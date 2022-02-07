{ name = "marlowe-dashboard-client"
, dependencies =
  [ "aff"
  , "affjax"
  , "argonaut"
  , "argonaut-codecs"
  , "argonaut-core"
  , "arrays"
  , "avar"
  , "bifunctors"
  , "console"
  , "control"
  , "datetime"
  , "dom-indexed"
  , "effect"
  , "either"
  , "enums"
  , "errors"
  , "exceptions"
  , "filterable"
  , "foldable-traversable"
  , "foreign-object"
  , "formatters"
  , "free"
  , "halogen"
  , "halogen-hooks"
  , "halogen-hooks-extra"
  , "halogen-nselect"
  , "halogen-store"
  , "halogen-subscriptions"
  , "heterogeneous"
  , "http-methods"
  , "identity"
  , "integers"
  , "json-helpers"
  , "lists"
  , "logging"
  , "maybe"
  , "newtype"
  , "now"
  , "ordered-collections"
  , "partial"
  , "polyform"
  , "prelude"
  , "profunctor"
  , "profunctor-lenses"
  , "psci-support"
  , "quickcheck"
  , "record"
  , "remotedata"
  , "servant-support"
  , "strings"
  , "tailrec"
  , "transformers"
  , "tuples"
  , "typelevel-prelude"
  , "unfoldable"
  , "uri"
  , "validation"
  , "variant"
  , "web-common"
  , "web-dom"
  , "web-events"
  , "web-html"
  , "web-socket"
  , "web-uievents"
  ]
, packages = ../packages.dhall
, sources =
  [ "src/**/*.purs"
  , "test/**/*.purs"
  , "generated/**/*.purs"
  , "../web-common-marlowe/src/**/*.purs"
  ]
}
