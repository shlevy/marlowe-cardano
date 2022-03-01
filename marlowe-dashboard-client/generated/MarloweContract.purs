-- File auto generated by purescript-bridge! --
module MarloweContract where

import Prelude

import Control.Lazy (defer)
import Data.Argonaut (encodeJson, jsonNull)
import Data.Argonaut.Decode (class DecodeJson)
import Data.Argonaut.Decode.Aeson ((</$\>), (</*\>), (</\>))
import Data.Argonaut.Decode.Aeson as D
import Data.Argonaut.Encode (class EncodeJson)
import Data.Argonaut.Encode.Aeson ((>$<), (>/\<))
import Data.Argonaut.Encode.Aeson as E
import Data.Bounded.Generic (genericBottom, genericTop)
import Data.Enum (class Enum)
import Data.Enum.Generic (genericPred, genericSucc)
import Data.Generic.Rep (class Generic)
import Data.Lens (Iso', Lens', Prism', iso, prism')
import Data.Lens.Iso.Newtype (_Newtype)
import Data.Lens.Record (prop)
import Data.Map as Map
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Data.Show.Generic (genericShow)
import Data.Tuple.Nested ((/\))
import Type.Proxy (Proxy(Proxy))

data MarloweContract
  = MarloweApp
  | WalletCompanion
  | MarloweFollower

derive instance Eq MarloweContract

derive instance Ord MarloweContract

instance Show MarloweContract where
  show a = genericShow a

instance EncodeJson MarloweContract where
  encodeJson = defer \_ -> E.encode E.enum

instance DecodeJson MarloweContract where
  decodeJson = defer \_ -> D.decode D.enum

derive instance Generic MarloweContract _

instance Enum MarloweContract where
  succ = genericSucc
  pred = genericPred

instance Bounded MarloweContract where
  bottom = genericBottom
  top = genericTop

--------------------------------------------------------------------------------

_MarloweApp :: Prism' MarloweContract Unit
_MarloweApp = prism' (const MarloweApp) case _ of
  MarloweApp -> Just unit
  _ -> Nothing

_WalletCompanion :: Prism' MarloweContract Unit
_WalletCompanion = prism' (const WalletCompanion) case _ of
  WalletCompanion -> Just unit
  _ -> Nothing

_MarloweFollower :: Prism' MarloweContract Unit
_MarloweFollower = prism' (const MarloweFollower) case _ of
  MarloweFollower -> Just unit
  _ -> Nothing