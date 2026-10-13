# Edits to texts, and places in them: the edits to make, spans that must not touch, and the lines and columns of
# offsets.
import Base
import ../shared/lists.bend as Lists
import ../shared/names.bend as Names
import ../shared/strings.bend as Strings

# Edits
# =====

# The text from `beg` to `end` in the file at `path`, replaced by `text`.
type Edit is Data:
  Edit{path: String, beg: U32, end: U32, text: String}

def Edit.path(edit: Edit) -> String:
  match edit:
    case Edit{path, beg, end, text}:
      path

def Edit.le(a: Edit, b: Edit) -> Bool:
  match a b:
    case Edit{p, x, e, t} Edit{q, y, f, u}:
      U32.is_le(x, y)

# `rest`, the text from `at` on, with `edits` (in order) made, after the pieces of `out` (last first). The pieces join
# once, at the end, so the text is copied once, whatever the number of edits.
def apply.go(edits: List<&2, Edit>, +rest: String, +at: U32, out: List<&2, String>) -> String:
  match edits:
    case Nil{}:
      Strings.joined(rest <> out, "")
    case Con{Edit{p, beg, +end, text}, more}:
      apply.go(
        more,
        String.drop(rest, U32.to_nat((end - at: U32))),
        end,
        text <> Strings.take(rest, U32.to_nat((beg - at: U32))) <> out
      )

# `text` with `edits` made. Edits must not overlap.
def apply(edits: List<&2, Edit>, text: String) -> String:
  apply.go(Lists.sort(~Edit, ~Edit.le, edits), text, 0, [])

# Spans
# =====

# Spans that never touch (`Spans.touch`), by place: a balanced (AVL) tree, by start, then end; `height` counts its
# levels. As spans never touch, their ends rise with their starts.
type Spans is Data:
  SLeaf{}
  SNode{height: U32, left: Spans, beg: U32, end: U32, right: Spans}

def Spans.height(t: Spans) -> U32:
  match t:
    case SLeaf{}:
      0
    case SNode{h, l, b, e, r}:
      h

# The node over `l` and `r`, whose heights differ by one at most.
def Spans.node(+l: Spans, b: U32, e: U32, +r: Spans) -> Spans:
  +hl = Spans.height(l)
  +hr = Spans.height(r)
  SNode{(Bool.pick(U32, U32.is_ge(hl, hr), hl, hr) + 1: U32), l, b, e, r}

def Spans.lean_left.by(
  outer: Bool,
  ll: Spans,
  lb: U32,
  le: U32,
  lr: Spans,
  b: U32,
  e: U32,
  r: Spans
) -> Spans:
  match outer lr:
    case False{} SNode{h, lrl, lrb, lre, lrr}:
      Spans.node(Spans.node(ll, lb, le, lrl), lrb, lre, Spans.node(lrr, b, e, r))
    case _ _:
      Spans.node(ll, lb, le, Spans.node(lr, b, e, r))

# The node over `l` and `r`, where `l` is two levels higher: turned right, after its left turns left if its inner side
# is the higher.
def Spans.lean_left(l: Spans, b: U32, e: U32, r: Spans) -> Spans:
  match l:
    case SNode{h, +ll, lb, le, +lr}:
      Spans.lean_left.by(U32.is_ge(Spans.height(ll), Spans.height(lr)), ll, lb, le, lr, b, e, r)
    case SLeaf{}:
      Spans.node(SLeaf{}, b, e, r)

def Spans.lean_right.by(
  outer: Bool,
  l: Spans,
  b: U32,
  e: U32,
  rl: Spans,
  rb: U32,
  re: U32,
  rr: Spans
) -> Spans:
  match outer rl:
    case False{} SNode{h, rll, rlb, rle, rlr}:
      Spans.node(Spans.node(l, b, e, rll), rlb, rle, Spans.node(rlr, rb, re, rr))
    case _ _:
      Spans.node(Spans.node(l, b, e, rl), rb, re, rr)

# The node over `l` and `r`, where `r` is two levels higher: the mirror of `lean_left`.
def Spans.lean_right(l: Spans, b: U32, e: U32, r: Spans) -> Spans:
  match r:
    case SNode{h, +rl, rb, re, +rr}:
      Spans.lean_right.by(U32.is_ge(Spans.height(rr), Spans.height(rl)), l, b, e, rl, rb, re, rr)
    case SLeaf{}:
      Spans.node(l, b, e, SLeaf{})

