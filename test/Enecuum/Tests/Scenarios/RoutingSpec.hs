module Enecuum.Tests.Scenarios.RoutingSpec where
  
import qualified Enecuum.Assets.Scenarios      as A
import qualified Enecuum.Domain                as D
import           Enecuum.Prelude
import           Enecuum.Testing.Integrational
import           Test.Hspec
import           Test.Hspec.Contrib.HUnit      (fromHUnitTest)
import           Test.HUnit

spec :: Spec
spec = describe "Routing tests" $ fromHUnitTest $ TestList
    []

{-
testRouting :: Test
testRouting = TestCase $ do
    startNode Nothing A.clientNode
    startNode Nothing A.bnNode
    -- waitForNode A.bnAddress
    -- threadDelay $ 1000 * 1000
    let ports = [5001..5010]
    forM ports (\port -> do
        startNode Nothing $ A.nnNode $ Just port
        -- waitForNode $ D.Address A.localhost port
        )
    let transmitter = D.Address A.localhost $ head ports
    let receivers = tail ports
    msg :: [Either Text Text] <- forM receivers (\receiver -> makeIORpcRequest A.clientAddress $ A.SendTo' transmitter receiver)

    print $ msg
    stopNode A.clientAddress
    -- stopNode A.bnAddress
    -- forM ports (\port -> stopNode $ D.Address A.localhost port)    
    True `shouldBe` True 
-}