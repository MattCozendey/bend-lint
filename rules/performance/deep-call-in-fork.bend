# performance/deep-call-in-fork: a fork that first calls a def that
# recurses without a tail call. A def has a parallel let, and its values,
# or the lets just before it, call a def of the file whose call of itself
# is not in tail position. In our tests, on the native lane, such a call
# at each fork cut the 16-thread speedup from 10x to 1.9x; the same def
# with a tail call kept it. The finding has no fix.
# Run: bun src/lint.ts file.bend --rules rules/performance/deep-call-in-fork.bend
import Base
import ../../src/bend/lint.bend as Lint
import ../shared.bend as Shared

# Types
# =====

# A def of the file: its name, its number of parameters and its body.
type Def is Data:
  Def{name: String, arity: Nat, body: Lint.Node}

# A step of a climb from a node to its ancestors: read its parent, read the
# parent's shape, or look at both.
type Climb is Data:
  Up{}
  Parent{parent: Maybe<&2, Lint.Node>}
  Shaped{parent: Lint.Node, shape: Lint.Shape}

# Constants
# =========

# The fuel to climb from a node to its def's body: three steps per ancestor.
def climb_fuel() -> Nat:
  4096n

# Functions
# =========
def kid_index(ks: List<&2, Lint.Node>, +n: Lint.Node, +i: Nat) -> Nat:
  match ks:
    case Con{k, rest}:
      Bool.pick(Nat, Shared.same_node(k, n), i, kid_index(rest, n, 1n+i))
    case Nil{}:
      i

# Whether `n`, a child of a node of shape `s`, is in tail position there: the
# body of a let, a lambda, a match's case or an annotation. A value of a
# parallel let counts as tail: a fork is not a loop.
def in_tail(s: Lint.Shape, +n: Lint.Node) -> Bool:
  match s:
    case Lint.Shape{"Let", name, span, +kids}:
      +k = List.length(&2, Lint.Node, kids)
      Bool.or(Nat.is_eq(1n+kid_index(kids, n, 0n), k), Nat.is_ge(k, 3n))
    case Lint.Shape{"App", name, span, kids}:
      False{}
    case Lint.Shape{"Ctr", name, span, kids}:
      False{}
    case _:
      True{}

# Whether `n` is in tail position in its def: each ancestor up to the body
# holds it in tail position.
def tail(fuel: Nat, c: Climb, +n: Lint.Node) -> IO(Bool):
  match fuel c:
    case 1n+k Up{}:
      IO.bind(Maybe<&2, Lint.Node>, Bool, Lint.parent(n), m => tail(k, Parent{m}, n))
    case 1n+k Parent{Some{+p}}:
      IO.bind(Lint.Shape, Bool, Lint.shape(p), s => tail(k, Shaped{p, s}, n))
    case 1n+k Shaped{+p, s}:
      Bool.pick(IO(Bool), in_tail(s, n), tail(k, Up{}, p), IO.pure(Bool, False{}))
    case _ _:
      IO.pure(Bool, True{})

def own_call(+self: String, +arity: Nat, h: Lint.Shape, sp: Shared.Spine) -> Bool:
  match sp:
    case Shared.Spine{head, args}:
      Bool.and(
        String.eq(Shared.ref_name(h), self),
        Nat.is_eq(List.length(&2, Lint.Node, args), arity)
      )

def not_tail(own: Bool, +n: Lint.Node) -> IO(Bool):
  match own:
    case True{}:
      IO.bind(Bool, Bool, tail(climb_fuel(), Up{}, n), t => IO.pure(Bool, Bool.not(t)))
    case False{}:
      IO.pure(Bool, False{})

# Whether `n`, of shape `s`, is a call of `self` to itself out of tail
# position.
def deep_at(+self: String, +arity: Nat, +n: Lint.Node, s: Lint.Shape) -> IO(Bool):
  match s:
    case Lint.Shape{"App", name, span, kids}:
      do IO<Bool>:
        +sp: Shared.Spine <- Shared.call_of(n)
        h: Lint.Shape <- Shared.head_shape(sp)
        not_tail(own_call(self, arity, h, sp), n)
    case _:
      IO.pure(Bool, False{})

