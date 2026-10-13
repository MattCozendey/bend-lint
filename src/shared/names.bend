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

# The value `key` names in `table`, a map by name (as `Lint.definitions` makes): one pass over the name, however many
# names there are.
def find(-A: Data, table: Map<&2, Maybe<&2, A>>, key: String) -> Maybe<&2, A>:
  Pair.snd(Map<&2, Maybe<&2, A>>, Maybe<&2, A>, Map.get(Maybe<&2, A>, None{}, table, key))

# Groups
# ======
# Values by name, in a map: each name's values, last first.
def Group.add.to(
  -A: Data,
  got: Map<&2, List<&2, A>> & List<&2, A>,
  key: String,
  x: A
) -> Map<&2, List<&2, A>>:
  match got:
    case Tuple{groups, old}:
      Map.set(&2, List<&2, A>, groups, key, x <> old)

# `groups` with `x` added under `key`. A key's list is last first; `Group.get` gives it in order.
def Group.add(-A: Data, groups: Map<&2, List<&2, A>>, +key: String, x: A) -> Map<&2, List<&2, A>>:
  Group.add.to(A, Map.get(List<&2, A>, [], groups, key), key, x)

# What is added under `key`, in the order added.
def Group.get(-A: Data, groups: Map<&2, List<&2, A>>, key: String) -> List<&2, A>:
  List.reverse(
    &2,
    A,
    Pair.snd(Map<&2, List<&2, A>>, List<&2, A>, Map.get(List<&2, A>, [], groups, key))
  )

def Group.of(
  ~A: Data,
  ~key: A -> String,
  xs: List<&2, A>,
  groups: Map<&2, List<&2, A>>
) -> Map<&2, List<&2, A>>:
  match xs:
    case Nil{}:
      groups
    case Con{+x, rest}:
      Group.of(~A, ~key, rest, Group.add(A, groups, key(x), x))
