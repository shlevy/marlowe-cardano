{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

{-# HLINT ignore "Eta reduce" #-}
module Language.Marlowe.Runtime.Web.Common (
  applyCloseTransaction,
  applyInputs,
  choose,
  createCloseContract,
  deposit,
  notify,
  signShelleyTransaction',
  submitContract,
  submitTransaction,
  submitWithdrawal,
  waitUntilConfirmed,
  withdraw,
  buildBurnRoleTokenTx,
  submitBurnRoleTokensTx,
) where

import Cardano.Api (
  AsType (..),
  ShelleyBasedEra (ShelleyBasedEraBabbage),
  ShelleyWitnessSigningKey (..),
  TextEnvelope (..),
  TextEnvelopeType (..),
  deserialiseFromTextEnvelope,
  serialiseToTextEnvelope,
  signShelleyTransaction,
 )
import Control.Concurrent (threadDelay)
import Control.Monad.IO.Class (MonadIO (liftIO))
import Data.Set (Set)
import qualified Data.Set as Set
import Data.String (IsString (..))
import qualified Data.Text as T
import qualified Language.Marlowe as V1
import Language.Marlowe.Core.V1.Semantics.Types (
  ChoiceId (ChoiceId),
  Input (NormalInput),
  InputContent (IChoice, IDeposit, INotify),
 )
import Language.Marlowe.Runtime.Integration.Common (
  Wallet (..),
  expectJust,
 )
import Language.Marlowe.Runtime.Transaction.Api (WalletAddresses (..))

import Language.Marlowe.Runtime.Web.Adapter.Server.DTO (ToDTO (toDTO))
import Language.Marlowe.Runtime.Web.Client (
  getContract,
  getWithdrawal,
  postContract,
  postWithdrawal,
  putContract,
  putWithdrawal,
 )
import Language.Marlowe.Runtime.Web.Contract.API (ContractOrSourceId (..))
import qualified Language.Marlowe.Runtime.Web.Contract.API as Web
import Language.Marlowe.Runtime.Web.Contract.Transaction.Client (
  getTransaction,
  postTransaction,
  putTransaction,
 )
import qualified Language.Marlowe.Runtime.Web.Core.Base16 as Web
import qualified Language.Marlowe.Runtime.Web.Core.BlockHeader as Web
import qualified Language.Marlowe.Runtime.Web.Core.MarloweVersion as Web
import qualified Language.Marlowe.Runtime.Web.Core.Tx as Web
import qualified Language.Marlowe.Runtime.Web.Role.API as Web
import Language.Marlowe.Runtime.Web.Role.Client (toWalletHeader)
import qualified Language.Marlowe.Runtime.Web.Role.Client as Web
import qualified Language.Marlowe.Runtime.Web.Role.TokenFilter as Web
import qualified Language.Marlowe.Runtime.Web.Tx.API as Web
import qualified Language.Marlowe.Runtime.Web.Withdrawal.API as Web
import qualified PlutusLedgerApi.V2 as PV2
import Servant.Client.Streaming (ClientM)

createCloseContract :: Wallet -> ClientM Web.TxOutRef
createCloseContract Wallet{..} = do
  let WalletAddresses{..} = addresses
  let webChangeAddress = toDTO changeAddress
  let webExtraAddresses = Set.map toDTO extraAddresses
  let webCollateralUtxos = Set.map toDTO collateralUtxos

  Web.CreateTxEnvelope{txEnvelope, ..} <-
    postContract
      Nothing
      webChangeAddress
      (Just webExtraAddresses)
      (Just webCollateralUtxos)
      Web.PostContractsRequest
        { metadata = mempty
        , version = Web.V1
        , roles = Nothing
        , threadTokenName = Nothing
        , contract = ContractOrSourceId $ Left V1.Close
        , accounts = mempty
        , minUTxODeposit = Nothing
        , tags = mempty
        }

  createTx <- liftIO $ signShelleyTransaction' txEnvelope signingKeys
  putContract contractId createTx
  _ <- waitUntilConfirmed (\Web.ContractState{status} -> status) $ getContract contractId
  pure contractId

applyCloseTransaction :: Wallet -> Web.TxOutRef -> ClientM Web.TxId
applyCloseTransaction Wallet{..} contractId = do
  let WalletAddresses{..} = addresses
  let webChangeAddress = toDTO changeAddress
  let webExtraAddresses = Set.map toDTO extraAddresses
  let webCollateralUtxos = Set.map toDTO collateralUtxos
  Web.ApplyInputsTxEnvelope{transactionId, txEnvelope} <-
    postTransaction
      webChangeAddress
      (Just webExtraAddresses)
      (Just webCollateralUtxos)
      contractId
      Web.PostTransactionsRequest
        { version = Web.V1
        , metadata = mempty
        , invalidBefore = Nothing
        , invalidHereafter = Nothing
        , inputs = []
        , tags = mempty
        }

  applyTx <- liftIO $ signShelleyTransaction' txEnvelope signingKeys

  putTransaction contractId transactionId applyTx

  _ <- waitUntilConfirmed (\Web.Tx{status} -> status) $ getTransaction contractId transactionId
  pure transactionId

submitContract
  :: Wallet
  -> Web.CreateTxEnvelope Web.CardanoTxBody
  -> ClientM Web.BlockHeader
submitContract Wallet{..} Web.CreateTxEnvelope{contractId, txEnvelope} = do
  signedCreateTx <- liftIO $ signShelleyTransaction' txEnvelope signingKeys
  putContract contractId signedCreateTx
  Web.ContractState{block} <- waitUntilConfirmed (\Web.ContractState{status} -> status) $ getContract contractId
  liftIO $ expectJust "Expected block header" block

submitTransaction
  :: Wallet
  -> Web.ApplyInputsTxEnvelope Web.CardanoTxBody
  -> ClientM Web.BlockHeader
submitTransaction Wallet{..} Web.ApplyInputsTxEnvelope{contractId, transactionId, txEnvelope} = do
  signedTx <- liftIO $ signShelleyTransaction' txEnvelope signingKeys
  putTransaction contractId transactionId signedTx
  Web.Tx{block} <- waitUntilConfirmed (\Web.Tx{status} -> status) $ getTransaction contractId transactionId
  liftIO $ expectJust "Expected a block header" block

submitWithdrawal
  :: Wallet
  -> Web.WithdrawTxEnvelope Web.CardanoTxBody
  -> ClientM Web.BlockHeader
submitWithdrawal Wallet{..} Web.WithdrawTxEnvelope{withdrawalId, txEnvelope} = do
  signedWithdrawalTx <- liftIO $ signShelleyTransaction' txEnvelope signingKeys
  putWithdrawal withdrawalId signedWithdrawalTx
  Web.Withdrawal{block} <- waitUntilConfirmed (\Web.Withdrawal{status} -> status) $ getWithdrawal withdrawalId
  liftIO $ expectJust "Expected a block header" block

submitBurnRoleTokensTx
  :: Wallet
  -> Web.BurnRoleTokensTxEnvelope Web.CardanoTxBody
  -> ClientM ()
submitBurnRoleTokensTx Wallet{..} Web.BurnRoleTokensTxEnvelope{txId, txEnvelope} = do
  signedBurnTx <- liftIO $ signShelleyTransaction' txEnvelope signingKeys
  Web.submitBurnTokenTx txId signedBurnTx

deposit
  :: Wallet
  -> Web.TxOutRef
  -> V1.Party
  -> V1.Party
  -> V1.Token
  -> Integer
  -> ClientM (Web.ApplyInputsTxEnvelope Web.CardanoTxBody)
deposit wallet contractId intoAccount fromParty ofToken quantity =
  applyInputs wallet contractId [NormalInput $ IDeposit intoAccount fromParty ofToken quantity]

choose
  :: Wallet
  -> Web.TxOutRef
  -> PV2.BuiltinByteString
  -> V1.Party
  -> Integer
  -> ClientM (Web.ApplyInputsTxEnvelope Web.CardanoTxBody)
choose wallet contractId choice party chosenNum =
  applyInputs wallet contractId [NormalInput $ IChoice (ChoiceId choice party) chosenNum]

notify
  :: Wallet
  -> Web.TxOutRef
  -> ClientM (Web.ApplyInputsTxEnvelope Web.CardanoTxBody)
notify wallet contractId = applyInputs wallet contractId [NormalInput INotify]

withdraw
  :: Wallet
  -> Set Web.TxOutRef
  -> ClientM (Web.WithdrawTxEnvelope Web.CardanoTxBody)
withdraw Wallet{..} payouts = do
  let WalletAddresses{..} = addresses
  let webChangeAddress = toDTO changeAddress
  let webExtraAddresses = Set.map toDTO extraAddresses
  let webCollateralUtxos = Set.map toDTO collateralUtxos

  postWithdrawal
    webChangeAddress
    (Just webExtraAddresses)
    (Just webCollateralUtxos)
    Web.PostWithdrawalsRequest
      { payouts
      }
applyInputs
  :: Wallet
  -> Web.TxOutRef
  -> [V1.Input]
  -> ClientM (Web.ApplyInputsTxEnvelope Web.CardanoTxBody)
applyInputs Wallet{..} contractId inputs = do
  let WalletAddresses{..} = addresses
  let webChangeAddress = toDTO changeAddress
  let webExtraAddresses = Set.map toDTO extraAddresses
  let webCollateralUtxos = Set.map toDTO collateralUtxos

  postTransaction
    webChangeAddress
    (Just webExtraAddresses)
    (Just webCollateralUtxos)
    contractId
    Web.PostTransactionsRequest
      { version = Web.V1
      , metadata = mempty
      , invalidBefore = Nothing
      , invalidHereafter = Nothing
      , inputs
      , tags = mempty
      }

buildBurnRoleTokenTx
  :: Wallet
  -> Web.RoleTokenFilter
  -> ClientM (Web.BurnRoleTokensTxEnvelope Web.CardanoTxBody)
buildBurnRoleTokenTx Wallet{..} roleFilter = Web.buildBurnTokenTxBody (toWalletHeader addresses) roleFilter

signShelleyTransaction' :: Web.TextEnvelope -> [ShelleyWitnessSigningKey] -> IO Web.TextEnvelope
signShelleyTransaction' Web.TextEnvelope{..} wits = do
  let te =
        TextEnvelope
          { teType = TextEnvelopeType (T.unpack teType)
          , teDescription = fromString (T.unpack teDescription)
          , teRawCBOR = Web.unBase16 teCborHex
          }
  txBody <- case deserialiseFromTextEnvelope (AsTxBody AsBabbageEra) te of
    Left err -> fail $ show err
    Right a -> pure a
  pure case serialiseToTextEnvelope Nothing $ signShelleyTransaction ShelleyBasedEraBabbage txBody wits of
    TextEnvelope (TextEnvelopeType ty) _ bytes -> Web.TextEnvelope (T.pack ty) "" $ Web.Base16 bytes

waitUntilConfirmed :: (MonadIO m) => (a -> Web.TxStatus) -> m a -> m a
waitUntilConfirmed getStatus getResource = do
  resource <- getResource
  case getStatus resource of
    Web.Confirmed -> pure resource
    _ -> do
      liftIO $ threadDelay 1000
      waitUntilConfirmed getStatus getResource