def any_deep(ns: List<&2, Lint.Node>, +self: String, +arity: Nat) -> IO(Bool):
  match ns:
    case Nil{}:
      IO.pure(Bool, False{})
    case Con{+n, rest}:
      do IO<Bool>:
        s: Lint.Shape <- Lint.shape(n)
        b: Bool <- deep_at(self, arity, n, s)
        more: Bool <- any_deep(rest, self, arity)
        return Bool.or(b, more)

def keep_deep(hit: Bool, d: Def, ds: List<&2, Def>) -> List<&2, Def>:
  match hit:
    case True{}:
      Con{d, ds}
    case False{}:
      ds

# The defs of `ds` that recurse without a tail call.
def deeps(ds: List<&2, Def>) -> IO(List<&2, Def>):
  match ds:
    case Nil{}:
      IO.pure(List<&2, Def>, [])
    case Con{Def{+name, +arity, +body}, rest}:
      do IO<List<&2, Def>>:
        ns: List<&2, Lint.Node> <- Lint.nodes(body)
        hit: Bool <- any_deep(ns, name, arity)
        more: List<&2, Def> <- deeps(rest)
        return keep_deep(hit, Def{name, arity, body}, more)

# The values of the lets just before `n`, in the same block, from the
# nearest on, put in front of `acc`.
def before(fuel: Nat, c: Climb, +n: Lint.Node, acc: List<&2, Lint.Node>) -> IO(List<&2, Lint.Node>):
  match fuel c:
    case 1n+k Up{}:
      IO.bind(
        Maybe<&2, Lint.Node>,
        List<&2, Lint.Node>,
        Lint.parent(n),
        m => before(k, Parent{m}, n, acc)
      )
    case 1n+k Parent{Some{+p}}:
      IO.bind(Lint.Shape, List<&2, Lint.Node>, Lint.shape(p), s => before(k, Shaped{p, s}, n, acc))
    case 1n+k Shaped{+p, Lint.Shape{"Ann", name, span, kids}}:
      before(k, Up{}, p, acc)
    case 1n+k Shaped{+p, Lint.Shape{"Let", name, span, Con{v, Con{b, Nil{}}}}}:
      before(k, Up{}, p, Con{v, acc})
    case _ _:
      IO.pure(List<&2, Lint.Node>, acc)

def all_but_last(ns: List<&2, Lint.Node>) -> List<&2, Lint.Node>:
  match ns:
    case Con{n, Nil{}}:
      []
    case Con{n, rest}:
      Con{n, all_but_last(rest)}
    case Nil{}:
      []

# The nodes under each of `roots`.
def under(roots: List<&2, Lint.Node>) -> IO(List<&2, Lint.Node>):
  match roots:
    case Nil{}:
      IO.pure(List<&2, Lint.Node>, [])
    case Con{r, rest}:
      do IO<List<&2, Lint.Node>>:
        ns: List<&2, Lint.Node> <- Lint.nodes(r)
        more: List<&2, Lint.Node> <- under(rest)
        return List.append(&2, Lint.Node, ns, more)

# The nodes evaluated at the fork `n`, of shape `s`, before its calls run:
# its values, and the values of the lets just before it.
def at_fork(+n: Lint.Node, s: Lint.Shape) -> IO(List<&2, Lint.Node>):
  match s:
    case Lint.Shape{"Let", name, span, +kids}:
      Bool.pick(
        IO(List<&2, Lint.Node>),
        Nat.is_ge(List.length(&2, Lint.Node, kids), 3n),
        IO.bind(
          List<&2, Lint.Node>,
          List<&2, Lint.Node>,
          before(climb_fuel(), Up{}, n, all_but_last(kids)),
          under
        ),
        IO.pure(List<&2, Lint.Node>, [])
      )
    case _:
      IO.pure(List<&2, Lint.Node>, [])

def forks(ns: List<&2, Lint.Node>) -> IO(List<&2, Lint.Node>):
  match ns:
    case Nil{}:
      IO.pure(List<&2, Lint.Node>, [])
    case Con{+n, rest}:
      do IO<List<&2, Lint.Node>>:
        s: Lint.Shape <- Lint.shape(n)
        here: List<&2, Lint.Node> <- at_fork(n, s)
        more: List<&2, Lint.Node> <- forks(rest)
        return List.append(&2, Lint.Node, here, more)

