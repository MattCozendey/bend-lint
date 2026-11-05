# Helpers for any program of this repo, by concept. Each name starts with its concept: Lists, Names, Sets,
# Strings, Tables.
import Base

# Lists
# =====
# List helpers. They recurse only in tail position, so a long list is fine on the JS lane, whose stack is small;
# Base's append, concat, length, any and sort recurse on the stack.
def Lists.when(-A: Data, hit: Bool, v: A) -> Maybe<&2, A>:
  match hit:
    case True{}:
      Some{v}
    case False{}:
      None{}

# `xs`, last first, onto `out`.
def Lists.onto(a, -A: Kind(a), xs: List<a, A>, out: List<a, A>) -> List<a, A>:
  match xs:
    case Nil{}:
      out
    case Con{h, t}:
      Lists.onto(a, A, t, h <> out)

def Lists.append(a, -A: Kind(a), xs: List<a, A>, ys: List<a, A>) -> List<a, A>:
  Lists.onto(a, A, List.reverse(a, A, xs), ys)

def Lists.concat.go(a, -A: Kind(a), xss: List<a, List<a, A>>, out: List<a, A>) -> List<a, A>:
  match xss:
    case Nil{}:
      List.reverse(a, A, out)
    case Con{xs, rest}:
      Lists.concat.go(a, A, rest, Lists.onto(a, A, xs, out))

def Lists.concat(a, -A: Kind(a), xss: List<a, List<a, A>>) -> List<a, A>:
  Lists.concat.go(a, A, xss, [])

def Lists.length.go(a, -A: Kind(a), xs: List<a, A>, n: Nat) -> Nat:
  match xs:
    case Nil{}:
      n
    case Con{h, t}:
      Lists.length.go(a, A, t, 1n+n)

def Lists.length(a, -A: Kind(a), xs: List<a, A>) -> Nat:
  Lists.length.go(a, A, xs, 0n)

def Lists.any.go(~A: Data, ~f: A -> Bool, xs: List<&2, A>, found: Bool) -> Bool:
  match xs found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{h, t} False{}:
      Lists.any.go(~A, ~f, t, f(h))

# Whether `f` holds for some `x` of `xs`; it stops at the first.
def Lists.any(~A: Data, ~f: A -> Bool, xs: List<&2, A>) -> Bool:
  Lists.any.go(~A, ~f, xs, False{})

def Lists.push(-A: Data, x: Maybe<&2, A>, out: List<&2, A>) -> List<&2, A>:
  match x:
    case Some{v}:
      v <> out
    case None{}:
      out

def Lists.sort.runs(-A: Data, xs: List<&2, A>, out: List<&2, List<&2, A>>) -> List<&2, List<&2, A>>:
  match xs:
    case Nil{}:
      List.reverse(&2, List<&2, A>, out)
    case Con{h, t}:
      Lists.sort.runs(A, t, [h] <> out)

# One pass: each two runs merged, in order.
def Lists.sort.pass(
  ~A: Data,
  ~le: A -> A -> Bool,
  +n: Nat,
  runs: List<&2, List<&2, A>>,
  out: List<&2, List<&2, A>>
) -> List<&2, List<&2, A>>:
  match runs:
    case Nil{}:
      List.reverse(&2, List<&2, A>, out)
    case Con{r, Nil{}}:
      List.reverse(&2, List<&2, A>, r <> out)
    case Con{r1, Con{r2, rest}}:
      Lists.sort.pass(~A, ~le, n, rest, List.merge.go(~A, ~le, n, (Nil{}, r1, r2)) <> out)

# Passes until one run is left; each pass halves the runs, so `fuel` (the length) is more than enough.
def Lists.sort.go(
  ~A: Data,
  ~le: A -> A -> Bool,
  fuel: Nat,
  +n: Nat,
  runs: List<&2, List<&2, A>>
) -> List<&2, A>:
  match fuel runs:
    case _ Nil{}:
      []
    case _ Con{r, Nil{}}:
      r
    case 0n _:
      Lists.concat(&2, A, runs)
    case 1n+f _:
      Lists.sort.go(~A, ~le, f, n, Lists.sort.pass(~A, ~le, n, runs, []))

