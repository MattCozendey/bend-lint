import Base

# This probe format is intentionally independent of the browser and Node JSON
# formats. It is a bounded starting point for reviewing native persistence.
type Edit is Data:
  Edit{x: U32, y: U32, z: U32, block: U32}

type Snapshot is Data:
  Snapshot{seed: U32, edit: Edit}

def encode(snapshot: Snapshot) -> String:
  Snapshot{seed, edit} = snapshot
  Edit{x, y, z, block} = edit
  "B2CS:1:" ++ U32.show(seed) ++ ":" ++ U32.show(x) ++ ":"
    ++ U32.show(y) ++ ":" ++ U32.show(z) ++ ":" ++ U32.show(block)

def read_u32.canonical(text: String, value: U32, canonical: Bool) -> Maybe<&2, U32>:
  match canonical:
    case False{}:
      None{}
    case True{}:
      Some{value}

def read_u32.parsed(+text: String, parsed: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match parsed:
    case None{}:
      None{}
    case Some{+value}:
      read_u32.canonical(text, value, String.eq(U32.show(value), text))

def read_u32(+text: String) -> Maybe<&2, U32>:
  read_u32.parsed(text, U32.read(text))

def decode.values(
  seed: Maybe<&2, U32>, x: Maybe<&2, U32>, y: Maybe<&2, U32>,
  z: Maybe<&2, U32>, block: Maybe<&2, U32>
) -> Maybe<&2, Snapshot>:
  match seed x y z block:
    case Some{seed_value} Some{x_value} Some{y_value} Some{z_value} Some{block_value}:
      Some{Snapshot{seed_value, Edit{x_value, y_value, z_value, block_value}}}
    case _ _ _ _ _:
      None{}

def decode.header(
  header: String, version: String, seed: String, x: String, y: String, z: String, block: String
) -> Maybe<&2, Snapshot>:
  match header version:
    case "B2CS" "1":
      decode.values(read_u32(seed), read_u32(x), read_u32(y), read_u32(z), read_u32(block))
    case _ _:
      None{}

def decode.parts(parts: List<&2, String>) -> Maybe<&2, Snapshot>:
  match parts:
    case Con{header, Con{version, Con{seed, Con{x, Con{y, Con{z, Con{block, Nil{}}}}}}}}:
      decode.header(header, version, seed, x, y, z, block)
    case _:
      None{}

# Five U32 decimal fields need at most 50 digits; the fixed prefix and four
# separators bring the complete canonical record to at most 61 characters.
def decode.within_limit(serialized: String, within_limit: Bool) -> Maybe<&2, Snapshot>:
  match within_limit:
    case False{}:
      None{}
    case True{}:
      decode.parts(String.split(serialized, ':'))

def decode(+serialized: String) -> Maybe<&2, Snapshot>:
  decode.within_limit(serialized, Nat.is_le(String.length(serialized), 61n))
