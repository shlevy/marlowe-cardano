module Data.Passphrase
  ( Passphrase
  , fromString
  , toString
  ) where

import Prologue

import Data.Argonaut (class DecodeJson, class EncodeJson)
import Data.String (trim)

newtype Passphrase = Passphrase String

derive instance Eq Passphrase
derive instance Ord Passphrase
derive newtype instance EncodeJson Passphrase
derive newtype instance DecodeJson Passphrase

instance Show Passphrase where
  show = const "<Passphrase>"

fromString :: String -> Maybe Passphrase
fromString s =
  if trim s /= s then Nothing
  else Just $ Passphrase s

toString :: Passphrase -> String
toString (Passphrase s) = s