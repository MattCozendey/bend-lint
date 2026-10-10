# What more than one file of bend-lint uses. The list functions here recurse only in tail position, so a long list
# is fine on the JS lane, whose stack is small; Base's append, concat, length, any and sort recurse on the stack.
import Base

# A value, with the name it is written as.
type Named<-A: Data> is Data:
  Named{name: String, value: A}

def lookup.hit(-A: Data, hit: Bool, v: A) -> Maybe<&2, A>:
  match hit:
    case True{}:
      Some{v}
    case False{}:
      None{}

def lookup.go(-A: Data, +key: String, table: List<&2, Named<A>>, found: Maybe<&2, A>) -> Maybe<&2, A>:
  match table found:
    case _ Some{v}:
      Some{v}
    case Nil{} None{}:
      None{}
    case Con{Named{k, v}, rest} None{}:
      lookup.go(A, key, rest, lookup.hit(A, String.eq(k, key), v))

# The value `key` names in `table`: the first, read no further.
def lookup(-A: Data, +key: String, table: List<&2, Named<A>>) -> Maybe<&2, A>:
  lookup.go(A, key, table, None{})

# `xs`, last first, onto `out`.
def onto(a, -A: Kind(a), xs: List<a, A>, out: List<a, A>) -> List<a, A>:
  match xs:
    case Nil{}:
      out
    case Con{h, t}:
      onto(a, A, t, h <> out)

# `xs`, then `ys`.
def append(a, -A: Kind(a), xs: List<a, A>, ys: List<a, A>) -> List<a, A>:
  onto(a, A, List.reverse(a, A, xs), ys)

def concat.go(a, -A: Kind(a), xss: List<a, List<a, A>>, out: List<a, A>) -> List<a, A>:
  match xss:
    case Nil{}:
      List.reverse(a, A, out)
    case Con{xs, rest}:
      concat.go(a, A, rest, onto(a, A, xs, out))

# The lists of `xss`, one after another.
def concat(a, -A: Kind(a), xss: List<a, List<a, A>>) -> List<a, A>:
  concat.go(a, A, xss, [])

def length.go(a, -A: Kind(a), xs: List<a, A>, n: Nat) -> Nat:
  match xs:
    case Nil{}:
      n
    case Con{h, t}:
      length.go(a, A, t, 1n+n)

def length(a, -A: Kind(a), xs: List<a, A>) -> Nat:
  length.go(a, A, xs, 0n)

def any.go(~A: Data, ~f: A -> Bool, xs: List<&2, A>, found: Bool) -> Bool:
  match xs found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{h, t} False{}:
      any.go(~A, ~f, t, f(h))

# Whether `f` holds for some `x` of `xs`; it stops at the first.
def any(~A: Data, ~f: A -> Bool, xs: List<&2, A>) -> Bool:
  any.go(~A, ~f, xs, False{})

# `x`, if there is one, onto `out`.
def push(-A: Data, x: Maybe<&2, A>, out: List<&2, A>) -> List<&2, A>:
  match x:
    case Some{v}:
      v <> out
    case None{}:
      out

def before.of(parts: List<&2, String>) -> String:
  match parts:
    case Con{first, Con{second, rest}}:
      first
    case _:
      ""

# What comes before the first `sep` of `s`, or "" if there is none.
def before(s: String, sep: Char) -> String:
  before.of(String.split(s, sep))

def sort.runs(-A: Data, xs: List<&2, A>, out: List<&2, List<&2, A>>) -> List<&2, List<&2, A>>:
  match xs:
    case Nil{}:
      List.reverse(&2, List<&2, A>, out)
    case Con{h, t}:
      sort.runs(A, t, [h] <> out)