def Spans.balance.by(left: Bool, right: Bool, l: Spans, b: U32, e: U32, r: Spans) -> Spans:
  match left right:
    case True{} _:
      Spans.lean_left(l, b, e, r)
    case _ True{}:
      Spans.lean_right(l, b, e, r)
    case _ _:
      Spans.node(l, b, e, r)

# The node over `l` and `r`, balanced: their heights may differ by two.
def Spans.balance(+l: Spans, b: U32, e: U32, +r: Spans) -> Spans:
  +hl = Spans.height(l)
  +hr = Spans.height(r)
  Spans.balance.by(U32.is_gt(hl, (hr + 1: U32)), U32.is_gt(hr, (hl + 1: U32)), l, b, e, r)

def Spans.cmp.of(starts: Cmp, e: U32, y: U32) -> Cmp:
  match starts:
    case EQ{}:
      U32.cmp(e, y)
    case LT{}:
      LT{}
    case GT{}:
      GT{}

# How the span from `b` to `e` compares with the root's of `t`, by start, then end; GT past a leaf.
def Spans.cmp(t: Spans, b: U32, e: U32) -> Cmp:
  match t:
    case SNode{h, l, x, y, r}:
      Spans.cmp.of(U32.cmp(b, x), e, y)
    case SLeaf{}:
      GT{}

# `t` with the span from `b` to `e`; `side` is how it compares with the root's.
def Spans.add(t: Spans, +b: U32, +e: U32, side: Cmp) -> Spans:
  match t side:
    case SLeaf{} _:
      SNode{1, SLeaf{}, b, e, SLeaf{}}
    case SNode{h, +l, x, y, r} LT{}:
      Spans.balance(Spans.add(l, b, e, Spans.cmp(l, b, e)), x, y, r)
    case SNode{h, l, x, y, +r} _:
      Spans.balance(l, x, y, Spans.add(r, b, e, Spans.cmp(r, b, e)))

# Whether `t` holds the span from `b` to `e`; `side` is how it compares with the root's.
def Spans.has(t: Spans, +b: U32, +e: U32, side: Cmp) -> Bool:
  match t side:
    case SLeaf{} _:
      False{}
    case SNode{h, l, x, y, r} EQ{}:
      True{}
    case SNode{h, +l, x, y, r} LT{}:
      Spans.has(l, b, e, Spans.cmp(l, b, e))
    case SNode{h, l, x, y, +r} GT{}:
      Spans.has(r, b, e, Spans.cmp(r, b, e))

def Spans.starts_before(t: Spans, e: U32) -> Bool:
  match t:
    case SNode{h, l, x, y, r}:
      U32.is_lt(x, e)
    case SLeaf{}:
      False{}

# The end of the last span of `t` (by start, then end) that starts before `e`, or `found`. `before` says whether the
# root's does. Its end is the furthest of theirs, as ends rise with starts.
def Spans.last(t: Spans, +e: U32, found: Maybe<&2, U32>, before: Bool) -> Maybe<&2, U32>:
  match t before:
    case SLeaf{} _:
      found
    case SNode{h, l, x, y, +r} True{}:
      Spans.last(r, e, Some{y}, Spans.starts_before(r, e))
    case SNode{h, +l, x, y, r} False{}:
      Spans.last(l, e, found, Spans.starts_before(l, e))

def Spans.ends_after(last: Maybe<&2, U32>, b: U32) -> Bool:
  match last:
    case Some{y}:
      U32.is_lt(b, y)
    case None{}:
      False{}

# Whether the span from `b` to `e` touches one of `t`: they share a character, or two insertions are at one place.
def Spans.touch.insertion(insertion: Bool, +t: Spans, +b: U32, +e: U32) -> Bool:
  match insertion:
    case True{}:
      Spans.has(t, b, e, Spans.cmp(t, b, e))
    case False{}:
      False{}

def Spans.touch.of(shares: Bool, t: Spans, +b: U32, +e: U32) -> Bool:
  match shares:
    case True{}:
      True{}
    case False{}:
      Spans.touch.insertion(U32.is_eq(b, e), t, b, e)

def Spans.touch(+t: Spans, +b: U32, +e: U32) -> Bool:
  Spans.touch.of(Spans.ends_after(Spans.last(t, e, None{}, Spans.starts_before(t, e)), b), t, b, e)

# Places
# ======

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
    Lists.sort(
      ~Located,
      ~Located.le,
      Walk.located(Lists.sort(~Placed, ~Placed.le, Placed.of(offsets, 0, [])), text)
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
      places.group(rest, Names.Group.add(Placed, groups, path, Placed{offset, offset}))

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
            Lists.sort(~Placed, ~Placed.le, Names.Group.get(Placed, groups, path)),
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
