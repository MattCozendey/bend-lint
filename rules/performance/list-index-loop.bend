# performance/list-index-loop: a loop that reads a list from its head on
# each step. A def passes a list parameter unchanged to its own call, and
# also gives it to List.get, List.drop, List.take, List.last or
# List.length. Each of those walks the list from its head, so the loop is
# O(n²) where a walk of the list is O(n). The finding has no fix: the
# rewrite changes the loop's parameters.
# Run: bun src/lint.ts file.bend --rules rules/performance/list-index-loop.bend
import Base
import ../../src/bend/lint.bend as Lint
import ../shared.bend as Shared

# Types
# =====

# A call in a def's body: its head's name, the name of the variable each
# argument is (or ""), and its span.
type Call is Data:
  Call{head: String, args: List<&2, String>, span: Maybe<&2, Lint.Span>}

# A list function that walks a list from its head: its name, its arity,
# and what to do instead.
type Walker is Data:
  Walker{name: String, arity: Nat, advice: String}

# Constants
# =========
def walk_advice() -> String:
  "Walk it instead: match it, use its head, and pass its tail to the next call."

# The list functions that walk a list from its head.
def walkers() -> List<&2, Walker>:
  [
    Walker{"List.get", 4n, walk_advice()},
    Walker{"List.drop", 4n, walk_advice()},
    Walker{"List.take", 4n, walk_advice()},
    Walker{"List.last", 3n, walk_advice()},
    Walker{"List.length", 3n, "Compute it once before the loop, and pass it as a parameter."}
  ]

# Functions
# =========
def nth(xs: List<&2, String>, n: Nat) -> String:
  match xs n:
    case Con{x, rest} 0n:
      x
    case Con{x, rest} 1n+k:
      nth(rest, k)
    case Nil{} _:
      ""

# The position of `x` in `xs`, if it is there.
def position(xs: List<&2, String>, +x: String, +i: Nat) -> Maybe<&2, Nat>:
  match xs:
    case Nil{}:
      None{}
    case Con{y, rest}:
      Bool.pick(Maybe<&2, Nat>, String.eq(y, x), Some{i}, position(rest, x, 1n+i))

def var_of(s: Lint.Shape) -> String:
  match s:
    case Lint.Shape{"Var", name, span, kids}:
      name
    case _:
      ""

# The variable each node is, or "".
def vars_of(ns: List<&2, Lint.Node>) -> IO(List<&2, String>):
  match ns:
    case Nil{}:
      IO.pure(List<&2, String>, [])
    case Con{n, rest}:
      do IO<List<&2, String>>:
        bare: Lint.Node <- Lint.strip(n)
        s: Lint.Shape <- Lint.shape(bare)
        vs: List<&2, String> <- vars_of(rest)
        return Con{var_of(s), vs}

def name_of(s: Lint.Shape) -> String:
  match s:
    case Lint.Shape{"Ref", name, span, kids}:
      name
    case _:
      ""

def call_at(sp: Shared.Spine, span: Maybe<&2, Lint.Span>) -> IO(Call):
  match sp:
    case Shared.Spine{head, args}:
      do IO<Call>:
        h: Lint.Shape <- Lint.shape(head)
        vs: List<&2, String> <- vars_of(args)
        return Call{name_of(h), vs, span}

def calls_in(s: Lint.Shape, +n: Lint.Node) -> IO(List<&2, Call>):
  match s:
    case Lint.Shape{"App", name, span, kids}:
      do IO<List<&2, Call>>:
        sp: Shared.Spine <- Shared.call_of(n)
        c: Call <- call_at(sp, span)
        return [c]
    case _:
      IO.pure(List<&2, Call>, [])

# Every call in `ns`. A call of n arguments is n nested App nodes; each is
# listed, with its own count of arguments.
def calls(ns: List<&2, Lint.Node>, acc: List<&2, Call>) -> IO(List<&2, Call>):
  match ns:
    case Nil{}:
      IO.pure(List<&2, Call>, acc)
    case Con{+n, rest}:
      do IO<List<&2, Call>>:
        s: Lint.Shape <- Lint.shape(n)
        cs: List<&2, Call> <- calls_in(s, n)
        calls(rest, List.append(&2, Call, cs, acc))

# Whether a call of `self` passes `v` at position `k`, unchanged.
def passes(cs: List<&2, Call>, +self: String, +arity: Nat, +k: Nat, +v: String) -> Bool:
  match cs:
    case Nil{}:
      False{}
    case Con{Call{head, +args, span}, rest}:
      Bool.or(
        Bool.and(
          Bool.and(String.eq(head, self), Nat.is_eq(List.length(&2, String, args), arity)),
          String.eq(nth(args, k), v)
        ),
        passes(rest, self, arity, k, v)
      )

# Whether def `self`, with parameters `params`, passes `v` unchanged to its
# own call.
def passes_at(
  cs: List<&2, Call>,
  +self: String,
  arity: Nat,
  at: Maybe<&2, Nat>,
  +v: String
) -> Bool:
  match at:
    case Some{k}:
      passes(cs, self, arity, k, v)
    case None{}:
      False{}

