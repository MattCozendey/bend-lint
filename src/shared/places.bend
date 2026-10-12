import Base
import ./groups.bend as Groups
import ./lists.bend as Lists

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
      places.group(rest, Groups.Group.add(Placed, groups, path, Placed{offset, offset}))

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
            Lists.sort(~Placed, ~Placed.le, Groups.Group.get(Placed, groups, path)),
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
