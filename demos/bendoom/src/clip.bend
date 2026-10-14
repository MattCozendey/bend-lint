# The solid columns: Doom's solidsegs, the screen columns a one-sided
# wall has already filled, as a sorted list of ranges with at least one
# open column between neighbours. Doom brackets its array with sentinel
# ranges off both screen edges to spare its loops the bounds checks; a
# list needs none, and the fragments come out the same. Columns are Nat,
# so the law that the list stays sorted is proven by induction rather
# than sampled. Each decision is a flag the caller computes for the next
# step, since a loop cannot match a computed Bool and then recurse.
import Base

type Clip.Range is Data:
  Range{first: Nat, last: Nat}

# Whether the head range ends at least two columns before first: it
# neither covers nor touches a range starting there.
def Clip.behind(rs: List<&2, Clip.Range>, first: Nat) -> Bool:
  match rs:
    case []:
      False{}
    case Range{f, l} <> rest:
      Nat.is_lt(1n+l, first)

# Whether the head range starts at least two columns after last.
def Clip.ahead(rs: List<&2, Clip.Range>, last: Nat) -> Bool:
  match rs:
    case []:
      False{}
    case Range{f, l} <> rest:
      Nat.is_lt(1n+last, f)

# The range lo to hi swallows every range it covers or touches.
def Clip.absorb(rs: List<&2, Clip.Range>, ahead: Bool, lo: Nat, +hi: Nat) -> List<&2, Clip.Range>:
  match rs ahead:
    case [] _:
      [Range{lo, hi}]
    case r <> rest True{}:
      Range{lo, hi} <> r <> rest
    case Range{rf, +rl} <> +rest False{}:
      Clip.absorb(rest, Clip.ahead(rest, Nat.max(hi, rl)), lo, Nat.max(hi, rl))

def Clip.add.go(rs: List<&2, Clip.Range>, behind: Bool, ahead: Bool, +first: Nat, +last: Nat) ->
  List<&2, Clip.Range>:
  match rs behind ahead:
    case [] _ _:
      [Range{first, last}]
    case r <> +rest True{} _:
      r <> Clip.add.go(rest, Clip.behind(rest, first), Clip.ahead(rest, last), first, last)
    case r <> rest False{} True{}:
      Range{first, last} <> r <> rest
    case Range{rf, +rl} <> +rest False{} False{}:
      Clip.absorb(rest, Clip.ahead(rest, Nat.max(last, rl)), Nat.min(first, rf), Nat.max(last, rl))

# Doom's R_ClipSolidWallSegment, the list's half: the columns first to
# last become solid.
def Clip.add(+first: Nat, +last: Nat, +rs: List<&2, Clip.Range>) -> List<&2, Clip.Range>:
  Clip.add.go(rs, Clip.behind(rs, first), Clip.ahead(rs, last), first, last)

# Whether the head range ends before first, or starts after last: it
# covers none of first to last.
def Clip.left(rs: List<&2, Clip.Range>, first: Nat) -> Bool:
  match rs:
    case []:
      False{}
    case Range{f, l} <> rest:
      Nat.is_lt(l, first)

def Clip.right(rs: List<&2, Clip.Range>, last: Nat) -> Bool:
  match rs:
    case []:
      False{}
    case Range{f, l} <> rest:
      Nat.is_lt(last, f)

def Clip.gaps.lead(open: Bool, first: Nat, rf: Nat, rest: List<&2, Clip.Range>) -> List<&2, Clip.Range>:
  match open:
    case True{}:
      Range{first, Nat.sub(rf, 1n)} <> rest
    case False{}:
      rest

def Clip.gaps.go(rs: List<&2, Clip.Range>, empty: Bool, left: Bool, right: Bool, +first: Nat,
  +last: Nat) -> List<&2, Clip.Range>:
  match rs empty left right:
    case _ True{} _ _:
      []
    case [] False{} _ _:
      [Range{first, last}]
    case r <> +rest False{} True{} _:
      Clip.gaps.go(rest, False{}, Clip.left(rest, first), Clip.right(rest, last), first, last)
    case r <> rest False{} False{} True{}:
      [Range{first, last}]
    case Range{+rf, +rl} <> +rest False{} False{} False{}:
      Clip.gaps.lead(Nat.is_lt(first, rf), first, rf,
        Clip.gaps.go(rest, Nat.is_lt(last, 1n+rl), Clip.left(rest, 1n+rl), Clip.right(rest, last),
          1n+rl, last))

# The fragments of first to last that no solid range covers, left to
# right: what Doom's two clip functions hand to R_StoreWallRange.
def Clip.gaps(+first: Nat, +last: Nat, +rs: List<&2, Clip.Range>) -> List<&2, Clip.Range>:
  Clip.gaps.go(rs, Nat.is_lt(last, first), Clip.left(rs, first), Clip.right(rs, last), first, last)

def Clip.covers.go(rs: List<&2, Clip.Range>, short: Bool, +first: Nat, +last: Nat) -> Bool:
  match rs short:
    case [] _:
      False{}
    case r <> +rest True{}:
      Clip.covers.go(rest, Clip.left(rest, last), first, last)
    case Range{rf, rl} <> rest False{}:
      Nat.is_le(rf, first)

# Doom's R_CheckBBox, the list's half: whether the first range reaching
# last holds all of first to last.
def Clip.covers(+first: Nat, +last: Nat, +rs: List<&2, Clip.Range>) -> Bool:
  Clip.covers.go(rs, Clip.left(rs, last), first, last)

# Sorted: every range runs from a first to a last no less, and the next
# starts at least two columns on.
def Clip.apart(rs: List<&2, Clip.Range>, last: Nat) -> Bool:
  match rs:
    case []:
      True{}
    case Range{f, l} <> rest:
      Nat.is_lt(1n+last, f)

def Clip.sorted(rs: List<&2, Clip.Range>) -> Bool:
  match rs:
    case []:
      True{}
    case Range{first, +last} <> +rest:
      Bool.and(Nat.is_le(first, last), Bool.and(Clip.apart(rest, last), Clip.sorted(rest)))