# `xs` in `le` order, stable: a bottom-up merge sort.
def Lists.sort(~A: Data, ~le: A -> A -> Bool, xs: List<&2, A>) -> List<&2, A>:
  +ys = {xs: List<&2, A>}
  +n = Lists.length(&2, A, ys)
  Lists.sort.go(~A, ~le, n, n, Lists.sort.runs(A, ys, []))

def Lists.deal.go(
  a,
  -A: Kind(a),
  xs: List<a, A>,
  even: Bool,
  l: List<a, A>,
  r: List<a, A>
) -> List<a, A>
  & List<a, A>:
  match xs even:
    case Nil{} _:
      (List.reverse(a, A, l), List.reverse(a, A, r))
    case Con{h, t} True{}:
      Lists.deal.go(a, A, t, False{}, h <> l, r)
    case Con{h, t} False{}:
      Lists.deal.go(a, A, t, True{}, l, h <> r)

# `xs` dealt into two halves, each in order: those at even positions, and those at odd ones.
def Lists.deal(a, -A: Kind(a), xs: List<a, A>) -> List<a, A> & List<a, A>:
  Lists.deal.go(a, A, xs, True{}, [], [])

# Names
# =====
# A value, with the name it is written as.
type Names.Named<-A: Data> is Data:
  Names.Named{name: String, value: A}

def Names.lookup.go(
  -A: Data,
  +key: String,
  table: List<&2, Names.Named<A>>,
  found: Maybe<&2, A>
) -> Maybe<&2, A>:
  match table found:
    case _ Some{v}:
      Some{v}
    case Nil{} None{}:
      None{}
    case Con{Names.Named{k, v}, rest} None{}:
      Names.lookup.go(A, key, rest, Lists.when(A, String.eq(k, key), v))

# Each of `xs` with the name `show` gives it: a table for `lookup`, so that each name is written once, in `show`.
def Names.table(~A: Data, ~show: A -> String, xs: List<&2, A>) -> List<&2, Names.Named<A>>:
  match xs:
    case Nil{}:
      []
    case Con{+x, rest}:
      Names.Named{show(x), x} <> Names.table(~A, ~show, rest)

# The value `key` names in `table`: the first, read no further.
def Names.lookup(-A: Data, key: String, table: List<&2, Names.Named<A>>) -> Maybe<&2, A>:
  Names.lookup.go(A, key, table, None{})

# The value `key` names in `table`, a map by name (as `Lint.definitions` makes): one pass over the name, however many
# names there are.
def Names.find(-A: Data, table: Map<&2, Maybe<&2, A>>, key: String) -> Maybe<&2, A>:
  Pair.snd(Map<&2, Maybe<&2, A>>, Maybe<&2, A>, Map.get(Maybe<&2, A>, None{}, table, key))

# Groups
# ======
# Values by name, in a map: each name's values, last first.
def Names.Group.add.of(
  -A: Data,
  got: Map<&2, List<&2, A>> & List<&2, A>,
  key: String,
  x: A
) -> Map<&2, List<&2, A>>:
  match got:
    case Tuple{groups, old}:
      Map.set(&2, List<&2, A>, groups, key, x <> old)

# `groups` with `x` added under `key`. A key's list is last first; `Group.get` gives it in order.
def Names.Group.add(
  -A: Data,
  groups: Map<&2, List<&2, A>>,
  +key: String,
  x: A
) -> Map<&2, List<&2, A>>:
  Names.Group.add.of(A, Map.get(List<&2, A>, [], groups, key), key, x)

