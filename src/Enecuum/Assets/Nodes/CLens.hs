{-# LANGUAGE DuplicateRecordFields  #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE TemplateHaskell        #-}

-- | Lenses for node configs.
module Enecuum.Assets.Nodes.CLens where

import           Control.Lens                             (makeFieldsNoPrefix)
import           Enecuum.Prelude

import           Enecuum.Assets.Nodes.GraphService.Config
import           Enecuum.Config
import qualified Enecuum.Domain                           as D

makeFieldsNoPrefix ''DBConfig
makeFieldsNoPrefix ''GraphWindowConfig
makeFieldsNoPrefix ''GraphServiceConfig
