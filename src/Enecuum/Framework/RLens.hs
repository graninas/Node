{-# LANGUAGE DuplicateRecordFields  #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE TemplateHaskell        #-}
{-# LANGUAGE UndecidableInstances   #-}

-- | Lenses for Framework Runtime types.
module Enecuum.Framework.RLens where

import           Control.Lens             ( makeFieldsNoPrefix )

import           Enecuum.Framework.Runtime

makeFieldsNoPrefix ''DBControl
makeFieldsNoPrefix ''DBHandle
makeFieldsNoPrefix ''NodeRuntime
