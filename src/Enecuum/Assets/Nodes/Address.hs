module Enecuum.Assets.Nodes.Address where

import qualified Enecuum.Domain                as D


graphNodeTransmitterRpcPort, graphNodeTransmitterTcpPort :: D.PortNumber
graphNodeTransmitterRpcPort = 2008
graphNodeTransmitterTcpPort = 3001

graphNodeReceiverRpcPort :: D.PortNumber
graphNodeReceiverRpcPort    = 2009

graphNodeTransmitterRpcAddress, graphNodeTransmitterTcpAddress :: D.Address
graphNodeTransmitterRpcAddress = D.Address "127.0.0.1" graphNodeTransmitterRpcPort
graphNodeTransmitterTcpAddress = D.Address "127.0.0.1" graphNodeTransmitterTcpPort

graphNodeReceiverRpcAddress :: D.Address
graphNodeReceiverRpcAddress = D.Address "127.0.0.1" graphNodeReceiverRpcPort


powNodeRpcPort :: D.PortNumber
powNodeRpcPort = 2005

powNodeRpcAddress :: D.Address
powNodeRpcAddress = D.Address "127.0.0.1" powNodeRpcPort

poaNodePort :: D.PortNumber
poaNodePort = 2006

poaNodeAddress :: D.Address
poaNodeAddress = D.Address "127.0.0.1" poaNodePort

