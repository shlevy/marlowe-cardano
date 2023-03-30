module Language.Marlowe.Runtime.Web.PostWithdrawal
  where

import Language.Marlowe.Runtime.Integration.Common
import qualified Language.Marlowe.Runtime.Web as Web
import Language.Marlowe.Runtime.Web.StandardContract
  ( StandardContractChoiceMade(..)
  , StandardContractClosed(..)
  , StandardContractFundsDeposited(..)
  , StandardContractInit(..)
  , StandardContractNotified(..)
  , createStandardContract
  )
import Test.Hspec (Spec, describe, it)
import Test.Integration.Marlowe.Local (withLocalMarloweRuntime)

spec :: Spec
spec = describe "POST /contracts/{contractId}/withdrawal" do
  it "returns the transaction header" $ withLocalMarloweRuntime $ runIntegrationTest do
    partyAWallet <- getGenesisWallet 0
    partyBWallet <- getGenesisWallet 1

    result <- runWebClient do
      StandardContractInit{makeInitialDeposit} <- createStandardContract partyAWallet partyBWallet
      StandardContractFundsDeposited{chooseGimmeTheMoney} <- makeInitialDeposit
      StandardContractChoiceMade{sendNotify} <- chooseGimmeTheMoney
      StandardContractNotified{makeReturnDeposit} <- sendNotify
      StandardContractClosed{withdrawPartyAFunds} <- makeReturnDeposit

      withdrawPartyAFunds

    case result of
      Left _ ->  fail $ "Expected 200 response code - got " <> show result
      Right (Web.WithdrawTxBody{}, _) ->  pure ()
