import Base

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