def deep_named(ds: List<&2, Def>, +name: String, +arity: Nat) -> Bool:
  match ds:
    case Nil{}:
      False{}
    case Con{Def{n, a, b}, rest}:
      Bool.or(Bool.and(String.eq(n, name), Nat.is_eq(a, arity)), deep_named(rest, name, arity))

def finding(
  hit: Bool,
  +self: String,
  +callee: String,
  span: Maybe<&2, Lint.Span>
) -> List<&2, Lint.Diag>:
  match hit:
    case True{}:
      [
        Lint.Diag{
          Lint.Warning{},
          callee
            ++ " recurses without a tail call, and "
            ++ self
            ++ " calls it at each fork. In our tests, such a call cut the 16-thread speedup from 10x to 1.9x; a tail call kept it. Make "
            ++ callee
            ++ " tail-recursive with an accumulator, compute its value with native operations, or pass it down as a parameter.",
          span,
          [],
          None{}
        }
      ]
    case False{}:
      []

def call_finding(+deep: List<&2, Def>, +self: String, c: Shared.Call) -> List<&2, Lint.Diag>:
  match c:
    case Shared.Call{+head, args, span}:
      finding(
        Bool.and(
          Bool.not(String.eq(head, self)),
          deep_named(deep, head, List.length(&2, Shared.Arg, args))
        ),
        self,
        head,
        span
      )

def call_findings(
  +deep: List<&2, Def>,
  +self: String,
  cs: List<&2, Shared.Call>
) -> List<&2, Lint.Diag>:
  match cs:
    case Nil{}:
      []
    case Con{c, rest}:
      List.append(&2, Lint.Diag, call_finding(deep, self, c), call_findings(deep, self, rest))

def in_def(+deep: List<&2, Def>, d: Def) -> IO(List<&2, Lint.Diag>):
  match d:
    case Def{+name, arity, body}:
      do IO<List<&2, Lint.Diag>>:
        ns: List<&2, Lint.Node> <- Lint.nodes(body)
        at: List<&2, Lint.Node> <- forks(ns)
        cs: List<&2, Shared.Call> <- Shared.calls(at, [])
        return List.reverse(&2, Lint.Diag, call_findings(deep, name, cs))

def in_defs(+deep: List<&2, Def>, ds: List<&2, Def>) -> IO(List<&2, Lint.Diag>):
  match ds:
    case Nil{}:
      IO.pure(List<&2, Lint.Diag>, [])
    case Con{d, rest}:
      do IO<List<&2, Lint.Diag>>:
        here: List<&2, Lint.Diag> <- in_def(deep, d)
        more: List<&2, Lint.Diag> <- in_defs(deep, rest)
        return List.append(&2, Lint.Diag, here, more)

def def_of(+name: String, +arity: Nat, m: Maybe<&2, Lint.Node>) -> List<&2, Def>:
  match m:
    case Some{b}:
      [Def{name, arity, b}]
    case None{}:
      []

# The top-level defs of `ds` that have a body, in file order; `all` are the
# file's declarations.
def defs(+all: List<&2, Lint.Declaration>, ds: List<&2, Lint.Declaration>) -> IO(List<&2, Def>):
  match ds:
    case Nil{}:
      IO.pure(List<&2, Def>, [])
    case Con{
      Lint.Declaration{Lint.Definition{}, +name, None{}, span, refs, loads, fills, term},
      rest
    }:
      do IO<List<&2, Def>>:
        m: Maybe<&2, Lint.Node> <- Lint.body(name)
        more: List<&2, Def> <- defs(all, rest)
        return List.append(
          &2,
          Def,
          def_of(name, List.length(&2, String, Shared.params_of(all, name)), m),
          more
        )
    case Con{d, rest}:
      defs(all, rest)

# Rule
# ====
def id() -> String:
  "performance/deep-call-in-fork"

def facts() -> Lint.Want:
  Lint.NoFacts{}

def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
  do IO<List<&2, Lint.Diag>>:
    +ds: List<&2, Lint.Declaration> <- Lint.declarations()
    +all: List<&2, Def> <- defs(ds, ds)
    deep: List<&2, Def> <- deeps(all)
    in_defs(deep, all)

def main() -> IO(Unit):
  Lint.serve(run)
