{-# LANGUAGE DuplicateRecordFields  #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE TemplateHaskell        #-}

-- | Lenses for Framework domain types.
module Enecuum.Framework.Lens where

import           Control.Lens             ( makeFieldsNoPrefix )

import           Enecuum.Framework.Domain

makeFieldsNoPrefix ''Address
makeFieldsNoPrefix ''Connection
makeFieldsNoPrefix ''NetworkRequest
makeFieldsNoPrefix ''NetworkResponse
