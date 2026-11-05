# JSON: read from text, and shown as text.
import Base

type Json is Data:
  JNull{}
  JTrue{}
  JFalse{}
  JNumber{text: String}
  JString{text: String}
  JArray{items: List<&2, Json>}
  JObject{fields: List<&2, JField>}

type JField is Data:
  JField{key: String, value: Json}

# The JSON value that `text` is, if it is one.
law read:
  for text: String
  Maybe<&2, Json>

# `v` as JSON text, on one line.
law show:
  for v: Json
  String
