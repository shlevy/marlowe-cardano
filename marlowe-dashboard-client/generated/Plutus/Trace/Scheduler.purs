-- File auto generated by purescript-bridge! --
module Plutus.Trace.Scheduler where

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
import Data.Newtype (class Newtype, unwrap)
import Data.Show.Generic (genericShow)
import Data.Tuple.Nested ((/\))
import Plutus.Trace.Tag (Tag)
import Type.Proxy (Proxy(Proxy))

data Priority
  = Normal
  | Sleeping
  | Frozen

derive instance Eq Priority

derive instance Ord Priority

instance Show Priority where
  show a = genericShow a

instance EncodeJson Priority where
  encodeJson = defer \_ -> E.encode E.enum

instance DecodeJson Priority where
  decodeJson = defer \_ -> D.decode D.enum

derive instance Generic Priority _

instance Enum Priority where
  succ = genericSucc
  pred = genericPred

instance Bounded Priority where
  bottom = genericBottom
  top = genericTop

--------------------------------------------------------------------------------

_Normal :: Prism' Priority Unit
_Normal = prism' (const Normal) case _ of
  Normal -> Just unit
  _ -> Nothing

_Sleeping :: Prism' Priority Unit
_Sleeping = prism' (const Sleeping) case _ of
  Sleeping -> Just unit
  _ -> Nothing

_Frozen :: Prism' Priority Unit
_Frozen = prism' (const Frozen) case _ of
  Frozen -> Just unit
  _ -> Nothing

--------------------------------------------------------------------------------

newtype SchedulerLog = SchedulerLog
  { slEvent :: ThreadEvent
  , slThread :: ThreadId
  , slTag :: Tag
  , slPrio :: Priority
  }

derive instance Eq SchedulerLog

instance Show SchedulerLog where
  show a = genericShow a

instance EncodeJson SchedulerLog where
  encodeJson = defer \_ -> E.encode $ unwrap >$<
    ( E.record
        { slEvent: E.value :: _ ThreadEvent
        , slThread: E.value :: _ ThreadId
        , slTag: E.value :: _ Tag
        , slPrio: E.value :: _ Priority
        }
    )

instance DecodeJson SchedulerLog where
  decodeJson = defer \_ -> D.decode $
    ( SchedulerLog <$> D.record "SchedulerLog"
        { slEvent: D.value :: _ ThreadEvent
        , slThread: D.value :: _ ThreadId
        , slTag: D.value :: _ Tag
        , slPrio: D.value :: _ Priority
        }
    )

derive instance Generic SchedulerLog _

derive instance Newtype SchedulerLog _

--------------------------------------------------------------------------------

_SchedulerLog :: Iso' SchedulerLog
  { slEvent :: ThreadEvent
  , slThread :: ThreadId
  , slTag :: Tag
  , slPrio :: Priority
  }
_SchedulerLog = _Newtype

--------------------------------------------------------------------------------

data StopReason
  = ThreadDone
  | ThreadExit

derive instance Eq StopReason

derive instance Ord StopReason

instance Show StopReason where
  show a = genericShow a

instance EncodeJson StopReason where
  encodeJson = defer \_ -> E.encode E.enum

instance DecodeJson StopReason where
  decodeJson = defer \_ -> D.decode D.enum

derive instance Generic StopReason _

instance Enum StopReason where
  succ = genericSucc
  pred = genericPred

instance Bounded StopReason where
  bottom = genericBottom
  top = genericTop

--------------------------------------------------------------------------------

_ThreadDone :: Prism' StopReason Unit
_ThreadDone = prism' (const ThreadDone) case _ of
  ThreadDone -> Just unit
  _ -> Nothing

_ThreadExit :: Prism' StopReason Unit
_ThreadExit = prism' (const ThreadExit) case _ of
  ThreadExit -> Just unit
  _ -> Nothing

--------------------------------------------------------------------------------

data ThreadEvent
  = Stopped StopReason
  | Resumed
  | Suspended
  | Started
  | Thawed

derive instance Eq ThreadEvent

instance Show ThreadEvent where
  show a = genericShow a

instance EncodeJson ThreadEvent where
  encodeJson = defer \_ -> case _ of
    Stopped a -> E.encodeTagged "Stopped" a E.value
    Resumed -> encodeJson { tag: "Resumed", contents: jsonNull }
    Suspended -> encodeJson { tag: "Suspended", contents: jsonNull }
    Started -> encodeJson { tag: "Started", contents: jsonNull }
    Thawed -> encodeJson { tag: "Thawed", contents: jsonNull }

instance DecodeJson ThreadEvent where
  decodeJson = defer \_ -> D.decode
    $ D.sumType "ThreadEvent"
    $ Map.fromFoldable
        [ "Stopped" /\ D.content (Stopped <$> D.value)
        , "Resumed" /\ pure Resumed
        , "Suspended" /\ pure Suspended
        , "Started" /\ pure Started
        , "Thawed" /\ pure Thawed
        ]

derive instance Generic ThreadEvent _

--------------------------------------------------------------------------------

_Stopped :: Prism' ThreadEvent StopReason
_Stopped = prism' Stopped case _ of
  (Stopped a) -> Just a
  _ -> Nothing

_Resumed :: Prism' ThreadEvent Unit
_Resumed = prism' (const Resumed) case _ of
  Resumed -> Just unit
  _ -> Nothing

_Suspended :: Prism' ThreadEvent Unit
_Suspended = prism' (const Suspended) case _ of
  Suspended -> Just unit
  _ -> Nothing

_Started :: Prism' ThreadEvent Unit
_Started = prism' (const Started) case _ of
  Started -> Just unit
  _ -> Nothing

_Thawed :: Prism' ThreadEvent Unit
_Thawed = prism' (const Thawed) case _ of
  Thawed -> Just unit
  _ -> Nothing

--------------------------------------------------------------------------------

newtype ThreadId = ThreadId { unThreadId :: Int }

derive instance Eq ThreadId

instance Show ThreadId where
  show a = genericShow a

instance EncodeJson ThreadId where
  encodeJson = defer \_ -> E.encode $ unwrap >$<
    ( E.record
        { unThreadId: E.value :: _ Int }
    )

instance DecodeJson ThreadId where
  decodeJson = defer \_ -> D.decode $
    (ThreadId <$> D.record "ThreadId" { unThreadId: D.value :: _ Int })

derive instance Generic ThreadId _

derive instance Newtype ThreadId _

--------------------------------------------------------------------------------

_ThreadId :: Iso' ThreadId { unThreadId :: Int }
_ThreadId = _Newtype