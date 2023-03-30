{-# LANGUAGE GADTs #-}

module Logging
  ( RootSelector(..)
  , defaultRootSelectorLogConfig
  , getRootSelectorConfig
  ) where

import Data.Foldable (fold)
import Data.Map (Map)
import Data.Text (Text)
import Language.Marlowe.Protocol.Types (Marlowe)
import Network.Protocol.Connection (ConnectorSelector, getConnectorSelectorConfig, getDefaultConnectorLogConfig)
import Network.Protocol.Handshake.Types (Handshake)
import Observe.Event.Component
  ( ConfigWatcherSelector(ReloadConfig)
  , GetSelectorConfig
  , SelectorConfig(..)
  , SelectorLogConfig
  , getDefaultLogConfig
  , prependKey
  , singletonFieldConfig
  )

data RootSelector f where
  MarloweServer :: ConnectorSelector (Handshake Marlowe) f -> RootSelector f
  ConfigWatcher :: ConfigWatcherSelector f -> RootSelector f

getRootSelectorConfig :: GetSelectorConfig RootSelector
getRootSelectorConfig = \case
  MarloweServer sel -> prependKey "proxy-server" $ getConnectorSelectorConfig False False sel
  ConfigWatcher ReloadConfig -> SelectorConfig "reload-log-config" True $ singletonFieldConfig "config" True

defaultRootSelectorLogConfig :: Map Text SelectorLogConfig
defaultRootSelectorLogConfig = fold
  [ getDefaultConnectorLogConfig getRootSelectorConfig MarloweServer
  , getDefaultLogConfig getRootSelectorConfig $ ConfigWatcher ReloadConfig
  ]