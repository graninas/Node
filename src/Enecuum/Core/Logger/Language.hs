{-# LANGUAGE GADTs           #-}
{-# LANGUAGE TemplateHaskell #-}

module Enecuum.Core.Logger.Language where

import qualified Enecuum.Core.Types as T (LogLevel (..))
import           Enecuum.Prelude

type MesType = Text

data LoggerF next where
  -- | Log message with a predefined level.
  LogMessage :: T.LogLevel -> MesType -> (() -> next) -> LoggerF next

instance Functor LoggerF where
  fmap g (LogMessage level msg next) = LogMessage level msg (g . next)

type LoggerL next = Free LoggerF next

class Logger m where
  logMessage :: T.LogLevel -> MesType -> m ()
instance Logger (Free LoggerF) where
  logMessage level msg = liftF $ LogMessage level msg id

-- | Log message with Info level.
logInfo :: Logger m => MesType -> m ()
logInfo = logMessage T.Info
