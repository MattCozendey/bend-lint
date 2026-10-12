# List helpers. They recurse only in tail position, so a long list is fine on the JS lane, whose stack is small;
# Base's append, concat, length, any and sort recurse on the stack.
import Base

def when(-A: Data, hit: Bool, v: A) -> Maybe<&2, A>:
  match hit:
    case True{}:
      Some{v}
    case False{}:
      None{}

# `xs`, last first, onto `out`.
def onto(a, -A: Kind(a), xs: List<a, A>, out: List<a, A>) -> List<a, A>:
  match xs:
    case Nil{}:
      out
    case Con{h, t}:
      onto(a, A, t, h <> out)

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
