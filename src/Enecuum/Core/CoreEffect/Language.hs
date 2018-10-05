module Enecuum.Core.CoreEffect.Language
  ( CoreEffectF (..)
  , CoreEffect
  , evalLogger
  ) where

import           Enecuum.Prelude

import           Enecuum.Core.Logger.Language (Logger, LoggerL, logMessage)
import           Enecuum.Core.Random.Language (ERandom, ERandomL, getRandomInt, evalRand)
import           Enecuum.Core.ControlFlow.Language (ControlFlowL, ControlFlow(..))

-- | Core effects container language.
data CoreEffectF next where
  -- | Logger effect
  EvalLogger      :: LoggerL ()     -> (() -> next) -> CoreEffectF next
  -- | Random effect
  EvalRandom      :: ERandomL a     -> (a  -> next) -> CoreEffectF next
  EvalControlFlow :: ControlFlowL a -> (a  -> next) -> CoreEffectF next

instance Functor CoreEffectF where
  fmap g (EvalLogger logger next) = EvalLogger logger (g . next)
  fmap g (EvalRandom n next)      = EvalRandom n (g . next)
  fmap g (EvalControlFlow n next) = EvalControlFlow n (g .next)

type CoreEffect next = Free CoreEffectF next

evalLogger :: LoggerL () -> CoreEffect ()
evalLogger logger = liftF $ EvalLogger logger id

instance Logger (Free CoreEffectF) where
  logMessage level msg = evalLogger $ logMessage level msg

evalRandom :: ERandomL a -> CoreEffect a
evalRandom g = liftF $ EvalRandom g id

evalControlFlow :: ControlFlowL a -> CoreEffect a
evalControlFlow a = liftF $ EvalControlFlow a id

instance ERandom (Free CoreEffectF) where
  getRandomInt = evalRandom . getRandomInt
  evalRand r g = evalRandom $ evalRand r g

instance ControlFlow (Free CoreEffectF) where
  delay i = evalControlFlow $ delay i