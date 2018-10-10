module Enecuum.Legacy.Service.System.Directory (
    getTime,
    getKeyFilePath,
    createFilesDirectory,
    getTransactionFilePath,
    getLedgerFilePath,
    getMicroblockFilePath,
    getMacroblockFilePath,
    getSproutFilePath,
    getLastFilePath
  )where

import           Data.UnixTime
import           Enecuum.Prelude
import           System.Directory      (createDirectoryIfMissing,
                                        getHomeDirectory)
import           System.FilePath       (pathSeparator)
import           System.FilePath.Posix (takeDirectory)


getTime :: IO Int
getTime = fromEnum <$> utSeconds <$> getUnixTime

getEnecuumDir :: IO FilePath
getEnecuumDir = do
    homeDir <- getHomeDirectory
    let enecuumDir = homeDir ++ [pathSeparator] ++ "enecuum"
    createDirectoryIfMissing True enecuumDir
    pure enecuumDir


getKeyFilePath :: IO FilePath
getKeyFilePath = do
    enecuumDir <- getEnecuumDir
    pure (enecuumDir ++ [pathSeparator] ++ "key.txt")


getTransactionFilePath :: IO FilePath
getTransactionFilePath = do
    enecuumDir <- getEnecuumDir
    pure (enecuumDir ++ [pathSeparator] ++ "tx.db")

getLedgerFilePath :: IO FilePath
getLedgerFilePath = do
    enecuumDir <- getEnecuumDir
    pure (enecuumDir ++ [pathSeparator] ++ "ledger.db")

getMicroblockFilePath :: IO FilePath
getMicroblockFilePath = do
    enecuumDir <- getEnecuumDir
    pure (enecuumDir ++ [pathSeparator] ++ "microblock.db")

getMacroblockFilePath :: IO FilePath
getMacroblockFilePath = do
    enecuumDir <- getEnecuumDir
    pure (enecuumDir ++ [pathSeparator] ++ "macroblock.db")

getSproutFilePath :: IO FilePath
getSproutFilePath = do
    enecuumDir <- getEnecuumDir
    pure (enecuumDir ++ [pathSeparator] ++ "sprout.db")

getLastFilePath :: IO FilePath
getLastFilePath = do
    enecuumDir <- getEnecuumDir
    pure (enecuumDir ++ [pathSeparator] ++ "last.db")

createFilesDirectory :: FilePath -> IO ()
createFilesDirectory path = createDirectoryIfMissing True $ takeDirectory path