# What is added under `key`, in the order added.
def Names.Group.get(-A: Data, groups: Map<&2, List<&2, A>>, key: String) -> List<&2, A>:
  List.reverse(
    &2,
    A,
    Pair.snd(Map<&2, List<&2, A>>, List<&2, A>, Map.get(List<&2, A>, [], groups, key))
  )

def Names.Group.of(
  ~A: Data,
  ~key: A -> String,
  xs: List<&2, A>,
  groups: Map<&2, List<&2, A>>
) -> Map<&2, List<&2, A>>:
  match xs:
    case Nil{}:
      groups
    case Con{+x, rest}:
      Names.Group.of(~A, ~key, rest, Names.Group.add(A, groups, key(x), x))

# Sets
# ====
# Set helpers. Base's Set.has gives the set back beside its answer; these give the answer alone.
def Sets.has(set: Set(), key: String) -> Bool:
  Pair.snd(Set(), Bool, Set.has(set, key))

# Whether one of `keys` is in `set`, or `found`.
def Sets.has_any(keys: List<&2, String>, +set: Set(), found: Bool) -> Bool:
  match keys found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{key, rest} False{}:
      Sets.has_any(rest, set, Sets.has(set, key))

# Strings
# =======
def Strings.take.go(n: Nat, s: String, acc: String) -> String:
  match n s:
    case 1n+k SCon{c, rest}:
      Strings.take.go(k, rest, SCon{c, acc})
    case _ _:
      String.reverse(acc)

# The first `n` characters of `s`. Base's String.take is not tail-recursive, so long text would overflow the stack.
def Strings.take(s: String, n: Nat) -> String:
  Strings.take.go(n, s, "")

# The text of `text` from `beg` to `end`, in code points.
def Strings.slice(text: String, +beg: U32, end: U32) -> String:
  Strings.take(String.drop(text, U32.to_nat(beg)), U32.to_nat((end - beg: U32)))

def Strings.line_start.go(s: String, +i: U32, +at: U32, start: U32, going: Bool) -> U32:
  match s going:
    case _ False{}:
      start
    case SNil{} True{}:
      start
    case SCon{c, rest} True{}:
      Strings.line_start.go(
        rest,
        (i + 1: U32),
        at,
        Bool.pick(U32, Char.is_eq(c, '\n'), (i + 1: U32), start),
        U32.is_lt((i + 1: U32), at)
      )

# Where the line of `text` that holds the offset `at` starts: after the last newline before it.
def Strings.line_start(text: String, +at: U32) -> U32:
  Strings.line_start.go(text, 0, at, 0, U32.is_lt(0, at))

def Strings.line_end.go(s: String, i: U32) -> U32:
  match s:
    case SNil{}:
      i
    case SCon{'\n', rest}:
      (i + 1: U32)
    case SCon{c, rest}:
      Strings.line_end.go(rest, (i + 1: U32))

# Where the line of `text` that starts at `beg` ends: after its newline, or at the end of the text.
def Strings.line_end(text: String, +beg: U32) -> U32:
  Strings.line_end.go(String.drop(text, U32.to_nat(beg)), beg)

def Strings.starts_with(s: String, c: Char) -> Bool:
  match s:
    case SCon{h, t}:
      Char.is_eq(h, c)
    case SNil{}:
      False{}

def Strings.before.go(s: String, +sep: Char, acc: String, at: Bool) -> String:
  match s at:
    case SNil{} _:
      ""
    case _ True{}:
      String.reverse(acc)
    case SCon{c, +rest} False{}:
      Strings.before.go(rest, sep, SCon{c, acc}, Strings.starts_with(rest, sep))

# What comes before the first `sep` of `s`, or "" if there is none.
def Strings.before(+s: String, +sep: Char) -> String:
  Strings.before.go(s, sep, "", Strings.starts_with(s, sep))

