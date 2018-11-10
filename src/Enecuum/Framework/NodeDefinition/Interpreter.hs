{-# LANGUAGE PackageImports #-}

module Enecuum.Framework.NodeDefinition.Interpreter where

import Enecuum.Prelude hiding (fromJust)
import qualified Data.Map                           as M
import           Data.Aeson                         as A
import           Control.Concurrent.STM.TChan
import           Control.Concurrent                 (killThread)
import qualified "rocksdb-haskell" Database.RocksDB as Rocks
import qualified Network.Socket.ByteString.Lazy     as S
import qualified Network.Socket                     as S hiding (recv)
import           Enecuum.Framework.Networking.Internal.Tcp.Server
import           Enecuum.Framework.Node.Interpreter        (runNodeL, setServerChan)
import           Enecuum.Framework.Runtime                 (NodeRuntime, DBHandle)
import qualified Enecuum.Framework.Language                as L
import qualified Enecuum.Framework.RLens                   as RLens
import qualified Enecuum.Core.Interpreters                 as Impl
import qualified Enecuum.Core.Runtime                      as Impl (getNextId)
import qualified Enecuum.Core.RLens                        as RLens
import qualified Enecuum.Framework.Node.Interpreter        as Impl
import qualified Enecuum.Framework.Domain.RPC              as D
import qualified Enecuum.Framework.Domain.Networking       as D
import qualified Enecuum.Framework.Domain.Process          as D
import           Enecuum.Framework.Handler.Rpc.Interpreter
import qualified Enecuum.Framework.Handler.Network.Interpreter    as Net
import qualified Enecuum.Framework.Networking.Internal.Connection as Con
import           Enecuum.Framework.Handler.Cmd.Interpreter as Cmd
import           Data.Aeson.Lens
import qualified Data.Text as T
import           System.Console.Haskeline
import           System.Console.Haskeline.History


getNextId :: NodeRuntime -> IO Int
getNextId nodeRt = atomically $ Impl.getNextId $ nodeRt ^. RLens.coreRuntime . RLens.stateRuntime

addProcess :: NodeRuntime -> D.ProcessPtr a -> ThreadId -> IO ()
addProcess nodeRt pPtr threadId = do
    pId <- D.getProcessId pPtr
    ps <- readTVarIO $ nodeRt ^. RLens.processes
    let newPs = M.insert pId threadId ps
    atomically $ writeTVar (nodeRt ^. RLens.processes) newPs

startServing
    :: (Impl.ConnectsLens a, Con.NetworkConnection a)
    => NodeRuntime -> S.PortNumber -> L.NetworkHandlerL a (Free L.NodeF) b -> IO b
startServing nodeRt port initScript = do
    m        <- atomically $ newTVar mempty
    a        <- Net.runNetworkHandlerL m initScript
    handlers <- readTVarIO m
    s        <- Con.startServer
        port
        ((\f a' b -> Impl.runNodeL nodeRt $ f a' b) <$> handlers)
        (\(D.Connection addr) -> Impl.insertConnect (nodeRt ^. Impl.connectsLens) addr)
        (Impl.logError' nodeRt)
    atomically $ setServerChan (nodeRt ^. RLens.servers) port s
    pure a

interpretNodeDefinitionL :: NodeRuntime -> L.NodeDefinitionF a -> IO a
interpretNodeDefinitionL nodeRt (L.NodeTag tag next) = do
    atomically $ writeTVar (nodeRt ^. RLens.nodeTag) tag
    pure $ next ()

interpretNodeDefinitionL nodeRt (L.EvalNodeL action next) = next <$> Impl.runNodeL nodeRt action

interpretNodeDefinitionL nodeRt (L.EvalCoreEffectNodeDefinitionF coreEffect next) =
    next <$> Impl.runCoreEffect (nodeRt ^. RLens.coreRuntime) coreEffect

interpretNodeDefinitionL nodeRt (L.ServingTcp port action next) =
    next <$> startServing nodeRt port action 

interpretNodeDefinitionL nodeRt (L.ServingUdp port action next) =
    next <$> startServing nodeRt port action 

interpretNodeDefinitionL nodeRt (L.StopServing port next) = do
    atomically $ do
        serversMap <- readTVar (nodeRt ^. RLens.servers)
        whenJust (serversMap ^. at port) Con.stopServer
    pure $ next ()

interpretNodeDefinitionL nodeRt (L.ServingRpc port action next) = do
    m <- atomically $ newTVar mempty
    a <- runRpcHandlerL m action
    s <- atomically $ takeServerChan (nodeRt ^. RLens.servers) port
    void $ forkIO $ runRpcServer s port (runNodeL nodeRt) m
    pure $ next a

interpretNodeDefinitionL nodeRt (L.Std handlers next) = do
    m <- atomically $ newTVar mempty
    _ <- runCmdHandlerL m handlers
    void $ forkIO $ do
        m'       <- readTVarIO m
        tag      <- readTVarIO (nodeRt ^. RLens.nodeTag)
        let 
            filePath = nodeRt ^. RLens.storyPaths.at tag
            inpStr = if tag == "Client" then "λ> " else ""
            loop   = do
                minput <- getInputLine inpStr
                case minput of
                    Nothing      -> pure ()
                    Just    line -> do
                        res <- liftIO $ callHandler nodeRt m' $ T.pack line
                        outputStrLn $ T.unpack res
                        whenJust filePath $ \path -> do
                            history <- getHistory
                            liftIO $ writeHistory path history
                        loop
                             
        runInputT defaultSettings{historyFile = filePath} loop
    pure $ next ()

-- TODO: make a separate language and use its interpreter in test runtime too.
interpretNodeDefinitionL nodeRt (L.ForkProcess action next) = do
    (pPtr, pVar) <- getNextId nodeRt >>= D.createProcessPtr
    threadId <- forkIO $ do
        res <- runNodeL nodeRt action
        atomically $ putTMVar pVar res
    addProcess nodeRt pPtr threadId
    pure $ next pPtr

interpretNodeDefinitionL _ (L.TryGetResult pPtr next) = do
    pVar <- D.getProcessVar pPtr
    mbResult <- atomically $ tryReadTMVar pVar
    pure $ next mbResult

interpretNodeDefinitionL _ (L.AwaitResult pPtr next) = do
    pVar <- D.getProcessVar pPtr
    result <- atomically $ takeTMVar pVar
    pure $ next result

callHandler :: NodeRuntime -> Map Text (Value -> L.NodeL Text) -> Text -> IO Text
callHandler nodeRt methods msg = do
    val <- try $ pure $ A.decode $ fromString $ T.unpack msg
    case val of
        Right (Just jval@((^? key "method" . _String) -> Just method)) -> 
            case methods ^. at method of
                Just justMethod -> Impl.runNodeL nodeRt $ justMethod jval
                Nothing         -> pure $ "The method " <> method <> " isn't supported."
        Right _                    -> pure "Error of request parsing."
        Left  (_ :: SomeException) -> pure "Error of request parsing."

-- TODO: treadDelay if server in port exist!!!
takeServerChan :: TVar (Map S.PortNumber (TChan D.ServerComand)) -> S.PortNumber -> STM (TChan D.ServerComand)
takeServerChan servs port = do
    chan <- newTChan
    Impl.setServerChan servs port chan
    pure chan


runRpcServer
    :: TChan D.ServerComand -> S.PortNumber -> (t -> IO D.RpcResponse) -> TVar (Map Text (A.Value -> Int -> t)) -> IO ()
runRpcServer chan port runner methodVar = do
    methods <- readTVarIO methodVar
    runTCPServer chan port $ \sock -> do
        msg      <- S.recv sock (1024 * 4)
        response <- callRpc runner methods msg
        S.sendAll sock $ A.encode response

callRpc :: Monad m => (t -> m D.RpcResponse) -> Map Text (A.Value -> Int -> t) -> LByteString -> m D.RpcResponse
callRpc runner methods msg = case A.decode msg of
    Just (D.RpcRequest method params reqId) -> case method `M.lookup` methods of
        Just justMethod -> runner $ justMethod params reqId
        Nothing         -> pure $ D.RpcResponseError (A.String $ "The method " <> method <> " isn't supported.") reqId
    Nothing -> pure $ D.RpcResponseError (A.String "error of request parsing") 0

runNodeDefinitionL :: NodeRuntime -> Free L.NodeDefinitionF a -> IO a
runNodeDefinitionL nodeRt = foldFree (interpretNodeDefinitionL nodeRt)

-- TODO: move it somewhere.
-- TODO: FIXME: stop network workers
clearNodeRuntime :: NodeRuntime -> IO ()
clearNodeRuntime nodeRt = do
    serverPorts <- M.keys  <$> readTVarIO (nodeRt ^. RLens.servers  )
    threadIds   <- M.elems <$> readTVarIO (nodeRt ^. RLens.processes)
    databases   <- M.elems <$> readTVarIO (nodeRt ^. RLens.databases)
    mapM_ (runNodeDefinitionL nodeRt . L.stopServing) serverPorts
    mapM_ killThread threadIds
    mapM_ releaseDB databases

-- TODO: move it somewhere.
releaseDB :: DBHandle -> IO ()
releaseDB dbHandle = Rocks.close $ dbHandle ^. RLens.db