{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}

module Enecuum.Legacy.Node.NetLvl.Server (
    netLvlServer,
    msgReceiver,
    msgSender,
    sendActionToCentralActor
  )  where

import qualified Control.Concurrent                               as C
import           Control.Concurrent.MVar
import           Control.Concurrent.Chan.Unagi.Bounded
import           Control.Monad
import           Control.Exception
import           Data.Aeson                                       as A
import qualified Data.Text                                        as T
import           Enecuum.Legacy.Node.Data.GlobalLoging
import           Enecuum.Legacy.Node.DataActor
import           Enecuum.Legacy.Node.NetLvl.Messages
import           Enecuum.Legacy.Node.Node.Types
import           Enecuum.Legacy.Pending
import           Enecuum.Legacy.Service.Network.Base
import           Enecuum.Legacy.Service.Network.WebSockets.Server
import           Enecuum.Legacy.Service.System.Version
import           Enecuum.Legacy.Service.Types                     (InfoMsg (..), LoggingTag (..),
                                                                   MsgType (..))
import qualified Network.WebSockets                               as WS
import           System.Random.Shuffle

import           Control.Concurrent.Async
import qualified Data.ByteString.Internal                         as BSI
import           Data.Maybe                                       ()
import           Enecuum.Legacy.Node.Data.Key
import           Enecuum.Legacy.Service.Sync.SyncJson
import           Prelude


netLvlServer :: MyNodeId
                -> PortNumber
                -> InChan MsgToCentralActor
                -> InChan InfoMsg
                -> InChan (DataActorRequest Connect)
                -> InChan PendingAction
                -> InChan BSI.ByteString
                -> IO ()
netLvlServer (MyNodeId aMyNodeId) aReceivePort ch aInfoChan aFileServerChan inChanPending aInChan = do
    writeLog aInfoChan [ServePoATag, InitTag] Info $
        "Init. NetLvlServer: a port is " ++ show aReceivePort
    runServer aReceivePort ("server of SN: " ++ show aMyNodeId) $ \aIp aPending -> do
        aConnect <- WS.acceptRequest aPending
        writeLog aInfoChan [ServePoATag] Info $ "New connect: " ++ showHostAddress aIp
        WS.forkPingThread aConnect 30
        aMsg <- WS.receiveData aConnect
        case A.eitherDecodeStrict aMsg of
            Right (ActionConnect aNodeType (Just aNodeId))
                | NodeId aMyNodeId /= aNodeId -> do
                    (aInpChan, aOutChan) <- newChan 64

                    when (aNodeType == NN) .
                        WS.sendTextData aConnect . A.encode $ ActionConnect NN (Just (NodeId aMyNodeId))

                    sendActionToCentralActor ch $ NewConnect aNodeId aNodeType aInpChan Nothing

                    void $ race
                        (msgSender ch aNodeId aConnect aOutChan)
                        (msgReceiver ch aInfoChan aFileServerChan aNodeType (IdFrom aNodeId) aConnect inChanPending aInChan)

            Right (ActionConnect aNodeType Nothing) -> do
                aNodeId <- generateClientId []
                WS.sendTextData aConnect $ A.encode $ ResponseNodeId aNodeId
                (aInpChan, aOutChan) <- newChan 64
                sendActionToCentralActor ch $ NewConnect aNodeId aNodeType aInpChan Nothing

                void $ race
                    (msgSender ch aNodeId aConnect aOutChan)
                    (msgReceiver ch aInfoChan aFileServerChan aNodeType (IdFrom aNodeId) aConnect inChanPending aInChan)

            Right _ -> do
                writeLog aInfoChan [ServePoATag] Warning $ "Broken message from PP " ++ show aMsg
                WS.sendTextData aConnect $ T.pack ("{\"tag\":\"Response\",\"type\":\"ErrorOfConnect\", \"Msg\":" ++ show aMsg ++ ", \"comment\" : \"not a connect msg\"}")

            Left a -> do
                writeLog aInfoChan [ServePoATag] Warning $ "Broken message from PP " ++ show aMsg ++ " " ++ a ++ " ip: " ++ showHostAddress aIp
                WS.sendTextData aConnect $ T.pack ("{\"tag\":\"Response\",\"type\":\"ErrorOfConnect\", \"reason\":\"" ++ a ++ "\", \"Msg\":" ++ show aMsg ++"}")