def Strings.after_last.go(s: String, +sep: Char, seg: String) -> String:
  match s:
    case SNil{}:
      String.reverse(seg)
    case SCon{+c, rest}:
      Strings.after_last.go(rest, sep, Bool.pick(String, Char.is_eq(c, sep), "", SCon{c, seg}))

# What comes after the last `sep` of `s`, or all of `s` if there is none.
def Strings.after_last(s: String, sep: Char) -> String:
  Strings.after_last.go(s, sep, "")

# The chunks of `chunks` (last first) as one text, before `out`. Each chunk is copied once, so it is linear.
def Strings.onto(chunks: List<&2, String>, out: String) -> String:
  match chunks:
    case Nil{}:
      out
    case Con{c, rest}:
      Strings.onto(rest, c ++ out)

# Tables
# ======
# Values by number, from 0: a balanced tree. Each node parts its values by a bit of their number, the lowest first, so
# a lookup reads the bits of a number, and no text.
type Tables.Table<-A: Data> is Data:
  Tables.TLeaf{value: Maybe<&2, A>}
  Tables.TNode{even: Tables.Table<A>, odd: Tables.Table<A>}

# A table grows one value at a time: a leaf holds the value whose number has no bits left (the number read from its
# lowest bit, a bit a level), so a value numbered `i` is about log2(i) levels down.

# The value numbered `i` in `t`: `odd` is whether `i` is.
def Tables.Table.get.go(-A: Data, t: Tables.Table<A>, +i: U32, odd: Bool) -> Maybe<&2, A>:
  match t odd:
    case Tables.TLeaf{v} _:
      Bool.pick(Maybe<&2, A>, U32.is_zero(i), v, None{})
    case Tables.TNode{e, o} False{}:
      Tables.Table.get.go(A, e, U32.shr(i), U32.is_eq(U32.and(U32.shr(i), 1), 1))
    case Tables.TNode{e, o} True{}:
      Tables.Table.get.go(A, o, U32.shr(i), U32.is_eq(U32.and(U32.shr(i), 1), 1))

def Tables.Table.get(-A: Data, t: Tables.Table<A>, +i: U32) -> Maybe<&2, A>:
  Tables.Table.get.go(A, t, i, U32.is_eq(U32.and(i, 1), 1))

# `t` with `x` numbered `i`: `odd` is whether `i` is, and `zero` whether it is 0. A leaf of another number parts
# first. `fuel` bounds the levels: two a bit.
def Tables.Table.set.go(
  -A: Data,
  fuel: Nat,
  t: Tables.Table<A>,
  +i: U32,
  x: A,
  odd: Bool,
  zero: Bool
) -> Tables.Table<A>:
  match fuel t odd zero:
    case 0n _ _ _:
      t
    case 1n+f Tables.TLeaf{v} _ True{}:
      Tables.TLeaf{Some{x}}
    case 1n+f Tables.TLeaf{v} _ False{}:
      Tables.Table.set.go(
        A,
        f,
        Tables.TNode{Tables.TLeaf{v}, Tables.TLeaf{None{}}},
        i,
        x,
        odd,
        zero
      )
    case 1n+f Tables.TNode{e, o} False{} _:
      Tables.TNode{
        Tables.Table.set.go(
          A,
          f,
          e,
          U32.shr(i),
          x,
          U32.is_eq(U32.and(U32.shr(i), 1), 1),
          U32.is_zero(U32.shr(i))
        ),
        o
      }
    case 1n+f Tables.TNode{e, o} True{} _:
      Tables.TNode{
        e,
        Tables.Table.set.go(
          A,
          f,
          o,
          U32.shr(i),
          x,
          U32.is_eq(U32.and(U32.shr(i), 1), 1),
          U32.is_zero(U32.shr(i))
        )
      }

def Tables.Table.set(-A: Data, t: Tables.Table<A>, +i: U32, x: A) -> Tables.Table<A>:
  Tables.Table.set.go(A, 66n, t, i, x, U32.is_eq(U32.and(i, 1), 1), U32.is_zero(i))
