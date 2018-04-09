{-# LANGUAGE GADTs, DeriveGeneric, TemplateHaskell #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

-- | Module provides types for storing internal state of a node and messages.
-- Different nodes use mutually overlapping set of messages
module Node.Node.Types where

import              Network.Socket
import              System.Clock
import qualified    Data.Set                        as S
import qualified    Data.ByteString                 as B
import qualified    Data.Bimap                      as BI
import              Data.Serialize
import              Data.Monoid
import qualified    Data.Map                        as M
import qualified    Crypto.PubKey.ECC.DH            as DH
import              GHC.Generics (Generic)
import              Control.Concurrent.Chan
import              Crypto.Random.Types
import              Crypto.PubKey.ECC.ECDSA         as ECDSA
import              Crypto.PubKey.ECC.Generate
import              Lens.Micro
import              Lens.Micro.TH

import              Node.Crypto
import              Node.Data.Data
import              Node.Data.NetPackage
import              Node.Data.NetMesseges
import              Node.Data.Lens
import              Node.Data.NodeTypes
import              Node.Template.Constructor
import              Sharding.Space.Point
import qualified    Sharding.Types.Node as N
import              Service.Types (Transaction, Microblock)

instance Show (Chan a) where
    show _ = "Chan"

data Msg where Msg :: B.ByteString -> Msg
type Transactions = [Transaction]
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
    ,   _chan            :: Chan MsgToSender
    ,   _nodePosition    :: Maybe NodePosition
    ,   _nodePort        :: PortNumber
    ,   _isBroadcast     :: Bool
    ,   _nodeHost        :: HostAddress
  }

makeLenses ''Node

data ManagerNodeData = ManagerNodeData {
        managerNodeDataNodeConfig   :: NodeConfig
    ,   managerNodeDataNodeBaseData :: NodeBaseData
    ,   managerTransactions         :: Chan Transaction
    ,   managerHashMap              :: BI.Bimap TimeSpec B.ByteString
    ,   managerPublicators          :: S.Set NodeId
    ,   managerSendedTransctions    :: BI.Bimap TimeSpec Transaction
  }

type IdIpPort = (NodeId, HostAddress, PortNumber)
type IpPort = (HostAddress, PortNumber)
type ShardingChan = Chan N.ShardingNodeAction
type MaybeChan a = Maybe (Chan a)

data NodeBaseData = NodeBaseData {
        nodeBaseDataExitChan            :: Chan ExitMsg
    ,   nodeBaseDataNodes               :: M.Map NodeId Node
    ,   nodeBaseDataBootNodes           :: BootNodeList
    ,   nodeBaseDataAnswerChan          :: Chan Answer
    ,   nodeBaseDataVacantPositions     :: BI.Bimap TimeSpec IdIpPort
    ,   nodeBaseDataBroadcastNum        :: Int
    ,   nodeBaseDataHostAddress         :: Maybe HostAddress
    ,   nodeBaseDataMicroblockChan      :: Chan Microblock
    ,   nodeBaseDataMyNodePosition      :: Maybe MyNodePosition
    ,   nodeBaseDataShardingChan        :: MaybeChan N.ShardingNodeAction
    ,   nodeBaseDataIAmBroadcast        :: Bool
  }


makeNodeBaseData aExitChan aList aAnswerChan aMicroblockChan = NodeBaseData
    aExitChan
    M.empty
    aList
    aAnswerChan
    BI.empty
    0
    Nothing
    aMicroblockChan
    Nothing
    Nothing
    False


data NodeConfig = NodeConfig {
    nodeConfigPrivateNumber :: DH.PrivateNumber,
    nodeConfigPublicPoint   :: DH.PublicPoint,
    nodeConfigPrivateKey    :: PrivateKey,
    nodeConfigMyNodeId      :: MyNodeId,
    nodeConfigPortNumber    :: PortNumber
  }
  deriving (Generic)


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
        :: Chan Transaction
        -> Chan Microblock
        -> Chan ExitMsg
        -> Chan Answer
        -> BootNodeList
        -> NodeConfig
        ->  a

instance ToManagerData ManagerNodeData where
    toManagerData aTransactionChan aMicroblockChan aExitChan aAnswerChan aList aNodeConfig = ManagerNodeData
        aNodeConfig (makeNodeBaseData aExitChan aList aAnswerChan aMicroblockChan)
            aTransactionChan BI.empty S.empty BI.empty


makeNewNodeConfig :: MonadRandom m => PortNumber -> m NodeConfig
makeNewNodeConfig aPort = do
    (aPublicKey,     aPrivateKey)  <- generate curve
    (aPrivateNumber, aPublicPoint) <- genKayPair curve
    let aId = keyToId aPublicKey
    pure $ NodeConfig aPrivateNumber aPublicPoint aPrivateKey (toMyNodeId aId) aPort


emptyData
    :: MonadRandom m
    => ToManagerData d
    => PortNumber
    -> Chan Transaction
    -> Chan Microblock
    -> Chan ExitMsg
    -> Chan Answer
    -> BootNodeList
    -> m d
emptyData aPort aTransactionChan aMicroblockChan aExitChan aAnswerChan aList =
    toManagerData aTransactionChan aMicroblockChan aExitChan aAnswerChan  aList
        <$> makeNewNodeConfig aPort

makePackageSignature
    ::  Serialize aPackage
    =>  ManagerData md
    =>  md
    ->  aPackage
    ->  IO PackageSignature
makePackageSignature aData aResponse = do
    aTime <- getTime Realtime
    let aNodeId = aData^.myNodeId
    aResponceSignature <- signEncodeble
        (aData^.privateKey)
        (aNodeId, aTime, aResponse)
    return $ PackageSignature aNodeId aTime aResponceSignature


lensInst "transactions" ["ManagerNodeData"]
    ["Chan", "Transaction"] "managerTransactions"

lensInst "hashMap" ["ManagerNodeData"]
    ["BI.Bimap", "TimeSpec", "B.ByteString"] "managerHashMap"

lensInst "publicators" ["ManagerNodeData"] ["S.Set", "NodeId"]
    "managerPublicators"

lensInst "sendedTransctions" ["ManagerNodeData"]
    ["BI.Bimap", "TimeSpec", "Transaction"] "managerSendedTransctions"





makeNode :: Chan MsgToSender -> HostAddress -> PortNumber -> Node
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
