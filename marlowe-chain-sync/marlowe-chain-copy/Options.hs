module Options (
  Options (..),
  getOptions,
) where

import Cardano.Api (NetworkId (..), NetworkMagic (..))
import Data.Maybe (fromMaybe)
import qualified Options.Applicative as O
import Prettyprinter
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

data Options = Options
  { nodeSocket :: !FilePath
  , networkId :: !NetworkId
  , databaseUri :: !String
  }
  deriving (Show, Eq)

getOptions :: String -> IO Options
getOptions version = do
  defaultNetworkId <- O.value . fromMaybe Mainnet <$> readNetworkId
  defaultSocketPath <- maybe mempty O.value <$> readSocketPath
  defaultDatabaseUri <- maybe mempty O.value <$> readDatabaseUri
  O.execParser $ parseOptions defaultNetworkId defaultSocketPath defaultDatabaseUri version
  where
    readNetworkId :: IO (Maybe NetworkId)
    readNetworkId = do
      value <- lookupEnv "CARDANO_TESTNET_MAGIC"
      pure $ Testnet . NetworkMagic <$> (readMaybe =<< value)

    readSocketPath :: IO (Maybe FilePath)
    readSocketPath = do
      value <- lookupEnv "CARDANO_NODE_SOCKET_PATH"
      pure case value of
        Just "" -> Nothing
        _ -> value

    readDatabaseUri :: IO (Maybe String)
    readDatabaseUri = do
      value <- lookupEnv "CHAIN_SYNC_DB_URI"
      pure case value of
        Just "" -> Nothing
        _ -> value

parseOptions
  :: O.Mod O.OptionFields NetworkId
  -> O.Mod O.OptionFields FilePath
  -> O.Mod O.OptionFields String
  -> String
  -> O.ParserInfo Options
parseOptions defaultNetworkId defaultSocketPath defaultDatabaseUri version = O.info parser infoMod
  where
    parser :: O.Parser Options
    parser =
      O.helper
        <*> versionOption
        <*> ( Options
                <$> socketPathOption
                <*> networkIdOption
                <*> databaseUriOption
            )
      where
        versionOption :: O.Parser (a -> a)
        versionOption =
          O.infoOption
            ("marlowe-chain-indexer " <> version)
            (O.long "version" <> O.help "Show version.")

        socketPathOption :: O.Parser FilePath
        socketPathOption = O.strOption options
          where
            options :: O.Mod O.OptionFields FilePath
            options =
              mconcat
                [ O.long "socket-path"
                , O.short 's'
                , O.metavar "SOCKET_FILE"
                , defaultSocketPath
                , O.help "Location of the cardano-node socket file. Defaults to the CARDANO_NODE_SOCKET_PATH environment variable."
                ]

        databaseUriOption :: O.Parser String
        databaseUriOption = O.strOption options
          where
            options :: O.Mod O.OptionFields FilePath
            options =
              mconcat
                [ O.long "database-uri"
                , O.short 'd'
                , O.metavar "DATABASE_URI"
                , defaultDatabaseUri
                , O.help "URI of the database where the chain information is saved."
                ]

        networkIdOption :: O.Parser NetworkId
        networkIdOption = O.option parse options
          where
            parse :: O.ReadM NetworkId
            parse = Testnet . NetworkMagic . toEnum <$> O.auto

            options :: O.Mod O.OptionFields NetworkId
            options =
              mconcat
                [ O.long "testnet-magic"
                , O.short 'm'
                , O.metavar "INTEGER"
                , defaultNetworkId
                , O.help "Testnet network ID magic. Defaults to the CARDANO_TESTNET_MAGIC environment variable."
                ]

    infoMod :: O.InfoMod Options
    infoMod =
      mconcat
        [ O.fullDesc
        , O.progDescDoc $ Just description
        , O.header "marlowe-chain-indexer: Chain indexer for the Marlowe Runtime."
        ]

description :: Doc ann
description =
  concatWith
    (\a b -> a <> line <> line <> b)
    [ vcat
        [ "The chain indexer for the Marlowe Runtime. This component connects to a local"
        , "Cardano Node and follows the chain. It copies a subset of the information"
        , "contained in every block to a postgresql database. This database can be queried"
        , "by downstream components, such as marlowe-chain-sync."
        ]
    , vcat
        [ "There should only be one instance of marlowe-chain-indexer writing data to a"
        , "given chain database. There is no need to run multiple indexers. If you would"
        , "like to scale runtime services, it is recommended to deploy a postgres replica"
        , "cluster, run one indexer to populate it, and as many marlowe-chain-sync"
        , "instances as required to read from it."
        ]
    , vcat
        [ "Before running the indexer, the database must be created and migrated using"
        , "sqitch. The migration plan and SQL scripts are included in the source code"
        , "folder for marlowe-chain-indexer."
        ]
    ]
