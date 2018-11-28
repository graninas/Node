{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE RecordWildCards       #-}

module Enecuum.Blockchain.Domain.KBlock where

import qualified Crypto.Hash.SHA256         as SHA
import qualified Data.Bits                  as Bit
import qualified Data.ByteString            as B
import qualified Data.ByteString.Base64     as Base64
import qualified Data.ByteString.Internal   as BSI
import           Data.HGraph.StringHashable (StringHash (..), StringHashable, fromStringHash, toHash)
import           Data.Serialize.Put         (putWord32le, putWord8, runPut)
import qualified Data.Serialize.Put         as P
import           Enecuum.Prelude

-- TODO: Base64 encoded newtype wrapper

-- TODO: this should be exact time type.
type BlockTime   = Word32
type BlockNumber = Word32
type Nonce       = Word32
type Solver      = StringHash
type PrevHash    = StringHash
type NonceRange  = (Nonce, Nonce)
type Difficulty  = Word32

data KBlock = KBlock
    { _time     :: BlockTime
    , _prevHash :: PrevHash
    , _number   :: BlockNumber
    , _nonce    :: Nonce
    , _solver   :: Solver
    -- , _type      :: Int
    } deriving (Eq, Generic, Ord, Read, Show, ToJSON, FromJSON, Serialize)

instance StringHashable KBlock where
  toHash = StringHash . calcKBlockHashBase64

data KBlockValidity
    = NextKBlock      -- ^ KBlock is good, and it's next to the current top
    | FutureKBlock    -- ^ KBlock is good, and it's from the future (number > curNumber + 1)
    | PreviousKBlock  -- ^ KBlock is duplicated
    | ForkedKBlock    -- ^ KBlock number <= curNumber, but we don't have this KBlock in the graph
    | InvalidKBlock   -- ^ KBlock is bad


genesisHash :: StringHash
genesisHash = toHash genesisKBlock

-- N.B. Hash in base64 encoding
genesisIndicationHashStr :: IsString a => a
genesisIndicationHashStr = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

genesisIndicationHash :: StringHash
genesisIndicationHash = StringHash genesisIndicationHashStr

-- N.B. Hash in base64 encoding
genesisSolverStr :: IsString a => a
genesisSolverStr = "EMde81cgGToGrGWSNCqm6Y498qBpjEzRczBbvC5MV2Q="

genesisSolverHash :: StringHash
genesisSolverHash = StringHash genesisSolverStr

kBlockType :: Int
kBlockType = 0

genesisKBlock :: KBlock
genesisKBlock = KBlock
    { _time      = 0
    , _prevHash  = genesisIndicationHash
    , _number    = 0
    , _nonce     = 0
    , _solver    = genesisSolverHash
    }

calcKBlockHashBase64 :: KBlock -> ByteString
calcKBlockHashBase64 KBlock {..} = Base64.encode $ calcKBlockHashRaw
    _time
    _number
    _nonce
    (fromRight "" $ Base64.decode $ fromStringHash _prevHash)
    (fromRight "" $ Base64.decode $ fromStringHash _solver)

calcKBlockHashRaw
  :: BlockTime
  -> BlockNumber
  -> Nonce
  -> ByteString
  -> ByteString
  -> ByteString
calcKBlockHashRaw time number nonce prevHash solver = SHA.hash bstr
    where
    bstr = P.runPut $ do
          P.putWord8 (toEnum kBlockType)
          P.putWord32le   number
          P.putWord32le   time
          P.putWord32le   nonce
          P.putByteString prevHash
          P.putByteString solver

calcHashDifficulty :: ByteString -> Int
calcHashDifficulty = countZeros . countedBytes
  where
    countZeros []     = 0
    countZeros (8:bs) = 8 + countZeros bs
    countZeros (n:_)  = n
    countedBytes hash = map leadingZeroBitsCount (B.unpack hash)

leadingZeroBitsCount :: Word8 -> Int
leadingZeroBitsCount (Bit.complement -> number) = snd $ checkBit' number (True, 0) [7, 6..0]
  where
    checkBit' _ res []                 = res
    checkBit' n (True, cnt) (bit:bits) | Bit.testBit n bit = checkBit' n (True, cnt + 1) bits
    checkBit' _ (True, cnt) _          = (False, cnt)
    checkBit' _ res _                  = res
