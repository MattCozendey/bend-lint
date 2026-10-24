# Set helpers. Base's Set.has gives the set back beside its answer; these give the answer alone.
import Base

def has(set: Set(), key: String) -> Bool:
  Pair.snd(Set(), Bool, Set.has(set, key))

# Whether one of `keys` is in `set`, or `found`.
def has_any(keys: List<&2, String>, +set: Set(), found: Bool) -> Bool:
  match keys found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{key, rest} False{}:
      has_any(rest, set, has(set, key))
