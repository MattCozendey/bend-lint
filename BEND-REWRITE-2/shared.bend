# What more than one file of bend-lint uses.
import Base

# A value, with the name it is written as.
type Named<-A: Data> is Data:
  Named{name: String, value: A}

# The value `key` names in `table`.
def lookup(-A: Data, +key: String, table: List<&2, Named<A>>) -> Maybe<&2, A>:
  match table:
    case Nil{}:
      None{}
    case Con{Named{+k, +v}, rest}:
      Bool.pick(Maybe<&2, A>, String.eq(k, key), Some{v}, lookup(A, key, rest))

# `xs`, last first, onto `out`.
def onto(a, -A: Kind(a), xs: List<a, A>, out: List<a, A>) -> List<a, A>:
  match xs:
    case Nil{}:
      out
    case Con{h, t}:
      onto(a, A, t, h <> out)

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
    List.sort(~Located, ~Located.le, Walk.go(text, 0, 1, 1, Walk.emit(sorted, Walk.due(sorted, 0), 0, 1, 1, []))),
    []
  )

# Where each offset of `offsets` is in `text`, in order: one pass over the text, whatever the number of offsets.
def positions(text: String, offsets: List<&2, U32>) -> List<&2, Position>:
  positions.of(List.sort(~Placed, ~Placed.le, Placed.of(offsets, 0, [])), text)

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
