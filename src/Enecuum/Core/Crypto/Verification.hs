{-# LANGUAGE PackageImports      #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Enecuum.Core.Crypto.Verification (verifyEncodable) where

import           "cryptonite" Crypto.Hash (SHA3_256(..))
import           Crypto.PubKey.ECC.ECDSA (Signature, verify)
import           Data.Serialize (encode)
import           Enecuum.Prelude
import qualified Enecuum.Core.Crypto.Keys  as Enq

verifyEncodable :: Serialize msg => Enq.PublicKey -> Signature -> msg -> Bool
verifyEncodable publicKey signature msg = verify SHA3_256 (Enq.decompressPublicKey publicKey) signature (encode msg)
