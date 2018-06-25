{-# LANGUAGE
        GADTs
    ,   DeriveGeneric
    ,   TemplateHaskell
    ,   OverloadedStrings
    ,   TypeSynonymInstances
    ,   FlexibleInstances
    ,   MultiWayIf
    ,   MultiParamTypeClasses
  #-}

{-# OPTIONS_GHC -fno-warn-orphans #-}

-- | Module provides types for storing internal state of a node and messages.
-- Different nodes use mutually overlapping set of messages
module Node.Node.Types where

import              System.Clock
import qualified    Data.Set                        as S
import qualified    Data.ByteString                 as B
import qualified    Data.Bimap                      as BI
import              Data.Serialize
import              Data.Monoid
import qualified    Data.Map                        as M
import qualified    Crypto.PubKey.ECC.DH            as DH
import              GHC.Generics (Generic)
import qualified    Control.Concurrent.Chan         as C
import              Control.Concurrent.Chan.Unagi.Bounded

import              Crypto.Random.Types
import              Crypto.PubKey.ECC.ECDSA         as ECDSA
import              Lens.Micro
import              Lens.Micro.TH

import              Node.Crypto
import              Node.Data.Key
import              Node.Data.NetPackage
import              Node.Template.Constructor
import              Sharding.Space.Point
import qualified    Sharding.Types.Node as N
import              Service.Types (Transaction, Microblock)
import              Sharding.Space.Distance

import              Data.Scientific (toRealFloat, Scientific)
import              Data.Aeson
import              Data.Aeson.TH
import              Service.InfoMsg
import              Service.Network.Base (ConnectInfo, HostAddress, PortNumber, Connect)
import              PoA.Types
import              Node.FileDB.FileServer


data NodeVariantRole where
    BroadcastNode   :: NodeVariantRole
    SimpleNode      :: NodeVariantRole
    BootNode        :: NodeVariantRole
    PublicatorNode  :: NodeVariantRole
  deriving (Show, Eq, Ord, Generic)

type NodeVariantRoles = [NodeVariantRole]

instance Show (InChan a) where
    show _ = "InChan"
instance Serialize NodeVariantRole

type BootNodeList   = [(NodeId, Connect)]




data Msg where Msg :: B.ByteString -> Msg
type Transactions = [Transaction]

--
idLens :: Lens' a a
idLens = lens Prelude.id (\_ a -> a)

data Answer where
    StateRequestAnswer ::
        NodeVariantRoles
        -> MyNodeId
        -> Int
        -> Int
        -> Int
        -> Answer
    RawPackege :: B.ByteString -> Answer
  deriving Show

data ExitMsg where
    ExitMsg :: ExitMsg

data MsgToSender where
    MsgToSender     :: B.ByteString -> MsgToSender
    SenderExit      :: B.ByteString -> MsgToSender
    SenderTerminate :: MsgToSender

data MsgToMainActorFromPP
    = MicroblockFromPP Microblock PPId
    | BroadcastRequestFromPP B.ByteString IdFrom NodeType
    | NewConnectWithPP PPId NodeType (InChan NNToPPMessage)
    | MsgResendingToPP IdFrom IdTo B.ByteString
    | PoWListRequest IdFrom
  deriving (Show)

dataConstruct "MsgToNodeManager" $
    ((_1 .~ False) <$> managerMsgFuncListData) <>
    ((_1 .~ False) <$> managerMiningMsgListData)

dataConstruct "ManagerMsgBase" managerMsgFuncListData

dataConstruct "ManagerMiningMsgBase" $
    ((_1 .~ False) <$> managerMsgFuncListData) <>
    managerMiningMsgListData

msgClass []             "ManagerMsg" managerMsgFuncListFull
msgClass ["ManagerMsg"] "ManagerMiningMsg" managerMiningMsgListFull


baseMsgInstance "ManagerMsg" "ManagerMsgBase" managerMsgFuncList
baseMsgInstance "ManagerMiningMsg" "ManagerMiningMsgBase" managerMiningMsgList


derivativeMsgInstance "ManagerMsg" "MsgToNodeManager" managerMsgFuncList
derivativeMsgInstance "ManagerMsg" "ManagerMiningMsgBase" managerMsgFuncList

derivativeMsgInstance "ManagerMiningMsg" "MsgToNodeManager" managerMiningMsgList

data MsgToServer where
    KillMsg       :: MsgToServer

data NodeStatus = Active | Noactive deriving (Show, Eq)

data Node = Node {
        _status          :: NodeStatus
    ,   _mKey            :: Maybe StringKey
    ,   _chan            :: C.Chan MsgToSender
    ,   _nodePosition    :: Maybe NodePosition
    ,   _nodePort        :: PortNumber
    ,   _isBroadcast     :: Bool
    ,   _nodeHost        :: HostAddress
  }
  deriving (Eq)

makeLenses ''Node

data ManagerNodeData = ManagerNodeData {
        managerNodeDataNodeConfig   :: NodeConfig
    ,   managerNodeDataNodeBaseData :: NodeBaseData
    ,   managerTransactions         :: C.Chan Transaction
    ,   managerHashMap              :: BI.Bimap TimeSpec B.ByteString
    ,   managerPoWNodes             :: BI.Bimap TimeSpec PPId
    ,   managerPublicators          :: S.Set NodeId
    ,   managerSendedTransctions    :: BI.Bimap TimeSpec Transaction
  }

type ShardingChan = C.Chan N.ShardingNodeAction
type MaybeChan a = Maybe (C.Chan a)

data PPNode = PPNode {
        _ppType :: NodeType
    ,   _ppChan :: InChan NNToPPMessage
  }
  deriving (Eq)



data NodeBaseData = NodeBaseData {
        nodeBaseDataExitChan            :: C.Chan ExitMsg
    ,   nodeBaseDataNodes               :: M.Map NodeId Node
    ,   nodeBaseDataPpNodes             :: M.Map PPId PPNode
    ,   nodeBaseDataBootNodes           :: BootNodeList
    ,   nodeBaseDataAnswerChan          :: C.Chan Answer
    ,   nodeBaseDataBroadcastNum        :: Int
    ,   nodeBaseDataHostAddress         :: Maybe HostAddress
    ,   nodeBaseDataMicroblockChan      :: C.Chan Microblock
    ,   nodeBaseDataMyNodePosition      :: Maybe MyNodePosition
    ,   nodeBaseDataShardingChan        :: MaybeChan N.ShardingNodeAction
    ,   nodeBaseDataIAmBroadcast        :: Bool
    ,   nodeBaseDataOutPort             :: PortNumber
    ,   nodeBaseDataInfoMsgChan         :: C.Chan InfoMsg
    ,   nodeBaseDataFileServerChan      :: C.Chan FileActorRequest
  }



makeNodeBaseData
    ::  C.Chan ExitMsg
    ->  BootNodeList
    ->  C.Chan Answer
    ->  C.Chan Microblock
    ->  PortNumber
    ->  C.Chan InfoMsg
    ->  C.Chan FileActorRequest
    ->  NodeBaseData
makeNodeBaseData aExitChan aList aAnswerChan aMicroblockChan = NodeBaseData
    aExitChan M.empty M.empty aList aAnswerChan 0 Nothing aMicroblockChan
    Nothing Nothing False

-- | TODO: shoud be refactord: reduce keys count.
data NodeConfig = NodeConfig {
    nodeConfigPrivateNumber :: DH.PrivateNumber,
    nodeConfigPublicPoint   :: DH.PublicPoint,
    nodeConfigPrivateKey    :: PrivateKey,
    nodeConfigMyNodeId      :: MyNodeId
  }
  deriving (Generic)
$(deriveJSON defaultOptions ''NodeConfig)

type Token = Integer

data RPCBuildConfig where
     RPCBuildConfig :: {
        rpcPort        :: PortNumber,
        enableIP       :: [String],
        accessToken    :: Maybe Token
  } -> RPCBuildConfig
  deriving (Generic)

data SimpleNodeBuildConfig where
     SimpleNodeBuildConfig :: {
        sharding       :: Bool,
        cliMode        :: String,  -- "off", "rpc" or ""cli
        rpcBuildConfig :: Maybe RPCBuildConfig
  } -> SimpleNodeBuildConfig
  deriving (Generic)

instance ToJSON PortNumber where
  toJSON pn = Number $ fromInteger $ toInteger pn

toDouble :: Scientific -> Double
toDouble = toRealFloat

instance FromJSON PortNumber where
    parseJSON (Number s) = return.toEnum.fromEnum.toDouble $ s
    parseJSON _          = error "i've felt with the portnumber parsing"


$(deriveJSON defaultOptions ''RPCBuildConfig)
$(deriveJSON defaultOptions ''SimpleNodeBuildConfig)

$(deriveJSON defaultOptions ''ConnectInfo)

data BuildConfig where
     BuildConfig :: {
        extConnectPort        :: PortNumber,
        poaPort               :: PortNumber,
        bootNodeList          :: String,
        simpleNodeBuildConfig :: Maybe SimpleNodeBuildConfig,
        statsdBuildConfig     :: ConnectInfo,
        logsBuildConfig       :: ConnectInfo
  } -> BuildConfig
  deriving (Generic)

$(deriveJSON defaultOptions ''BuildConfig)



genDataClass        "nodeConfig" nodeConfigList
genBazeDataInstance "nodeConfig" (fst <$> nodeConfigList)

genDataClass        "nodeBaseData" nodeBaseDataList
genBazeDataInstance "nodeBaseData" (fst <$> nodeBaseDataList)

instance Serialize NodeConfig

class (NodeConfigClass a, NodeBaseDataClass a) => ManagerData a
instance ManagerData ManagerNodeData


mapM (uncurry makeLensInstance') [
        ("nodeConfig", "managerNodeData")
    ,   ("nodeBaseData", "managerNodeData")
    ]


instance Serialize PrivateKey where
    get = PrivateKey <$> get <*> get
    put (PrivateKey a b)= put a >> put b

class ToManagerData a where
    toManagerData
        :: C.Chan Transaction
        -> C.Chan Microblock
        -> C.Chan ExitMsg
        -> C.Chan Answer
        -> C.Chan InfoMsg
        -> C.Chan FileActorRequest
        -> BootNodeList
        -> NodeConfig
        -> PortNumber
        ->  a

instance ToManagerData ManagerNodeData where
    toManagerData aTransactionChan aMicroblockChan aExitChan aAnswerChan aInfoChan aFileRequestChan aList aNodeConfig aOutPort = ManagerNodeData
        aNodeConfig (makeNodeBaseData aExitChan aList aAnswerChan aMicroblockChan aOutPort aInfoChan aFileRequestChan)
            aTransactionChan BI.empty BI.empty S.empty BI.empty


makeNewNodeConfig :: MonadRandom m => m NodeConfig
makeNewNodeConfig = do
    (aPublicKey,     aPrivateKey)  <- generateKeyPair
    (aPrivateNumber, aPublicPoint) <- genKeyPair curve_256
    let aId = keyToId aPublicKey
    pure $ NodeConfig aPrivateNumber aPublicPoint aPrivateKey (toMyNodeId aId)

-- FIXME: find a right place.
makePackageSignature
    ::  Serialize aPackage
    =>  ManagerData md
    =>  md
    ->  aPackage
    ->  IO PackageSignature
makePackageSignature aData aResponse = do
    aTime <- getTime Realtime
    let aNodeId = aData^.myNodeId
    aResponseSignature <- signEncodeble
        (aData^.privateKey)
        (aNodeId, aTime, aResponse)
    return $ PackageSignature aNodeId aTime aResponseSignature


lensInst "transactions" ["ManagerNodeData"]
    ["C.Chan", "Transaction"] "managerTransactions"

lensInst "hashMap" ["ManagerNodeData"]
    ["BI.Bimap", "TimeSpec", "B.ByteString"] "managerHashMap"

lensInst "publicators" ["ManagerNodeData"] ["S.Set", "NodeId"]
    "managerPublicators"

lensInst "sendedTransctions" ["ManagerNodeData"]
    ["BI.Bimap", "TimeSpec", "Transaction"] "managerSendedTransctions"


lensInst "poWNodes" ["ManagerNodeData"] ["BI.Bimap", "TimeSpec", "PPId"]
    "managerPoWNodes"

makeNode :: C.Chan MsgToSender -> HostAddress -> PortNumber -> Node
makeNode aChan aHostAdress aPortNumber = Node {
        _status         = Noactive
    ,   _mKey           = Nothing
    ,   _chan           = aChan
    ,   _nodePosition   = Nothing
    ,   _nodePort       = aPortNumber
    ,   _isBroadcast    = False
    ,   _nodeHost       = aHostAdress
  }


defaultServerPort :: PortNumber
defaultServerPort = 3000


makeLenses ''PPNode

--
--
instance DistanceTo Node Point where
    distanceTo aNode aPoint = if
        | Just aPosition <- aNode^.nodePosition ->
            distanceTo aPosition  (NodePosition aPoint)
        | otherwise                             -> maxBound

instance DistanceTo Node PointTo where
    distanceTo aNode aPoint = distanceTo aNode (toPoint aPoint)
