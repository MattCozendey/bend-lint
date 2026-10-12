# Bend helpers that are not about linting. The list functions here recurse only in tail position, so a long list
# is fine on the JS lane, whose stack is small; Base's append, concat, length, any and sort recurse on the stack.
import Base

# A value, with the name it is written as.
type Named<-A: Data> is Data:
  Named{name: String, value: A}

def when(-A: Data, hit: Bool, v: A) -> Maybe<&2, A>:
  match hit:
    case True{}:
      Some{v}
    case False{}:
      None{}

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
      lookup.go(A, key, rest, when(A, String.eq(k, key), v))

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

# `xs`, last first, onto `out`.
def onto(a, -A: Kind(a), xs: List<a, A>, out: List<a, A>) -> List<a, A>:
  match xs:
    case Nil{}:
      out
    case Con{h, t}:
      onto(a, A, t, h <> out)

def take.go(n: Nat, s: String, acc: String) -> String:
  match n s:
    case 1n+k SCon{c, rest}:
      take.go(k, rest, SCon{c, acc})
    case _ _:
      String.reverse(acc)

# The first `n` characters of `s`. Base's String.take is not tail-recursive, so long text would overflow the stack.
def take(s: String, n: Nat) -> String:
  take.go(n, s, "")

# The text of `text` from `beg` to `end`, in code points.
def slice(text: String, +beg: U32, end: U32) -> String:
  take(String.drop(text, U32.to_nat(beg)), U32.to_nat((end - beg: U32)))

def line_start.go(s: String, +i: U32, +at: U32, start: U32, going: Bool) -> U32:
  match s going:
    case _ False{}:
      start
    case SNil{} True{}:
      start
    case SCon{c, rest} True{}:
      line_start.go(
        rest,
        (i + 1: U32),
        at,
        Bool.pick(U32, Char.is_eq(c, '\n'), (i + 1: U32), start),
        U32.is_lt((i + 1: U32), at)
      )

# Where the line of `text` that holds the offset `at` starts: after the last newline before it.
def line_start(text: String, +at: U32) -> U32:
  line_start.go(text, 0, at, 0, U32.is_lt(0, at))

def line_end.go(s: String, i: U32) -> U32:
  match s:
    case SNil{}:
      i
    case SCon{'\n', rest}:
      (i + 1: U32)
    case SCon{c, rest}:
      line_end.go(rest, (i + 1: U32))

# Where the line of `text` that starts at `beg` ends: after its newline, or at the end of the text.
def line_end(text: String, +beg: U32) -> U32:
  line_end.go(String.drop(text, U32.to_nat(beg)), beg)

def append(a, -A: Kind(a), xs: List<a, A>, ys: List<a, A>) -> List<a, A>:
  onto(a, A, List.reverse(a, A, xs), ys)

def concat.go(a, -A: Kind(a), xss: List<a, List<a, A>>, out: List<a, A>) -> List<a, A>:
  match xss:
    case Nil{}:
      List.reverse(a, A, out)
    case Con{xs, rest}:
      concat.go(a, A, rest, onto(a, A, xs, out))

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

def push(-A: Data, x: Maybe<&2, A>, out: List<&2, A>) -> List<&2, A>:
  match x:
    case Some{v}:
      v <> out
    case None{}:
      out

def starts(s: String, c: Char) -> Bool:
  match s:
    case SCon{h, t}:
      Char.is_eq(h, c)
    case SNil{}:
      False{}

def before.go(s: String, +sep: Char, acc: String, at: Bool) -> String:
  match s at:
    case SNil{} _:
      ""
    case _ True{}:
      String.reverse(acc)
    case SCon{c, +rest} False{}:
      before.go(rest, sep, SCon{c, acc}, starts(rest, sep))

