{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Main where

import Control.Lens ((&), (.~), (?~))
import Control.Monad (replicateM)
import Control.Monad.Reader (ReaderT (runReaderT), runReader)
import Data.Aeson (ToJSON, Value (Null))
import Data.Aeson.Encode.Pretty (encodePrettyToTextBuilder)
import qualified Data.ByteString as BS
import Data.Coerce (coerce)
import Data.Data (Typeable)
import Data.Functor ((<&>))
import qualified Data.HashMap.Strict.InsOrd as IOHM
import Data.Kind (Type)
import Data.OpenApi (
  HasDescription (description),
  HasOneOf (oneOf),
  HasProperties (properties),
  HasRequired (required),
  HasType (type_),
  OpenApiType (OpenApiBoolean, OpenApiInteger, OpenApiString),
  Pattern,
  Reference (Reference),
  Referenced (Inline, Ref),
  Schema,
  ToSchema,
 )
import Data.Proxy (Proxy (Proxy))
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Internal.Builder as TB
import qualified Data.Text.Lazy as TL
import Language.Marlowe (TransactionInput (..))
import qualified Language.Marlowe.Core.V1.Semantics.Types as Semantics (Input (..))
import qualified Language.Marlowe.Core.V1.Semantics.Types as V1
import Language.Marlowe.Object.Gen ()
import Language.Marlowe.Runtime.Transaction.Gen ()
import qualified Language.Marlowe.Runtime.Web.API as Web (
  RuntimeAPI,
 )
import qualified Language.Marlowe.Runtime.Web.Adapter.Links as Web
import Language.Marlowe.Runtime.Web.Adapter.Servant (WithRuntimeStatus)
import qualified Language.Marlowe.Runtime.Web.Adapter.Servant as Web
import Language.Marlowe.Runtime.Web.Contract.API (ContractOrSourceId (..))
import qualified Language.Marlowe.Runtime.Web.Contract.API as Web
import qualified Language.Marlowe.Runtime.Web.Core.Address as Web
import qualified Language.Marlowe.Runtime.Web.Core.Asset as Web
import qualified Language.Marlowe.Runtime.Web.Core.Base16 as Web
import qualified Language.Marlowe.Runtime.Web.Core.BlockHeader as Web
import qualified Language.Marlowe.Runtime.Web.Core.MarloweVersion as Web
import qualified Language.Marlowe.Runtime.Web.Core.Metadata as Web
import qualified Language.Marlowe.Runtime.Web.Core.Party as Web
import qualified Language.Marlowe.Runtime.Web.Core.Roles as Web
import qualified Language.Marlowe.Runtime.Web.Core.Tx as Web
import Language.Marlowe.Runtime.Web.OpenAPIServer (
  OpenApiLintEnvironment (..),
  OpenApiLintIssue (..),
  OpenApiWithEmptySecurity (..),
  lintOpenApi,
  lookupFieldType,
  lookupType,
  openApi,
  schemaRule1Check,
 )
import qualified Language.Marlowe.Runtime.Web.Payout.API as Web

import GHC.Generics (Generic)
import Language.Marlowe.Analysis.Safety.Types (
  SafetyError (MissingRolesCurrency),
 )
import qualified Language.Marlowe.Analysis.Safety.Types as Web
import qualified Language.Marlowe.Runtime.Web.Role.API as Web
import qualified Language.Marlowe.Runtime.Web.Role.TokenFilter as Web
import qualified Language.Marlowe.Runtime.Web.Tx.API as Web
import qualified Language.Marlowe.Runtime.Web.Withdrawal.API as Web
import Servant.API (
  Headers,
  ReqBody',
  Verb,
  type (:<|>),
  type (:>),
 )
import Servant.OpenApi (validateEveryToJSONWithPatternChecker)
import Spec.Marlowe.Semantics.Arbitrary (
  ValidContractStructure (unValidContractStructure),
 )
import Spec.Marlowe.Semantics.Next.Arbitrary ()
import Test.Hspec (Spec, describe, hspec, it, shouldBe)
import Test.Hspec.Golden (defaultGolden)
import Test.QuickCheck (Arbitrary (..), Gen, chooseInt, elements, genericShrink, listOf, oneof, resize, sized, suchThat)
import Test.QuickCheck.Instances ()
import Text.Regex.Posix ((=~))

main :: IO ()
main = hspec do
  describe "OpenAPI" openAPISpec

openAPISpec :: Spec
openAPISpec = do
  describe "linter" do
    it "finds no problems with empty schema" do
      let actual = lintOpenApi mempty
          expected :: [OpenApiLintIssue] = []
      actual `shouldBe` expected

    it "finds no problems with the Marlowe Runtime OpenApi Schema" do
      let actual = lintOpenApi $ coerce openApi
          expected :: [OpenApiLintIssue] = []
      actual `shouldBe` expected

    describe "lookupType" do
      it "test 00" do
        let linterEnv :: OpenApiLintEnvironment
            linterEnv = OpenApiLintEnvironment mempty
            input :: Schema
            input = mempty
            actual = runReader (lookupType input) linterEnv
            expected = []
        actual `shouldBe` expected
      it "test 01" do
        let linterEnv :: OpenApiLintEnvironment
            linterEnv = OpenApiLintEnvironment mempty
            input :: Schema
            input = mempty & type_ ?~ OpenApiBoolean
            actual = runReader (lookupType input) linterEnv
            expected = [OpenApiBoolean]
        actual `shouldBe` expected

      it "test 02" do
        let linterEnv :: OpenApiLintEnvironment
            linterEnv = OpenApiLintEnvironment mempty
            input :: Schema
            input =
              mempty
                & oneOf
                  ?~ [ Inline (mempty & type_ ?~ OpenApiString)
                     , Inline (mempty & type_ ?~ OpenApiString)
                     , Inline (mempty & type_ ?~ OpenApiBoolean)
                     ]
            actual = runReader (lookupType input) linterEnv
            expected = [OpenApiString, OpenApiBoolean]
        actual `shouldBe` expected

      it "test 03" do
        let linterEnv :: OpenApiLintEnvironment
            linterEnv = OpenApiLintEnvironment mempty
            input :: Schema
            input =
              mempty
                & oneOf
                  ?~ [ Ref (Reference "mydef")
                     , Inline (mempty & type_ ?~ OpenApiString)
                     , Inline (mempty & type_ ?~ OpenApiBoolean)
                     ]
            actual = runReader (lookupType input) linterEnv
            expected = []
        actual `shouldBe` expected

      it "test 04" do
        let linterEnv :: OpenApiLintEnvironment
            linterEnv =
              OpenApiLintEnvironment $
                IOHM.fromList
                  [ ("mydef", mempty & type_ ?~ OpenApiInteger)
                  ]
            input :: Schema
            input =
              mempty
                & oneOf
                  ?~ [ Ref (Reference "mydef")
                     , Inline (mempty & type_ ?~ OpenApiString)
                     , Inline (mempty & type_ ?~ OpenApiBoolean)
                     ]
            actual = runReader (lookupType input) linterEnv
            expected = [OpenApiInteger, OpenApiString, OpenApiBoolean]
        actual `shouldBe` expected

    describe "lookupFieldType" do
      it "test 00" do
        let linterEnv :: OpenApiLintEnvironment
            linterEnv = OpenApiLintEnvironment mempty
            input :: Schema
            input = mempty
            actual = runReader (lookupFieldType "hey" input) linterEnv
            expected = Nothing
        actual `shouldBe` expected

      it "test 01" do
        let linterEnv :: OpenApiLintEnvironment
            linterEnv = OpenApiLintEnvironment mempty
            input :: Schema
            input = mempty & properties .~ IOHM.fromList [("hey", Inline (mempty & description ?~ "no type!"))]
            actual = runReader (lookupFieldType "hey" input) linterEnv
            expected = Nothing
        actual `shouldBe` expected

      it "test 02" do
        let linterEnv :: OpenApiLintEnvironment
            linterEnv = OpenApiLintEnvironment mempty
            input :: Schema
            input = mempty & properties .~ IOHM.fromList [("hey", Inline (mempty & type_ ?~ OpenApiBoolean))]
            actual = runReader (lookupFieldType "hey" input) linterEnv
            expected = Just [OpenApiBoolean]
        actual `shouldBe` expected

      it "test 03" do
        let linterEnv :: OpenApiLintEnvironment
            linterEnv = OpenApiLintEnvironment mempty
            input :: Schema
            input = mempty & oneOf ?~ [Inline (mempty & properties .~ IOHM.fromList [])]
            actual = runReader (lookupFieldType "hey" input) linterEnv
            expected = Nothing
        actual `shouldBe` expected

      it "test 04" do
        let linterEnv :: OpenApiLintEnvironment
            linterEnv = OpenApiLintEnvironment mempty
            input :: Schema
            input =
              mempty & oneOf ?~ [Inline (mempty & properties .~ IOHM.fromList [("hey", Inline (mempty & description ?~ "no type!"))])]
            actual = runReader (lookupFieldType "hey" input) linterEnv
            expected = Nothing
        actual `shouldBe` expected

      it "test 05" do
        let linterEnv :: OpenApiLintEnvironment
            linterEnv = OpenApiLintEnvironment mempty
            input :: Schema
            input =
              mempty & oneOf ?~ [Inline (mempty & properties .~ IOHM.fromList [("hey", Inline (mempty & type_ ?~ OpenApiBoolean))])]
            actual = runReader (lookupFieldType "hey" input) linterEnv
            expected = Just [OpenApiBoolean]
        actual `shouldBe` expected

      it "test 06" do
        let linterEnv :: OpenApiLintEnvironment
            linterEnv = OpenApiLintEnvironment mempty
            input :: Schema
            input =
              mempty
                & oneOf
                  ?~ [ Inline
                        ( mempty
                            & properties
                              .~ IOHM.fromList
                                [ ("hey", Inline (mempty & type_ ?~ OpenApiInteger))
                                ]
                        )
                     ]
            actual = runReader (lookupFieldType "hey" input) linterEnv
            expected = Just [OpenApiInteger]
        actual `shouldBe` expected

      it "test 07" do
        let linterEnv :: OpenApiLintEnvironment
            linterEnv = OpenApiLintEnvironment mempty
            input :: Schema
            input =
              mempty
                & oneOf
                  ?~ [ Inline
                        ( mempty
                            & properties
                              .~ IOHM.fromList
                                [ ("hey", Inline (mempty & description ?~ "no type!"))
                                ]
                        )
                     ]
            actual = runReader (lookupFieldType "hey" input) linterEnv
            expected = Nothing
        actual `shouldBe` expected

      it "test 08" do
        let linterEnv :: OpenApiLintEnvironment
            linterEnv =
              OpenApiLintEnvironment $
                IOHM.fromList
                  [ ("yo", mempty & type_ ?~ OpenApiString)
                  ]
            input :: Schema
            input =
              mempty
                & oneOf
                  ?~ [ Inline
                        ( mempty
                            & properties
                              .~ IOHM.fromList
                                [ ("hey", Ref (Reference "yo"))
                                ]
                        )
                     ]
            actual = runReader (lookupFieldType "hey" input) linterEnv
            expected = Just [OpenApiString]
        actual `shouldBe` expected

      it "test 09" do
        let linterEnv :: OpenApiLintEnvironment
            linterEnv =
              OpenApiLintEnvironment $
                IOHM.fromList
                  [ ("yo", mempty & type_ ?~ OpenApiString)
                  , ("sup", mempty & description ?~ "no type!")
                  ]
            input :: Schema
            input =
              mempty
                & oneOf
                  ?~ [ Inline
                        ( mempty
                            & properties
                              .~ IOHM.fromList
                                [ ("hey", Ref (Reference "sup"))
                                ]
                        )
                     ]
            actual = runReader (lookupFieldType "hey" input) linterEnv
            expected = Nothing
        actual `shouldBe` expected

      it "test 10" do
        let linterEnv :: OpenApiLintEnvironment
            linterEnv =
              OpenApiLintEnvironment $
                IOHM.fromList
                  [ ("yo", mempty & type_ ?~ OpenApiString)
                  , ("sup", mempty & oneOf ?~ [Ref (Reference "yo")])
                  ]
            input :: Schema
            input =
              mempty
                & properties
                  .~ IOHM.fromList
                    [ ("hey", Ref (Reference "sup"))
                    ]
            actual = runReader (lookupFieldType "hey" input) linterEnv
            expected = Just [OpenApiString]
        actual `shouldBe` expected

      it "test 11" do
        let linterEnv :: OpenApiLintEnvironment
            linterEnv =
              OpenApiLintEnvironment $
                IOHM.fromList
                  [ ("yo", mempty & type_ ?~ OpenApiString)
                  , ("sup", mempty & oneOf ?~ [Ref (Reference "yo")])
                  , ("bye", mempty & properties .~ IOHM.fromList [("hey", Inline (mempty & type_ ?~ OpenApiBoolean))])
                  ]
            input :: Schema
            input =
              mempty
                & oneOf
                  ?~ [ Inline (mempty & properties .~ IOHM.fromList [("hey", Ref (Reference "sup"))])
                     , Inline (mempty & properties .~ IOHM.fromList [("hey", Ref (Reference "yo"))])
                     , Inline (mempty & properties .~ IOHM.fromList [("hey", Inline (mempty & type_ ?~ OpenApiInteger))])
                     , Ref (Reference "bye")
                     ]
            actual = runReader (lookupFieldType "hey" input) linterEnv
            expected = Just [OpenApiString, OpenApiInteger, OpenApiBoolean]
        actual `shouldBe` expected

    describe "schemaRule1Check" do
      it "test 00" do
        let linterEnv :: OpenApiLintEnvironment
            linterEnv = OpenApiLintEnvironment mempty
            input :: Schema
            input = mempty
            actual = runReaderT (schemaRule1Check [] input) linterEnv
            expected = []
        actual `shouldBe` expected

      it "test 01" do
        let linterEnv :: OpenApiLintEnvironment
            linterEnv = OpenApiLintEnvironment mempty
            input :: Schema
            input = mempty & required .~ ["myfield"]
            actual = runReaderT (schemaRule1Check ["huey", "dewey", "louie"] input) linterEnv
            expected =
              [ OpenApiLintIssue
                  { trace = "louie/dewey/huey"
                  , message = "Missing type for required field 'myfield'!"
                  }
              ]
        actual `shouldBe` expected

  validateEveryToJSONWithPatternChecker patternChecker (Proxy @(WrapContractBodies (RetractRuntimeStatus Web.RuntimeAPI)))
  it "Should match the golden test" do
    defaultGolden "OpenApi" $
      TL.unpack $
        TB.toLazyText $
          encodePrettyToTextBuilder openApi

type family RetractRuntimeStatus api where
  RetractRuntimeStatus (WithRuntimeStatus api) = api

type family WrapContractBodies (api :: Type) :: Type where
  WrapContractBodies (ReqBody' mods cs V1.Contract :> api) = ReqBody' mods cs WrappedContract :> WrapContractBodies api
  WrapContractBodies ((e :: k) :> api) = e :> WrapContractBodies api
  WrapContractBodies (api1 :<|> api2) = WrapContractBodies api1 :<|> WrapContractBodies api2
  WrapContractBodies (Verb v s cs (Headers hs V1.Contract)) = Verb v s cs (Headers hs WrappedContract)
  WrapContractBodies (Verb v s cs V1.Contract) = Verb v s cs WrappedContract
  WrapContractBodies (Verb v s cs a) = Verb v s cs a
  WrapContractBodies api = api

newtype WrappedContract = WrappedContract {unWrappedContract :: V1.Contract}
  deriving (Typeable)
  deriving newtype (Show, ToJSON, ToSchema)

instance Arbitrary WrappedContract where
  arbitrary = WrappedContract <$> resize 6 arbitrary
  shrink = fmap WrappedContract . shrink . unWrappedContract

patternChecker :: Pattern -> Text -> Bool
patternChecker pat text = T.unpack text =~ T.unpack pat

instance Arbitrary Web.PostContractSourceResponse where
  arbitrary =
    Web.PostContractSourceResponse
      <$> arbitrary
      <*> arbitrary

instance Arbitrary Web.WithdrawalHeader where
  arbitrary =
    Web.WithdrawalHeader
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary

instance Arbitrary Web.ContractHeader where
  arbitrary =
    Web.ContractHeader
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary

instance Arbitrary Web.TxHeader where
  arbitrary =
    Web.TxHeader
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary

instance Arbitrary Web.PayoutState where
  arbitrary =
    Web.PayoutState
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
  shrink = genericShrink

instance Arbitrary Web.ContractState where
  arbitrary =
    Web.ContractState
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      -- size of 6 will result in a 1-layer deep contract being generated (this is
      -- all we care about for the purposes of schema checking).
      <*> resize 6 arbitrary
      <*> arbitrary
      <*> resize 6 arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
  shrink = genericShrink

instance Arbitrary Web.Payout where
  arbitrary =
    Web.Payout
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
  shrink = genericShrink

instance Arbitrary Web.PayoutStatus where
  arbitrary = elements [Web.Available, Web.Withdrawn]
  shrink = genericShrink

instance Arbitrary Web.PayoutHeader where
  arbitrary =
    Web.PayoutHeader
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
  shrink = genericShrink

instance Arbitrary Web.Assets where
  arbitrary = Web.Assets <$> arbitrary <*> arbitrary
  shrink = genericShrink

instance Arbitrary Web.Tokens where
  arbitrary = Web.Tokens <$> arbitrary
  shrink = genericShrink

instance Arbitrary Web.Withdrawal where
  arbitrary =
    Web.Withdrawal
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
  shrink = genericShrink

instance Arbitrary Web.RoleTokenFilter where
  arbitrary =
    oneof
      [ Web.RoleTokensAnd <$> arbitrary <*> arbitrary
      , Web.RoleTokensOr <$> arbitrary <*> arbitrary
      , Web.RoleTokenNot <$> arbitrary
      , Web.RoleTokenNot <$> arbitrary
      , pure Web.RoleTokenFilterNone
      , Web.RoleTokenFilterByContracts <$> arbitrary
      , Web.RoleTokenFilterByPolicyIds <$> arbitrary
      , Web.RoleTokenFilterByTokens <$> arbitrary
      , pure Web.RoleTokenFilterAny
      ]
  shrink = genericShrink

instance Arbitrary Web.Tx where
  arbitrary = do
    -- size of 6 will result in a 1-layer deep contract being generated (this is
    -- all we care about for the purposes of schema checking).
    contract <- resize 6 arbitrary
    Web.Tx
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> pure contract
      <*> arbitrary
      <*> arbitraryNormal -- FIXME: This should handle merkleized input, too.
      <*> arbitrary
      <*> elements [Nothing, Just contract]
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> (TransactionInput <$> arbitrary <*> arbitraryNormal)
      <*> resize 6 arbitrary
      <*> arbitrary
  shrink = genericShrink

instance Arbitrary Web.PostWithdrawalsRequest where
  arbitrary = Web.PostWithdrawalsRequest <$> arbitrary

instance Arbitrary Web.PostContractsRequest where
  arbitrary =
    Web.PostContractsRequest
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
  shrink = genericShrink

instance Arbitrary Web.Party where
  arbitrary = Web.Party <$> arbitrary
  shrink = genericShrink

instance Arbitrary Web.ContractOrSourceId where
  arbitrary =
    ContractOrSourceId
      <$> oneof
        [ Right <$> arbitrary
        , Left <$> resize 6 (arbitrary <&> unValidContractStructure)
        ]
  shrink = genericShrink

instance Arbitrary Web.PostTransactionsRequest where
  arbitrary =
    Web.PostTransactionsRequest
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitraryNormal -- FIXME: This should handle merkleized input, too.
  shrink = genericShrink

instance Arbitrary (Web.CreateTxEnvelope tx) where
  arbitrary = Web.CreateTxEnvelope <$> arbitrary <*> arbitrary <*> resize 5 arbitrary
  shrink = genericShrink

instance Arbitrary (Web.WithdrawTxEnvelope tx) where
  arbitrary = Web.WithdrawTxEnvelope <$> arbitrary <*> arbitrary
  shrink = genericShrink

instance Arbitrary (Web.ApplyInputsTxEnvelope tx) where
  arbitrary =
    Web.ApplyInputsTxEnvelope
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> (fmap . fmap) unWebSafetyError arbitrary
  shrink = genericShrink

newtype WebSafetyError = WebSafetyError {unWebSafetyError :: Web.SafetyError}
  deriving (Show, Generic)

instance Arbitrary WebSafetyError where
  arbitrary = pure . WebSafetyError $ MissingRolesCurrency
  shrink = genericShrink

instance Arbitrary (Web.BurnRoleTokensTxEnvelope tx) where
  arbitrary = Web.BurnRoleTokensTxEnvelope <$> arbitrary <*> arbitrary
  shrink = genericShrink

instance Arbitrary Web.MarloweVersion where
  arbitrary = pure Web.V1

instance Arbitrary Web.RolesConfig where
  arbitrary =
    oneof
      [ Web.UsePolicy <$> arbitrary
      , Web.Mint <$> arbitrary
      ]
  shrink = genericShrink

instance Arbitrary Web.RoleTokenConfig where
  arbitrary = Web.RoleTokenConfig <$> arbitrary <*> arbitrary
  shrink = genericShrink

instance Arbitrary Web.RoleTokenRecipient where
  arbitrary =
    oneof
      [ Web.ClosedRole <$> arbitrary
      , pure Web.OpenRole
      ]
  shrink = genericShrink

instance Arbitrary Web.TokenMetadata where
  arbitrary =
    Web.TokenMetadata
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> oneof
        [ pure Nothing
        , Just <$> sized \size -> do
            len <- chooseInt (0, size)
            case len of
              0 -> pure []
              _ -> do
                let itemSize = size `div` len
                resize itemSize $ replicateM len arbitrary
        ]
      <*> pure mempty
  shrink = genericShrink

instance Arbitrary Web.TokenMetadataFile where
  arbitrary =
    Web.TokenMetadataFile
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> pure mempty
  shrink = genericShrink

instance Arbitrary Web.Address where
  arbitrary = Web.Address <$> arbitrary
  shrink = genericShrink

instance Arbitrary Web.StakeAddress where
  arbitrary = Web.StakeAddress <$> arbitrary
  shrink = genericShrink

instance (Arbitrary a) => Arbitrary (Web.ListObject a) where
  arbitrary = Web.ListObject <$> arbitrary
  shrink = genericShrink

instance Arbitrary Web.TextEnvelope where
  arbitrary = Web.TextEnvelope <$> arbitrary <*> arbitrary <*> arbitrary
  shrink = genericShrink

instance Arbitrary Web.TxOutRef where
  arbitrary = Web.TxOutRef <$> arbitrary <*> arbitrary
  shrink = genericShrink

instance Arbitrary Web.AssetId where
  arbitrary = Web.AssetId <$> arbitrary <*> arbitrary
  shrink = genericShrink

instance Arbitrary Web.ContractSourceId where
  arbitrary = Web.ContractSourceId . BS.pack <$> replicateM 32 arbitrary

instance Arbitrary Web.TxId where
  arbitrary = Web.TxId . BS.pack <$> replicateM 32 arbitrary

instance Arbitrary Web.PolicyId where
  arbitrary = Web.PolicyId . BS.pack <$> listOf arbitrary

instance Arbitrary Web.Metadata where
  arbitrary = pure $ Web.Metadata Null

instance Arbitrary Web.TxStatus where
  arbitrary =
    elements
      [ Web.Unsigned
      , Web.Submitted
      , Web.Confirmed
      ]

instance Arbitrary Web.BlockHeader where
  arbitrary = Web.BlockHeader <$> arbitrary <*> arbitrary <*> arbitrary

instance Arbitrary Web.Base16 where
  arbitrary = Web.Base16 . BS.pack <$> listOf arbitrary

instance (Arbitrary a) => Arbitrary (Web.WithLink name a) where
  arbitrary =
    oneof
      [ Web.OmitLink <$> arbitrary
      , Web.IncludeLink (Proxy @name) <$> arbitrary
      ]
  shrink (Web.OmitLink a) = Web.OmitLink <$> shrink a
  shrink (Web.IncludeLink n a) = [Web.OmitLink a] <> (Web.IncludeLink n <$> shrink a)

arbitraryNormal :: Gen [Semantics.Input]
arbitraryNormal =
  arbitrary `suchThat` all isNormal
  where
    isNormal (Semantics.NormalInput _) = True
    isNormal _ = False
