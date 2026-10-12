import Base
import ./lists.bend as Lists

# A value, with the name it is written as.
type Named<-A: Data> is Data:
  Named{name: String, value: A}

def lookup.go(
  -A: Data,
  +key: String,
  table: List<&2, Named<A>>,
  found: Maybe<&2, A>
) -> Maybe<&2, A>:
  match table found:
    case _ Some{v}:
      Some{v}
    case Nil{} None{}:
      None{}
    case Con{Named{k, v}, rest} None{}:
      lookup.go(A, key, rest, Lists.when(A, String.eq(k, key), v))

# Each of `xs` with the name `show` gives it: a table for `lookup`, so that each name is written once, in `show`.
def named(~A: Data, ~show: A -> String, xs: List<&2, A>) -> List<&2, Named<A>>:
  match xs:
    case Nil{}:
      []
    case Con{+x, rest}:
      Named{show(x), x} <> named(~A, ~show, rest)

# The value `key` names in `table`: the first, read no further.
def lookup(-A: Data, key: String, table: List<&2, Named<A>>) -> Maybe<&2, A>:
  lookup.go(A, key, table, None{})

# The values of `named`, by name, onto `out`: a table for `find`, which reads a name in one pass over it, however many
# names there are.
def table(-A: Data, named: List<&2, Named<A>>, out: Map<&2, Maybe<&2, A>>) -> Map<&2, Maybe<&2, A>>:
  match named:
    case Nil{}:
      out
    case Con{Named{name, value}, rest}:
      table(A, rest, Map.set(&2, Maybe<&2, A>, out, name, Some{value}))

def find(-A: Data, table: Map<&2, Maybe<&2, A>>, key: String) -> Maybe<&2, A>:
  Pair.snd(Map<&2, Maybe<&2, A>>, Maybe<&2, A>, Map.get(Maybe<&2, A>, None{}, table, key))