def kept(cs: List<&2, Call>, +self: String, +params: List<&2, String>, +v: String) -> Bool:
  passes_at(cs, self, List.length(&2, String, params), position(params, v, 0n), v)

def walker_of(ws: List<&2, Walker>, +name: String, +arity: Nat) -> Maybe<&2, Walker>:
  match ws:
    case Nil{}:
      None{}
    case Con{Walker{+w, +a, +advice}, rest}:
      Bool.pick(
        Maybe<&2, Walker>,
        Bool.and(String.eq(w, name), Nat.is_eq(a, arity)),
        Some{Walker{w, a, advice}},
        walker_of(rest, name, arity)
      )

def finding(
  hit: Bool,
  +self: String,
  +v: String,
  w: Walker,
  span: Maybe<&2, Lint.Span>
) -> List<&2, Lint.Diag>:
  match hit w:
    case True{} Walker{name, arity, advice}:
      [
        Lint.Diag{
          Lint.Warning{},
          name
            ++ " walks "
            ++ v
            ++ " from its head, and "
            ++ self
            ++ " passes "
            ++ v
            ++ " unchanged to each call of itself: the loop is O(n²). "
            ++ advice,
          span,
          [],
          None{}
        }
      ]
    case False{} _:
      []

def judged(
  +cs: List<&2, Call>,
  +self: String,
  +params: List<&2, String>,
  m: Maybe<&2, Walker>,
  args: List<&2, String>,
  span: Maybe<&2, Lint.Span>
) -> List<&2, Lint.Diag>:
  match m:
    case Some{w}:
      +v = nth(args, 2n)
      finding(kept(cs, self, params, v), self, v, w, span)
    case None{}:
      []

def findings(
  +all: List<&2, Call>,
  cs: List<&2, Call>,
  +self: String,
  +params: List<&2, String>
) -> List<&2, Lint.Diag>:
  match cs:
    case Nil{}:
      []
    case Con{Call{+head, +args, span}, rest}:
      List.append(
        &2,
        Lint.Diag,
        judged(
          all,
          self,
          params,
          walker_of(walkers(), head, List.length(&2, String, args)),
          args,
          span
        ),
        findings(all, rest, self, params)
      )

# Rule
# ====
def in_body(
  +self: String,
  +params: List<&2, String>,
  m: Maybe<&2, Lint.Node>
) -> IO(List<&2, Lint.Diag>):
  match m:
    case None{}:
      IO.pure(List<&2, Lint.Diag>, [])
    case Some{b}:
      do IO<List<&2, Lint.Diag>>:
        ns: List<&2, Lint.Node> <- Lint.nodes(b)
        +cs: List<&2, Call> <- calls(ns, [])
        return List.reverse(&2, Lint.Diag, findings(cs, cs, self, params))

def param_name(
  owner: Maybe<&2, String>,
  kind: Lint.DeclarationKind,
  +o: String,
  +name: String,
  +rest: List<&2, String>
) -> List<&2, String>:
  match owner kind:
    case Some{x} Lint.Parameter{}:
      Bool.pick(List<&2, String>, String.eq(x, o), Con{name, rest}, rest)
    case _ _:
      rest

# The parameters of def `o`, in order.
def params_of(ds: List<&2, Lint.Declaration>, +o: String) -> List<&2, String>:
  match ds:
    case Nil{}:
      []
    case Con{Lint.Declaration{kind, name, owner, span, refs, loads, fills, term}, rest}:
      param_name(owner, kind, o, name, params_of(rest, o))

def check(+all: List<&2, Lint.Declaration>, d: Lint.Declaration) -> IO(List<&2, Lint.Diag>):
  match d:
    case Lint.Declaration{Lint.Definition{}, +name, None{}, span, refs, loads, fills, term}:
      IO.bind(
        Maybe<&2, Lint.Node>,
        List<&2, Lint.Diag>,
        Lint.body(name),
        m => in_body(name, params_of(all, name), m)
      )
    case _:
      IO.pure(List<&2, Lint.Diag>, [])

def checks(
  +all: List<&2, Lint.Declaration>,
  ds: List<&2, Lint.Declaration>,
  acc: List<&2, Lint.Diag>
) -> IO(List<&2, Lint.Diag>):
  match ds:
    case Nil{}:
      IO.pure(List<&2, Lint.Diag>, acc)
    case Con{d, rest}:
      IO.bind(
        List<&2, Lint.Diag>,
        List<&2, Lint.Diag>,
        check(all, d),
        found => checks(all, rest, List.append(&2, Lint.Diag, acc, found))
      )

def id() -> String:
  "performance/list-index-loop"

def facts() -> Lint.Want:
  Lint.NoFacts{}

def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
  IO.bind(
    List<&2, Lint.Declaration>,
    List<&2, Lint.Diag>,
    Lint.declarations(),
    +ds => checks(ds, ds, [])
  )

def main() -> IO(Unit):
  Lint.serve(run)
