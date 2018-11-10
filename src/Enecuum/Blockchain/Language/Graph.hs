module Enecuum.Blockchain.Language.Graph where

import qualified Enecuum.Blockchain.Domain          as D
import qualified Enecuum.Blockchain.Language.Ledger as L
import qualified Enecuum.Core.Language              as L
import qualified Enecuum.Core.Types                 as D
import qualified Enecuum.Framework.Domain           as D
import qualified Enecuum.Framework.Language         as L
import           Enecuum.Prelude

import Data.Map

-- | Get kBlock by Hash
getKBlock :: D.BlockchainData -> D.StringHash -> L.StateL (Maybe D.KBlock)
getKBlock bData hash = do
    (res, mbMsg) <- L.evalGraph (D._graph bData) $ do
        maybeKBlock <- L.getNode hash
        case maybeKBlock of
            Just (D.HNode _ _ (D.fromContent -> D.KBlockContent kBlock) _ _) -> pure (Just kBlock, Nothing)
            _ -> pure (Nothing, Just $ "KBlock not found by hash: " <> show hash)
    whenJust mbMsg L.logInfo
    pure res

-- Get Top kBlock
getTopKeyBlock :: D.BlockchainData -> L.StateL D.KBlock
getTopKeyBlock bData = do
    topNodeHash <- L.readVar (D._curNode bData)
    fromJust <$> getKBlock bData topNodeHash


-- | Add key block to the top of the graph
addTopKBlock :: Text -> D.BlockchainData -> D.KBlock -> L.StateL Bool
addTopKBlock kBlockSrc bData kBlock = do
    L.logInfo $ "Adding " +| kBlockSrc |+ " KBlock to the graph: " +|| kBlock ||+ "."
    let kBlock' = D.KBlockContent kBlock
    ref <- L.readVar (D._curNode bData)

    mBlocks <- fromMaybe [] <$> getMBlocksForKBlock bData ref
    forM_ mBlocks $ L.calculateLedger bData

    L.evalGraph (D._graph bData) $ do
        L.newNode kBlock'
        L.newLink ref kBlock'

    -- change of curNode.
    L.writeVar (D._curNode bData) $ D.toHash kBlock'
    pure True

-- | Add microblock to graph
addMBlock :: D.BlockchainData -> D.Microblock -> L.StateL Bool
addMBlock bData mblock@(D.Microblock hash _ _ _) = do
    kblock <- getKBlock bData hash

    unless (isJust kblock) $ L.logInfo $ "Can't add MBlock to the graph: KBlock not found (" +|| hash ||+ ")."

    when (isJust kblock) $ do
        L.logInfo $ "Adding MBlock to the graph for KBlock (" +|| hash ||+ ")."
        L.evalGraph (D._graph bData) $ do
            L.newNode (D.MBlockContent mblock)
            L.newLink hash (D.MBlockContent mblock)
    pure $ isJust kblock

getMBlocksForKBlock :: D.BlockchainData -> D.StringHash -> L.StateL (Maybe [D.Microblock])
getMBlocksForKBlock bData hash =  L.evalGraph (D._graph bData) $ do
    node <- L.getNode hash
    case node of
        Nothing -> pure Nothing
        Just (D.HNode _ _ _ links _) -> do
            aMBlocks                       <- forM (Data.Map.keys links) $ \aNRef -> do
                (D.HNode _ _ (D.fromContent -> block) _ _) <- fromJust <$> L.getNode aNRef
                case block of
                    D.MBlockContent mBlock -> pure $ Just mBlock
                    _               -> pure Nothing
            pure $ Just $ catMaybes aMBlocks

-- Return all blocks after given number as a list
findBlocksByNumber :: D.BlockchainData -> D.BlockNumber -> D.KBlock -> L.StateL [D.KBlock]
findBlocksByNumber bData num prev = do
    let cNum = D._number prev
    if  | cNum < num -> pure []
        | cNum == num -> pure [prev]
        | cNum > num -> do
            maybeNext <- getKBlock bData (D._prevHash prev)
            case maybeNext of
                Nothing   -> error "Broken chain"
                Just next -> (:) prev <$> findBlocksByNumber bData num next

kBlockIsNext :: D.KBlock -> D.KBlock -> Bool
kBlockIsNext kBlock topKBlock =
       D._number   kBlock == D._number topKBlock + 1
    && D._prevHash kBlock == D.toHash  topKBlock

-- TODO: this should check whether the KBlock is new or it's duplicated.
kBlockExists :: D.KBlock -> D.KBlock -> Bool
kBlockExists kBlock topKBlock = D._number kBlock <= D._number topKBlock
