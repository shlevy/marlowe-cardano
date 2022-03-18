module Capability.PAB
  ( class ManagePAB
  , activateContract
  , getWalletContractInstances
  , invokeEndpoint
  , onNewActiveEndpoints
  , subscribeToPlutusApp
  , unsubscribeFromPlutusApp
  ) where

import Prologue

import Affjax (defaultRequest)
import Affjax as Affjax
import Affjax.ResponseFormat as ResponseFormat
import Affjax.StatusCode (StatusCode(..))
import AppM (AppM)
import Control.Concurrent.AVarMap as AVarMap
import Control.Monad.Error.Class (class MonadError)
import Control.Monad.Except (ExceptT(..), lift, runExcept, runExceptT)
import Control.Monad.Maybe.Trans (MaybeT(..), runMaybeT)
import Control.Monad.Reader (ReaderT, asks)
import Control.Monad.Rec.Class (class MonadRec, untilJust)
import Control.Parallel (parOneOf)
import Data.Argonaut (encodeJson)
import Data.Argonaut.Encode (class EncodeJson)
import Data.Filterable (filter)
import Data.Lens (view)
import Data.Map (Map)
import Data.Newtype (unwrap)
import Data.Set as Set
import Data.String (Pattern(..), contains)
import Data.Time.Duration (Minutes(..), fromDuration)
import Data.Traversable (sequence)
import Data.UUID.Argonaut as UUID
import Data.WalletId (WalletId)
import Data.WalletId as WalletId
import Effect.Aff (Error, delay, error)
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Class (class MonadEffect, liftEffect)
import Env (_endpointAVarMap, _sinks)
import Foreign.Class (decode)
import Halogen (HalogenM)
import Halogen.Subscription as HS
import Marlowe.PAB (PlutusAppId)
import MarloweContract (MarloweContract)
import Plutus.Contract.Effects (ActiveEndpoint)
import Plutus.PAB.Webserver as PAB
import Plutus.PAB.Webserver.Types
  ( CombinedWSStreamToServer(..)
  , ContractActivationArgs(..)
  , ContractInstanceClientState
  )
import Servant.PureScript (class MonadAjax, AjaxError(..), ErrorDescription(..))
import Types (AjaxResponse)
import Wallet.Emulator.Wallet (Wallet(..))

class Monad m <= ManagePAB m where
  activateContract
    :: MarloweContract -> WalletId -> m (AjaxResponse PlutusAppId)
  invokeEndpoint
    :: forall d
     . EncodeJson d
    => PlutusAppId
    -> String
    -> d
    -> m (AjaxResponse Unit)
  getWalletContractInstances
    :: WalletId
    -> m (AjaxResponse (Array (ContractInstanceClientState MarloweContract)))
  onNewActiveEndpoints :: PlutusAppId -> Array ActiveEndpoint -> m Unit
  subscribeToPlutusApp :: PlutusAppId -> m Unit
  unsubscribeFromPlutusApp :: PlutusAppId -> m Unit

