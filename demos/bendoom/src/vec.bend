# A copyable array of U32: a complete binary tree of 2^d leaves, Data
# like everything the sim reads, indexed in d steps. The low bit of an
# index picks the child, so a lookup needs no depth, and a tree is built
# from a list by splitting it into its even and odd positions.
import Base

type Vec is Data:
  Leaf{x: U32}
  Node{l: Vec, r: Vec}

def Vec.odd(+i: U32) -> Bool:
  U32.is_eq((i .&. 1 : U32), 1)

# The child is chosen by a bit passed in, computed for the next level
# beside the shifted index, so the recursion descends on the tree alone.
def Vec.get.go(v: Vec, odd: Bool, +i: U32) -> U32:
  match v odd:
    case Leaf{x} _:
      x
    case Node{l, r} False{}:
      Vec.get.go(l, Vec.odd((i >> 1n : U32)), (i >> 1n : U32))
    case Node{l, r} True{}:
      Vec.get.go(r, Vec.odd((i >> 1n : U32)), (i >> 1n : U32))

def Vec.get(v: Vec, +i: U32) -> U32:
  Vec.get.go(v, Vec.odd(i), i)

# The tree with x at index i, the nodes off the path shared with the
# old tree. A leaf standing for many indices, as a lump of zeros does,
# takes x for all of them.
def Vec.set.go(v: Vec, odd: Bool, +i: U32, x: U32) -> Vec:
  match v odd:
    case Leaf{y} _:
      Leaf{x}
    case Node{l, r} False{}:
      Node{Vec.set.go(l, Vec.odd((i >> 1n : U32)), (i >> 1n : U32), x), r}
    case Node{l, r} True{}:
      Node{l, Vec.set.go(r, Vec.odd((i >> 1n : U32)), (i >> 1n : U32), x)}

def Vec.set(v: Vec, +i: U32, x: U32) -> Vec:
  Vec.set.go(v, Vec.odd(i), i, x)

# The tree with every entry doubled.
def Vec.doubled(v: Vec) -> Vec:
  match v:
    case Leaf{x}:
      Leaf{(x * 2 : U32)}
    case Node{l, r}:
      Node{Vec.doubled(l), Vec.doubled(r)}

def Vec.split.cons(h: U32, p: List<&2, U32> & List<&2, U32>) ->
  List<&2, U32> & List<&2, U32>:
  (o, e) = p
  (h <> e, o)

# The elements at even positions beside those at odd ones.
def Vec.split(xs: List<&2, U32>) -> List<&2, U32> & List<&2, U32>:
  match xs:
    case []:
      ([], [])
    case h <> t:
      Vec.split.cons(h, Vec.split(t))

def Vec.head(xs: List<&2, U32>) -> U32:
  match xs:
    case []:
      0
    case h <> t:
      h

def Vec.of.go(d: Nat, eo: List<&2, U32> & List<&2, U32>) -> Vec:
  match d:
    case 0n:
      (e, o) = eo
      Leaf{Vec.head(e)}
    case 1n++p:
      (e, o) = eo
      Node{Vec.of.go(p, Vec.split(e)), Vec.of.go(p, Vec.split(o))}

def Vec.depth.go(fuel: Nat, +n: U32, +size: U32, d: Nat, done: Bool) -> Nat:
  match fuel done:
    case _ True{}:
      d
    case 0n _:
      d
    case 1n+f False{}:
      Vec.depth.go(f, n, (size * 2 : U32), 1n+d, U32.is_ge((size * 2 : U32), n))

# The least depth whose leaves hold n elements.
def Vec.depth(+n: U32) -> Nat:
  Vec.depth.go(32n, n, 1, 0n, U32.is_ge(1, n))

# The n elements of xs as a tree; missing ones read as zero.
def Vec.of_list(xs: List<&2, U32>, n: U32) -> Vec:
  Vec.of.go(Vec.depth(n), Vec.split(xs))

# A list as a tree of just its length.
def Vec.of(+xs: List<&2, U32>) -> Vec:
  Vec.of_list(xs, U32.from_nat(List.length(&2, U32, xs)))

# The n entries from i, each after a space.
def Vec.show(+v: Vec, n: Nat, +i: U32) -> String:
  match n:
    case 0n:
      ""
    case 1n+m:
      " " ++ U32.show(Vec.get(v, i)) ++ Vec.show(v, m, (i + 1 : U32))

# A list with x before it when it is kept.
def Vec.keep(~T: Data, keep: Bool, x: T, rest: List<&2, T>) -> List<&2, T>:
  match keep:
    case False{}:
      rest
    case True{}:
      x <> rest

# A copyable array of any Data with the same shape, a slot holding its
# element or none. It grows: each slot becomes a fork of itself and an
# empty one, so twice the indices fit and the old ones read as before.
type Tree<-A: Data> is Data:
  Slot{x: Maybe<&2, A>}
  Fork{l: Tree<A>, r: Tree<A>}

def Tree.empty(-A: Data, d: Nat) -> Tree<A>:
  match d:
    case 0n:
      Slot{None{}}
    case 1n++p:
      Fork{Tree.empty(A, p), Tree.empty(A, p)}

def Tree.get.go(-A: Data, t: Tree<A>, odd: Bool, +i: U32) -> Maybe<&2, A>:
  match t odd:
    case Slot{x} _:
      x
    case Fork{l, r} False{}:
      Tree.get.go(A, l, Vec.odd((i >> 1n : U32)), (i >> 1n : U32))
    case Fork{l, r} True{}:
      Tree.get.go(A, r, Vec.odd((i >> 1n : U32)), (i >> 1n : U32))

def Tree.get(-A: Data, t: Tree<A>, +i: U32) -> Maybe<&2, A>:
  Tree.get.go(A, t, Vec.odd(i), i)

def Tree.set.go(-A: Data, t: Tree<A>, odd: Bool, +i: U32, x: Maybe<&2, A>) -> Tree<A>:
  match t odd:
    case Slot{old} _:
      Slot{x}
    case Fork{l, r} False{}:
      Fork{Tree.set.go(A, l, Vec.odd((i >> 1n : U32)), (i >> 1n : U32), x), r}
    case Fork{l, r} True{}:
      Fork{l, Tree.set.go(A, r, Vec.odd((i >> 1n : U32)), (i >> 1n : U32), x)}

def Tree.set(-A: Data, t: Tree<A>, +i: U32, x: Maybe<&2, A>) -> Tree<A>:
  Tree.set.go(A, t, Vec.odd(i), i, x)

def Tree.grown(-A: Data, t: Tree<A>) -> Tree<A>:
  match t:
    case Slot{x}:
      Fork{Slot{x}, Slot{None{}}}
    case Fork{l, r}:
      Fork{Tree.grown(A, l), Tree.grown(A, r)}
