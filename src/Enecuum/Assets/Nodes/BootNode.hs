module Enecuum.Assets.Nodes.BootNode where

import           Enecuum.Prelude

import           Enecuum.Config (Config)
import qualified Enecuum.Language as L

bootNode :: Config -> L.NodeDefinitionL cfg ()
bootNode _ = do
    L.logInfo "Boot node starting..."
    L.logInfo "Boot node definition finished."