# What comes before the first `sep` of `s`, or "" if there is none.
def before(+s: String, +sep: Char) -> String:
  before.go(s, sep, "", starts(s, sep))

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
def sort.go(
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
      concat(&2, A, runs)
    case 1n+f _:
      sort.go(~A, ~le, f, n, sort.pass(~A, ~le, n, runs, []))

# `xs` in `le` order, stable: a bottom-up merge sort.
def sort(~A: Data, ~le: A -> A -> Bool, xs: List<&2, A>) -> List<&2, A>:
  +ys = {xs: List<&2, A>}
  +n = length(&2, A, ys)
  sort.go(~A, ~le, n, n, sort.runs(A, ys, []))

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

# The chunks of `chunks` (last first) as one text, before `out`. Each chunk is copied once, so it is linear.
def joined(chunks: List<&2, String>, out: String) -> String:
  match chunks:
    case Nil{}:
      out
    case Con{c, rest}:
      joined(rest, c ++ out)

# A place in a text: its line and its column, from 1. A column counts UTF-16 units, as editors do.
type Position is Data:
  Position{line: U32, column: U32}

# An offset in the file at `path`.
type Place is Data:
  Place{path: String, offset: U32}

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
      Placed.of(rest, (index + 1: U32), Placed{index, o} <> out)

def Walk.due(pending: List<&2, Placed>, at: U32) -> Bool:
  match pending:
    case Con{Placed{i, offset}, rest}:
      U32.is_le(offset, at)
    case Nil{}:
      False{}

# The offsets due at `at`, placed at `line` and `column`.
def Walk.emit(
  pending: List<&2, Placed>,
  due: Bool,
  +at: U32,
  +line: U32,
  +column: U32,
  out: List<&2, Located>
) -> Walk:
  match pending due:
    case Con{Placed{i, offset}, +rest} True{}:
      Walk.emit(
        rest,
        Walk.due(rest, at),
        at,
        line,
        column,
        Located{i, Position{line, column}} <> out
      )
    case _ _:
      Walk{pending, out}

def Walk.done(w: Walk) -> List<&2, Located>:
  match w:
    case Walk{pending, out}:
      out

# The offsets placed, one character of `text` at a time; offsets past its end are placed at its end.
def Walk.go(text: String, +at: U32, +line: U32, column: U32, w: Walk) -> List<&2, Located>:
  match text w:
    case _ Walk{Nil{}, out}:
      out
    case SNil{} Walk{pending, out}:
      Walk.done(Walk.emit(pending, True{}, 4294967295, line, column, out))
    case SCon{+c, t} Walk{+pending, out}:
      +ends = Char.is_eq(c, '\n')
      +l = Bool.pick(U32, ends, (line + 1: U32), line)
      +col = Bool.pick(
        U32,
        ends,
        1,
        (column + Bool.pick(U32, U32.is_ge(Char.to_u32(c), 65536), 2, 1): U32)
      )
      Walk.go(
        t,
        (at + 1: U32),
        l,
        col,
        Walk.emit(pending, Walk.due(pending, (at + 1: U32)), (at + 1: U32), l, col, out)
      )

def Walk.positions(located: List<&2, Located>, out: List<&2, Position>) -> List<&2, Position>:
  match located:
    case Nil{}:
      List.reverse(&2, Position, out)
    case Con{Located{i, at}, rest}:
      Walk.positions(rest, at <> out)

# The offsets of `sorted` (in offset order) placed in `text`, in no order.
def Walk.located(+sorted: List<&2, Placed>, text: String) -> List<&2, Located>:
  Walk.go(text, 0, 1, 1, Walk.emit(sorted, Walk.due(sorted, 0), 0, 1, 1, []))

# Where each offset of `offsets` is in `text`, in order: one pass over the text, whatever the number of offsets.
def positions(text: String, offsets: List<&2, U32>) -> List<&2, Position>:
  Walk.positions(
    sort(
      ~Located,
      ~Located.le,
      Walk.located(sort(~Placed, ~Placed.le, Placed.of(offsets, 0, [])), text)
    ),
    []
  )

def Place.key(path: String, offset: U32) -> String:
  path ++ "\t" ++ U32.show(offset)

# Where the offset `offset` of the file at `path` is, among `places` (what `places` gives); 1:1 if it is not there.
def Place.at(places: Map<&2, Position>, path: String, offset: U32) -> Position:
  Pair.snd(
    Map<&2, Position>,
    Position,
    Map.get(Position, Position{1, 1}, places, Place.key(path, offset))
  )

# The requests by file, each offset numbered by itself, onto `groups`.
def places.group(
  requests: List<&2, Place>,
  groups: Map<&2, List<&2, Placed>>
) -> Map<&2, List<&2, Placed>>:
  match requests:
    case Nil{}:
      groups
    case Con{Place{path, +offset}, rest}:
      places.group(rest, Group.add(Placed, groups, path, Placed{offset, offset}))

# The places found in the file at `path`, by key, onto `out`.
def places.keep(
  located: List<&2, Located>,
  +path: String,
  out: Map<&2, Position>
) -> Map<&2, Position>:
  match located:
    case Nil{}:
      out
    case Con{Located{offset, at}, rest}:
      places.keep(rest, path, Map.set(&2, Position, out, Place.key(path, offset), at))

# The requests of each file of `paths` placed in its text, onto `out`; a file `texts` lacks places them at its start.
def places.walk(
  paths: List<&2, String>,
  +groups: Map<&2, List<&2, Placed>>,
  +texts: Map<&2, String>,
  out: Map<&2, Position>
) -> Map<&2, Position>:
  match paths:
    case Nil{}:
      out
    case Con{+path, rest}:
      places.walk(
        rest,
        groups,
        texts,
        places.keep(
          Walk.located(
            sort(~Placed, ~Placed.le, Group.get(Placed, groups, path)),
            Pair.snd(Map<&2, String>, String, Map.get(String, "", texts, path))
          ),
          path,
          out
        )
      )

# Where each requested offset is, by key (read with `Place.at`): one pass over each file asked about, whatever the
# number of requests. `texts` holds the files' texts, by path.
def places(texts: Map<&2, String>, requests: List<&2, Place>) -> Map<&2, Position>:
  +groups = places.group(requests, Map.new(&2, List<&2, Placed>))
  places.walk(Map.keys(&2, List<&2, Placed>, groups), groups, texts, Map.new(&2, Position))

def deal.go(
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
      deal.go(a, A, t, False{}, h <> l, r)
    case Con{h, t} False{}:
      deal.go(a, A, t, True{}, l, h <> r)

# `xs` dealt into two halves, each in order: those at even positions, and those at odd ones. `interleave` undoes it.
def deal(a, -A: Kind(a), xs: List<a, A>) -> List<a, A> & List<a, A>:
  deal.go(a, A, xs, True{}, [], [])

def interleave.go(
  a,
  -A: Kind(a),
  fuel: Nat,
  xs: List<a, A>,
  ys: List<a, A>,
  out: List<a, A>
) -> List<a, A>:
  match fuel xs:
    case 1n+k Con{x, rest}:
      interleave.go(a, A, k, ys, rest, x <> out)
    case _ _:
      onto(a, A, out, ys)

# The halves `deal` made, back in their order: one of `xs`, one of `ys`, and so on.
def interleave(a, -A: Kind(a), xs: List<a, A>, ys: List<a, A>) -> List<a, A>:
  interleave.go(a, A, 4294967295n, xs, ys, [])

# Values by number, from 0: a balanced tree. Each node parts its values by a bit of their number, the lowest first, so
# a lookup reads the bits of a number, and no text.
type Table<-A: Data> is Data:
  TLeaf{value: Maybe<&2, A>}
  TNode{even: Table<A>, odd: Table<A>}

# A table and its size, a power of two.
type Indexed<-A: Data> is Data:
  Indexed{size: U32, table: Table<A>}

# The smallest power of two at least `n`, and its exponent.
def Table.fit(fuel: Nat, +n: U32, +size: U32, depth: Nat, fits: Bool) -> U32 & Nat:
  match fuel fits:
    case _ True{}:
      (size, depth)
    case 0n False{}:
      (size, depth)
    case 1n+f False{}:
      Table.fit(f, n, (size * 2: U32), 1n+depth, U32.is_le(n, (size * 2: U32)))

# The node over the values parted in `halves` (those at even places, and those at odd), `depth` levels above its leaves.
def Table.grow(-A: Data, +depth: Nat, halves: List<&2, A> & List<&2, A>) -> Table<A>:
  match depth halves:
    case 0n Tuple{e, o}:
      TNode{TLeaf{List.head(&2, A, e)}, TLeaf{List.head(&2, A, o)}}
    case 1n+d Tuple{e, o}:
      # bend-lint: expect-next performance/missed-fork@information -- measured: forking the halves made no run faster, as the table is a small part of a run
      TNode{Table.grow(A, d, deal(&2, A, e)), Table.grow(A, d, deal(&2, A, o))}

def Table.root(-A: Data, depth: Nat, xs: List<&2, A>) -> Table<A>:
  match depth:
    case 0n:
      TLeaf{List.head(&2, A, xs)}
    case 1n+d:
      Table.grow(A, d, deal(&2, A, xs))

def Table.sized(-A: Data, xs: List<&2, A>, fit: U32 & Nat) -> Indexed<A>:
  match fit:
    case Tuple{size, depth}:
      Indexed{size, Table.root(A, depth, xs)}

# The values of `xs`, numbered from 0; `n` is its length.
def Table.of(-A: Data, +n: U32, xs: List<&2, A>) -> Indexed<A>:
  Table.sized(A, xs, Table.fit(33n, n, 1, 0n, U32.is_le(n, 1)))

# The value numbered `i` in `t`: `odd` is whether `i` is.
def Table.at(-A: Data, t: Table<A>, +i: U32, odd: Bool) -> Maybe<&2, A>:
  match t odd:
    case TLeaf{v} _:
      v
    case TNode{e, o} False{}:
      Table.at(A, e, U32.shr(i), U32.is_eq(U32.and(U32.shr(i), 1), 1))
    case TNode{e, o} True{}:
      Table.at(A, o, U32.shr(i), U32.is_eq(U32.and(U32.shr(i), 1), 1))

def Table.find(-A: Data, t: Table<A>, +i: U32, inside: Bool) -> Maybe<&2, A>:
  match inside:
    case False{}:
      None{}
    case True{}:
      Table.at(A, t, i, U32.is_eq(U32.and(i, 1), 1))

def Indexed.get(-A: Data, x: Indexed<A>, +i: U32) -> Maybe<&2, A>:
  match x:
    case Indexed{size, table}:
      Table.find(A, table, i, U32.is_lt(i, size))
