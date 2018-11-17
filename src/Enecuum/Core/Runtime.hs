module Enecuum.Core.Runtime where

import Enecuum.Prelude

import qualified Enecuum.Core.Types                as D
import qualified Enecuum.Core.Language             as L
import qualified Data.Map                          as Map
import qualified Data.ByteString.Base64            as Base64
import qualified Crypto.Hash.SHA256                as SHA
import qualified Enecuum.Core.Logger.Impl.HsLogger as Impl

-- | Runtime data for the concrete logger impl.
newtype LoggerRuntime = LoggerRuntime
    { _hsLoggerHandle :: Maybe Impl.HsLoggerHandle
    }

-- | Runtime data for core subsystems.
data CoreRuntime = CoreRuntime
    { _loggerRuntime :: LoggerRuntime
    , _stateRuntime  :: StateRuntime
    }

-- | Logger that can be used in runtime via the logging subsystem.
newtype RuntimeLogger = RuntimeLogger
    { logMessage' :: D.LogLevel -> D.Message -> IO ()
    }

newtype VarNumber = VarNumber Int

data VarHandle = VarHandle D.VarId (TVar Any)

instance D.StringHashable VarNumber where
  toHash (VarNumber n) = D.StringHash . Base64.encode . SHA.hash $ show ("VarNumber " +|| n ||+ "" :: String)

data DelayedLogEntry = DelayedLogEntry D.LogLevel D.Message
type DelayedLog = [DelayedLogEntry]

data StateRuntime = StateRuntime
    { _state      :: TMVar (Map.Map D.VarId VarHandle) -- ^ Node state.
    , _idCounter  :: TMVar Int                         -- ^ ID counter. Used to generate VarIds, ProcessIds.
    , _delayedLog :: TVar DelayedLog                   -- ^ Delayed log entries
    }

-- TODO: make it right
createVoidLoggerRuntime :: IO LoggerRuntime
createVoidLoggerRuntime = pure $ LoggerRuntime Nothing

createLoggerRuntime :: D.LoggerConfig -> IO LoggerRuntime
createLoggerRuntime config = LoggerRuntime . Just <$> Impl.setupLogger config

clearLoggerRuntime :: LoggerRuntime -> IO ()
clearLoggerRuntime (LoggerRuntime (Just hsLogger)) = Impl.teardownLogger hsLogger
clearLoggerRuntime _                               = pure ()

createStateRuntime :: IO StateRuntime
createStateRuntime = StateRuntime
    <$> newTMVarIO Map.empty
    <*> newTMVarIO 0
    <*> newTVarIO []

createCoreRuntime :: LoggerRuntime -> IO CoreRuntime
createCoreRuntime loggerRt = CoreRuntime loggerRt
    <$> createStateRuntime

clearCoreRuntime :: CoreRuntime -> IO ()
clearCoreRuntime _ = pure ()

mkRuntimeLogger :: LoggerRuntime -> RuntimeLogger
mkRuntimeLogger (LoggerRuntime hsLog) = RuntimeLogger
    { logMessage' = \lvl msg -> Impl.runLoggerL hsLog $ L.logMessage lvl msg
    }

-- Runtime log functions
logInfo' :: RuntimeLogger -> D.Message -> IO ()
logInfo' (RuntimeLogger l) = l D.Info

logError' :: RuntimeLogger -> D.Message -> IO ()
logError' (RuntimeLogger l) = l D.Error

logDebug' :: RuntimeLogger -> D.Message -> IO ()
logDebug' (RuntimeLogger l) = l D.Debug

logWarning' :: RuntimeLogger -> D.Message -> IO ()
logWarning' (RuntimeLogger l) = l D.Warning

getNextId :: StateRuntime -> STM Int
getNextId stateRt = do
    number <- takeTMVar $ _idCounter stateRt
    putTMVar (_idCounter stateRt) $ number + 1
    pure number