msgSender
    ::  ToJSON a1
    =>  InChan MsgToCentralActor
    ->  NodeId
    ->  WS.Connection
    ->  OutChan a1
    ->  IO a2
msgSender ch aId aConnect aNewChan = forever (WS.sendTextData aConnect . A.encode =<< readChan aNewChan)
    `finally` writeChan ch (NodeIsDisconnected aId)


msgReceiver :: InChan MsgToCentralActor
               -> InChan InfoMsg
               -> InChan (DataActorRequest Connect)
               -> NodeType
               -> IdFrom
               -> WS.Connection
               -> InChan PendingAction
               -> InChan BSI.ByteString
               -> IO b
msgReceiver ch aInfoChan aFileServerChan aNodeType aId aConnect aPendingChan aInChan = forever $ do
    aMsg <- WS.receiveData aConnect
    let aLog bMsg  = writeLog aInfoChan [ServePoATag] Info bMsg
        aSend bMsg = WS.sendTextData aConnect $ A.encode bMsg
    aLog $ "Raw msg: " ++ show aMsg ++ "\n"
    case A.eitherDecodeStrict aMsg of
        Right a -> case a of
            -- REVIEW: Check fair distribution of transactions between nodes
            RequestTransaction aNum -> void $ C.forkIO $ do
                aTmpChan <- C.newChan
                writeInChan aPendingChan $ GetTransaction aNum aTmpChan
                aTransactions <- C.readChan aTmpChan
                aLog    "Sending of transactions to client node."
                aSend $ ResponseTransactions aTransactions

            RequestPotentialConnects _ -> do
                aShuffledRecords <- shuffleM =<< getRecords aFileServerChan
                let aConnects = take 5 aShuffledRecords
                aLog  $ "Sending of connections: " ++ show aConnects
                aSend $ ResponsePotentialConnects aConnects

            RequestPoWList -> do
                aLog $ "PoWListRequest the msg from " ++ show aId
                sendActionToCentralActor ch $ RequestListOfPoW aId

            RequestVersion -> do
                aLog  $ "Version request from client node."
                aSend $ ResponseVersion $(version)

            RequestPending (Just aTransaction) -> do
                aTmpChan <- C.newChan
                writeInChan aPendingChan $ IsInPending aTransaction aTmpChan
                aTransactions <- C.readChan aTmpChan
                aLog  $ "Pending request from client node."
                aSend $ ResponseTransactionIsInPending aTransactions

            RequestPending Nothing -> do
                aTmpChan <- C.newChan
                writeInChan aPendingChan $ GetPending aTmpChan
                aTransactions <- C.readChan aTmpChan
                aSend $ ResponseTransactions aTransactions


            RequestActualConnects -> do
                aMVar <- newEmptyMVar
                sendActionToCentralActor ch $ RequestActualConnectList aMVar
                aVar <- takeMVar aMVar
                aSend $ ResponseActualConnects aVar
            --
            aMessage -> do
                writeLog aInfoChan [ServePoATag] Info $ "Received msg " ++ show aMessage
                sendMsgToCentralActor ch aNodeType aMessage
                when (isBlock aMessage) $ writeInChan aInChan aMsg

        Left l -> do
            case A.eitherDecodeStrict aMsg of
                Right (a :: SyncMessage) -> do
                    let IdFrom aNodeId = aId
                    writeInChan ch (SyncToNode a aNodeId)
                Left a -> do
                    writeLog aInfoChan [ServePoATag] Warning $ "Broken message from PP " ++ show aMsg ++ " " ++ l
                    WS.sendTextData aConnect $ T.pack ("{\"tag\":\"Response\",\"type\":\"Error\", \"reason\":\"" ++ a ++ "\", \"Msg\":" ++ show aMsg ++"}")


writeInChan :: InChan t -> t -> IO ()
writeInChan aChan aMsg = do
    aOk <- tryWriteChan aChan aMsg
    C.threadDelay 10000
    unless aOk $ writeInChan aChan aMsg

sendMsgToCentralActor :: InChan MsgToCentralActor -> NodeType -> NetMessage -> IO ()
sendMsgToCentralActor aChan aNodeType aMsg = writeInChan aChan (MsgFromNode aNodeType aMsg)


sendActionToCentralActor :: InChan MsgToCentralActor -> MsgFromNode -> IO ()
sendActionToCentralActor aChan aMsg = writeInChan aChan (ActionFromNode aMsg)