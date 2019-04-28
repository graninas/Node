{-# LANGUAGE PackageImports #-}

module Enecuum.Core.Database.Interpreter where

import           Enecuum.Prelude
import qualified Enecuum.Core.Language as L
import qualified Enecuum.Core.Types as D
import qualified "rocksdb-haskell" Database.RocksDB as Rocks


-- TODO: think about read / write options.
-- https://task.enecuum.com/issues/2859

writeOpts :: Rocks.WriteOptions
writeOpts = Rocks.defaultWriteOptions { Rocks.sync = True }

-- | Interpret DatabaseL language.
interpretDatabaseL :: Rocks.DB -> L.DatabaseF db a -> IO a

-- TODO: Perhaps, this method can be implemented more effectively with using Bloom filter.
-- For now, it's just the same as GetValueRaw.
interpretDatabaseL db (L.HasKeyRaw key next) = do
    mbVal <- Rocks.get db Rocks.defaultReadOptions key
    pure $ next $ isJust mbVal

interpretDatabaseL db (L.GetValueRaw key next) = do
    mbVal <- Rocks.get db Rocks.defaultReadOptions key
    pure $ next $ case mbVal of
        Nothing  -> Left $ D.DBError D.KeyNotFound (show key)
        Just val -> Right val

interpretDatabaseL db (L.PutValueRaw key val next) = do
    -- TODO: catch exceptions, if any
    r <- Rocks.put db writeOpts key val
    pure $ next $ Right r

runDatabaseL ::  Rocks.DB -> L.DatabaseL db a -> IO a
runDatabaseL db = foldFree (interpretDatabaseL db)