# One pass: each two runs merged, in order.
def sort.pass(
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
      sort.pass(~A, ~le, n, rest, List.merge.go(~A, ~le, n, (Nil{}, r1, r2)) <> out)

# Passes until one run is left; each pass halves the runs, so `fuel` (the length) is more than enough.
def sort.go(~A: Data, ~le: A -> A -> Bool, fuel: Nat, +n: Nat, runs: List<&2, List<&2, A>>) -> List<&2, A>:
  match fuel runs:
    case _ Nil{}:
      []
    case _ Con{r, Nil{}}:
      r
    case 0n _:
      concat(&2, A, runs)
    case 1n+f _:
      sort.go(~A, ~le, f, n, sort.pass(~A, ~le, n, runs, []))

# `xs` in `le` order, stable: a bottom-up merge sort.
def sort(~A: Data, ~le: A -> A -> Bool, xs: List<&2, A>) -> List<&2, A>:
  +ys = {xs : List<&2, A>}
  +n = length(&2, A, ys)
  sort.go(~A, ~le, n, n, sort.runs(A, ys, []))

# A place in a text: its line and column, from 1.
type Position is Data:
  Position{line: U32, column: U32}

# An offset to place, by its place among the offsets asked; and a place found, by the same.
type Placed is Data:
  Placed{index: U32, offset: U32}

type Located is Data:
  Located{index: U32, at: Position}

# The offsets left to place, in offset order, and the places found, last first.
type Walk is Data:
  Walk{pending: List<&2, Placed>, out: List<&2, Located>}

def Placed.le(a: Placed, b: Placed) -> Bool:
  match a b:
    case Placed{i, x} Placed{j, y}:
      U32.is_le(x, y)

def Located.le(a: Located, b: Located) -> Bool:
  match a b:
    case Located{i, x} Located{j, y}:
      U32.is_le(i, j)

def Placed.of(offsets: List<&2, U32>, +index: U32, out: List<&2, Placed>) -> List<&2, Placed>:
  match offsets:
    case Nil{}:
      out
    case Con{o, rest}:
      Placed.of(rest, (index + 1 : U32), Placed{index, o} <> out)

# Whether the next offset to place is at or before `at`.
def Walk.due(pending: List<&2, Placed>, +at: U32) -> Bool:
  match pending:
    case Con{Placed{i, offset}, rest}:
      U32.is_le(offset, at)
    case Nil{}:
      False{}

# The offsets due at `at`, placed at `line` and `column`.
def Walk.emit(pending: List<&2, Placed>, due: Bool, +at: U32, +line: U32, +column: U32, out: List<&2, Located>) -> Walk:
  match pending due:
    case Con{Placed{i, offset}, +rest} True{}:
      Walk.emit(rest, Walk.due(rest, at), at, line, column, Located{i, Position{line, column}} <> out)
    case _ _:
      Walk{pending, out}

def Walk.done(w: Walk) -> List<&2, Located>:
  match w:
    case Walk{pending, out}:
      out

# The offsets placed, one character of `text` at a time; offsets past its end are placed at its end.
def Walk.go(text: String, +at: U32, +line: U32, +column: U32, w: Walk) -> List<&2, Located>:
  match text w:
    case _ Walk{Nil{}, out}:
      out
    case SNil{} Walk{pending, out}:
      Walk.done(Walk.emit(pending, True{}, 4294967295, line, column, out))
    case SCon{+c, t} Walk{+pending, out}:
      Walk.go(
        t,
        (at + 1 : U32),
        Bool.pick(U32, Char.is_eq(c, '\n'), (line + 1 : U32), line),
        Bool.pick(U32, Char.is_eq(c, '\n'), 1, (column + 1 : U32)),
        Walk.emit(
          pending,
          Walk.due(pending, (at + 1 : U32)),
          (at + 1 : U32),
          Bool.pick(U32, Char.is_eq(c, '\n'), (line + 1 : U32), line),
          Bool.pick(U32, Char.is_eq(c, '\n'), 1, (column + 1 : U32)),
          out
        )
      )

def Walk.positions(located: List<&2, Located>, out: List<&2, Position>) -> List<&2, Position>:
  match located:
    case Nil{}:
      List.reverse(&2, Position, out)
    case Con{Located{i, at}, rest}:
      Walk.positions(rest, at <> out)

def positions.of(+sorted: List<&2, Placed>, text: String) -> List<&2, Position>:
  Walk.positions(
    sort(~Located, ~Located.le, Walk.go(text, 0, 1, 1, Walk.emit(sorted, Walk.due(sorted, 0), 0, 1, 1, []))),
    []
  )

# Where each offset of `offsets` is in `text`, in order: one pass over the text, whatever the number of offsets.
def positions(text: String, offsets: List<&2, U32>) -> List<&2, Position>:
  positions.of(sort(~Placed, ~Placed.le, Placed.of(offsets, 0, [])), text)

def deal.go(a, -A: Kind(a), xs: List<a, A>, even: Bool, l: List<a, A>, r: List<a, A>) -> List<a, A> & List<a, A>:
  match xs even:
    case Nil{} _:
      (List.reverse(a, A, l), List.reverse(a, A, r))
    case Con{h, t} True{}:
      deal.go(a, A, t, False{}, h <> l, r)
    case Con{h, t} False{}:
      deal.go(a, A, t, True{}, l, h <> r)

# `xs` dealt into two halves, each in order: those at even positions, and those at odd ones. `interleave` undoes it.
def deal(a, -A: Kind(a), xs: List<a, A>) -> List<a, A> & List<a, A>:
  deal.go(a, A, xs, True{}, [], [])

def interleave.go(a, -A: Kind(a), fuel: Nat, xs: List<a, A>, ys: List<a, A>, out: List<a, A>) -> List<a, A>:
  match fuel xs:
    case 1n+k Con{x, rest}:
      interleave.go(a, A, k, ys, rest, x <> out)
    case _ _:
      onto(a, A, out, ys)

# The halves `deal` made, back in their order: one of `xs`, one of `ys`, and so on.
def interleave(a, -A: Kind(a), xs: List<a, A>, ys: List<a, A>) -> List<a, A>:
  interleave.go(a, A, 4294967295n, xs, ys, [])
