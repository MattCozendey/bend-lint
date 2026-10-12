import Base

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