instance
  ( MonadRec m
  , MonadAff m
  , MonadError Error m
  , MonadAjax PAB.Api m
  ) =>
  ManagePAB (AppM m) where
  activateContract contractActivationId wallet =
    PAB.postApiContractActivate
      $ ContractActivationArgs
          { caID: contractActivationId
          , caWallet: Just $ Wallet
              { prettyWalletName: Nothing
              , getWalletId: WalletId.toString wallet
              }
          }

  invokeEndpoint appId endpoint payload =
    runExceptT $ untilJust $ runMaybeT do
      endpointAvarMap <- asks $ view _endpointAVarMap
      -- Try to take the endpoint's availability AVar with a 5 minute timeout
      lift $ ExceptT $ liftAff $ parOneOf
        [ Right <$> AVarMap.take (Tuple appId endpoint) endpointAvarMap
        , Left timeoutError <$ delay (fromDuration $ Minutes 5.0)
        ]
      ajaxResult <- lift $ lift $
        PAB.postApiContractInstanceByContractinstanceidEndpointByEndpointname
          (encodeJson payload)
          appId
          endpoint
      MaybeT
        $ ExceptT
        $ pure
        $ sequence
        $ filter (not <<< isEndpointNotAvailableFailure)
        $ Just ajaxResult
    where
    timeoutError = AjaxError
      { request: defaultRequest { responseFormat = ResponseFormat.json }
      , response: Nothing
      , description: ConnectingError $ Affjax.XHROtherError $ error $
          "Timed out waiting for endpoint to be released. AppId: "
            <> UUID.toString (unwrap appId)
            <> ", Endpoint: "
            <> endpoint
      }

    isEndpointNotAvailableFailure = case _ of
      Left
        ( AjaxError
            -- This is a ConnectingError, not an UnexpectedHTTPStatus becase to
            -- create an UnexpectedHTTPStatus, servant-support needs to get a
            -- `Response Json` back from affjax. However, the body is in fact a
            -- String produced by calling Show, not JSON. Affjax fails to parse
            -- this as JSON and throws an error instead. So, we need to dig
            -- into the Error returned from Affjax to get the underlying
            -- `Response Foreign` and inspect that instead.
            { description: ConnectingError
                (Affjax.ResponseBodyError _ { status: StatusCode 500, body })
            }
        ) ->
        case runExcept $ decode body of
          Right str -> contains (Pattern "EndpointNotAvailable") str
          _ -> false
      _ -> false

  getWalletContractInstances wallet =
    PAB.getApiContractInstancesWalletByWalletid (WalletId.toString wallet)
      Nothing

  onNewActiveEndpoints appId endpoints = do
    let
      endpointMap :: Map (Tuple PlutusAppId String) Unit
      endpointMap = Set.toMap $ Set.fromFoldable $ map
        ( Tuple appId
            <<< _.getEndpointDescription
            <<< unwrap
            <<< _.aeDescription
            <<< unwrap
        )
        endpoints
    endpointAvarMap <- asks $ view _endpointAVarMap
    AVarMap.mask endpointMap endpointAvarMap
  subscribeToPlutusApp = Left >>> Subscribe >>> sendWsMessage
  unsubscribeFromPlutusApp = Left >>> Unsubscribe >>> sendWsMessage

sendWsMessage
  :: forall m. MonadEffect m => CombinedWSStreamToServer -> AppM m Unit
sendWsMessage msg = do
  { pabWebsocket } <- asks $ view _sinks
  liftEffect $ HS.notify pabWebsocket msg

instance ManagePAB m => ManagePAB (HalogenM state action slots msg m) where
  activateContract contractActivationId wallet = lift $ activateContract
    contractActivationId
    wallet
  invokeEndpoint plutusAppId endpointDescription payload = lift $ invokeEndpoint
    plutusAppId
    endpointDescription
    payload
  getWalletContractInstances = lift <<< getWalletContractInstances
  onNewActiveEndpoints appId = lift <<< onNewActiveEndpoints appId
  subscribeToPlutusApp = lift <<< subscribeToPlutusApp
  unsubscribeFromPlutusApp = lift <<< unsubscribeFromPlutusApp

instance ManagePAB m => ManagePAB (MaybeT m) where
  activateContract contractActivationId wallet = lift $ activateContract
    contractActivationId
    wallet
  invokeEndpoint plutusAppId endpointDescription payload = lift $ invokeEndpoint
    plutusAppId
    endpointDescription
    payload
  getWalletContractInstances = lift <<< getWalletContractInstances
  onNewActiveEndpoints appId = lift <<< onNewActiveEndpoints appId
  subscribeToPlutusApp = lift <<< subscribeToPlutusApp
  unsubscribeFromPlutusApp = lift <<< unsubscribeFromPlutusApp

instance ManagePAB m => ManagePAB (ReaderT r m) where
  activateContract contractActivationId wallet = lift $ activateContract
    contractActivationId
    wallet
  invokeEndpoint plutusAppId endpointDescription payload = lift $ invokeEndpoint
    plutusAppId
    endpointDescription
    payload
  getWalletContractInstances = lift <<< getWalletContractInstances
  onNewActiveEndpoints appId = lift <<< onNewActiveEndpoints appId
  subscribeToPlutusApp = lift <<< subscribeToPlutusApp
  unsubscribeFromPlutusApp = lift <<< unsubscribeFromPlutusApp
