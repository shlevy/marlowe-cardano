module Env where

import Prologue

import Control.Concurrent.AVarMap (AVarMap)
import Control.Concurrent.EventBus (EventBus)
import Control.Logger.Effect (Logger)
import Control.Logger.Structured (StructuredLog)
import Data.Lens (Lens')
import Data.Lens.Iso.Newtype (_Newtype)
import Data.Lens.Record (prop)
import Data.Newtype (class Newtype)
import Data.UUID.Argonaut (UUID)
import Data.Wallet (SyncStatus)
import Effect.AVar (AVar)
import Halogen (SubscriptionId)
import Halogen.Subscription (Emitter, Listener)
import Language.Marlowe.Client (ContractHistory, MarloweError)
import Marlowe.PAB (PlutusAppId)
import Marlowe.Semantics (Assets, MarloweParams)
import Plutus.PAB.Webserver.Types
  ( CombinedWSStreamToClient
  , CombinedWSStreamToServer
  )
import Type.Proxy (Proxy(..))
import WebSocket.Support (FromSocket)

type WalletFunds = { sync :: SyncStatus, assets :: Assets }

type Sources =
  { pabWebsocket :: Emitter (FromSocket CombinedWSStreamToClient)
  , walletFunds :: Emitter WalletFunds
  }

type Sinks =
  { pabWebsocket :: Listener CombinedWSStreamToServer
  , logger :: Logger StructuredLog
  }

-- Application enviroment configuration
newtype Env = Env
  {
    -- This AVar helps to solve a concurrency problem in the contract carousel subscriptions.
    -- See notes in [Contract.State(unsubscribeFromSelectCenteredStep)]
    -- There are two reasons why this is stored in the `Env` rather than the Contract.State:
    -- 1. There are multiple Contract.State (one per each contract) but only one carousel at a time.
    --    Sharing the subscription makes sense in that regard.
    -- 2. We need to be inside the Effect/Aff monad in order to create an AVar, and most of the state
    --    creation functions didn't require that, so it seemed wrong to lift several functions into Effect.
    --    In contrast, the Env is created in Main, where we already have access to Effect
    contractStepCarouselSubscription :: AVar SubscriptionId
  , endpointAVarMap :: AVarMap (Tuple PlutusAppId String) Unit
  , createBus :: EventBus UUID (Either MarloweError MarloweParams)
  , applyInputBus :: EventBus UUID (Either MarloweError Unit)
  , redeemBus :: EventBus UUID (Either MarloweError Unit)
  , followerAVarMap :: AVarMap MarloweParams (AVar PlutusAppId)
  , followerBus :: EventBus PlutusAppId ContractHistory
  -- | All the outbound communication channels to the outside world
  , sinks :: Sinks
  -- | All the inbound communication channels from the outside world
  , sources :: Sources
  }

derive instance newtypeEnv :: Newtype Env _

_createBus :: Lens' Env (EventBus UUID (Either MarloweError MarloweParams))
_createBus = _Newtype <<< prop (Proxy :: _ "createBus")

_applyInputBus :: Lens' Env (EventBus UUID (Either MarloweError Unit))
_applyInputBus = _Newtype <<< prop (Proxy :: _ "applyInputBus")

_redeemBus :: Lens' Env (EventBus UUID (Either MarloweError Unit))
_redeemBus = _Newtype <<< prop (Proxy :: _ "redeemBus")

_followerAVarMap :: Lens' Env (AVarMap MarloweParams (AVar PlutusAppId))
_followerAVarMap = _Newtype <<< prop (Proxy :: _ "followerAVarMap")

_followerBus :: Lens' Env (EventBus PlutusAppId ContractHistory)
_followerBus = _Newtype <<< prop (Proxy :: _ "followerBus")

_endpointAVarMap :: Lens' Env (AVarMap (Tuple PlutusAppId String) Unit)
_endpointAVarMap = _Newtype <<< prop (Proxy :: _ "endpointAVarMap")

_sources :: Lens' Env Sources
_sources = _Newtype <<< prop (Proxy :: _ "sources")

_sinks :: Lens' Env Sinks
_sinks = _Newtype <<< prop (Proxy :: _ "sinks")
