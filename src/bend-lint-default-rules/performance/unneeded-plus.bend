# performance/unneeded-plus: a binder written with `+` that its body uses at most once on each path, so
# the `+` buys nothing: a `+` value carries a reference count at run time.
# Heuristics: it reads how often the checker found each binder used, the most over its branches. A
# binder that a match or a let takes apart is skipped: its `+` also makes its fields reusable. So is a parameter
# of a definition used as a value (`OnFile{run}`): the type it must have can ask for the `+`. "bend
# guide shaders" measured a needless `+` slowing a program from 2.83 s to 3.30 s.
import Base
import ../../linter/lint.bend as Lint
import ../../linter/shared.bend as Shared
import ../../shared/lists.bend as Lists
import ../../shared/names.bend as Names

# Types
# =====

# A binder of a definition: its number, and the definition's id.
type Bound is Data:
  Bound{binder: U32, owner: U32}

# Functions
# =========

# Whether `node` is an application whose function is the node numbered `i`.
def calls(node: Maybe<&2, Lint.Node>, i: U32) -> Bool:
  match node:
    case Some{Lint.Node{id, p, o, Lint.Application{}, n, b, q, s, t}}:
      U32.is_eq((id + 1: U32), i)
    case _:
      False{}

# The id of `used`, a definition, onto `out`.
def value.of(used: Maybe<&2, Lint.Node>, out: List<&2, U32>) -> List<&2, U32>:
  match used:
    case Some{Lint.Node{i, p, o, s, n, b, q, sp, t}}:
      i <> out
    case None{}:
      out

def value.add(
  called: Bool,
  defs: Map<&2, Maybe<&2, Lint.Node>>,
  target: String,
  out: List<&2, U32>
) -> List<&2, U32>:
  match called:
    case True{}:
      out
    case False{}:
      value.of(Names.find(Lint.Node, defs, target), out)

# The definitions of the file used as values: named, not called (`OnFile{run}`), by id.
def values(
  nodes: List<&2, Lint.Node>,
  +defs: Map<&2, Maybe<&2, Lint.Node>>,
  +here: Lint.Here,
  out: List<&2, U32>
) -> List<&2, U32>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{i, p, o, Lint.Reference{}, n, b, q, s, t}, rest}:
      values(rest, defs, here, value.add(calls(Lint.Here.node(here, p), i), defs, t, out))
    case Con{node, rest}:
      values(rest, defs, here, out)

def constructed(nodes: List<&2, Lint.Node>) -> Bool:
  match nodes:
    case Con{Lint.Node{i, p, o, Lint.PatternConstructor{}, n, b, q, s, t}, rest}:
      True{}
    case _:
      False{}

# Whether the variable numbered `id`, under `node`, is taken apart there: `node` is a match, or a let
# with a constructor pattern (`Vert{x, y} = v`) whose rest of block it is not.
def apart(node: Maybe<&2, Lint.Node>, id: U32, +children: Lint.Children) -> Bool:
  match node:
    case Some{Lint.Node{i, p, o, Lint.Match{}, n, b, q, s, t}}:
      True{}
    case Some{Lint.Node{+i, p, o, Lint.Destructure{}, n, b, q, s, t}}:
      U32.is_ne(Lint.Children.last(children, i), id) && constructed(Lint.Children.get(children, i))
    case _:
      False{}

# The binders taken apart: a match's scrutinees (the variables right under it), and a let's value (a
# variable under it that is not the rest of its block).
def matched(
  nodes: List<&2, Lint.Node>,
  +here: Lint.Here,
  +children: Lint.Children,
  out: List<&2, Bound>
) -> List<&2, Bound>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{i, p, o, Lint.Variable{}, n, Some{b}, q, s, t}, rest}:
      matched(
        rest,
        here,
        children,
        Lists.push(
          Bound,
          Lists.when(Bound, apart(Lint.Here.node(here, p), i, children), Bound{b, o}),
          out
        )
      )
    case Con{node, rest}:
      matched(rest, here, children, out)

def Bound.has(bounds: List<&2, Bound>, hit: Bool, +binder: U32, +owner: U32) -> Bool:
  match bounds hit:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{Bound{b, o}, rest} False{}:
      Bound.has(rest, U32.is_eq(b, binder) && U32.is_eq(o, owner), binder, owner)

# Whether a binder used `used` times needs no `+`: none or one use.
def once(used: Maybe<&2, Lint.Quantity>) -> Bool:
  match used:
    case Some{Lint.Erased{}}:
      True{}
    case Some{Lint.Once{}}:
      True{}
    case _:
      False{}

# Whether a binder is a parameter of a definition used as a value.
def typed(syntax: Lint.Syntax, owner: U32, values: List<&2, U32>) -> Bool:
  match syntax:
    case Lint.Parameter{}:
      List.contains(~U32, ~U32.is_eq, values, owner)
    case _:
      False{}

def message(+name: String) -> String:
  "+"
    ++ name
    ++ " is used at most once on each path, so it needs no `+`. A `+` value carries a reference count at run time, and \"bend guide shaders\" measured a needless `+` slowing a program from 2.83 s to 3.30 s. Write "
    ++ name
    ++ " without the `+`. In the slash boss demo of Bend, removing 503 such + changed no timing: it matters most for a value that many lanes share."

# The finding about a binder that needs no `+` (if `hit`), unless a match takes it apart.
def unmatched(
  hit: Bool,
  b: U32,
  o: U32,
  matched: List<&2, Bound>,
  span: Maybe<&2, Lint.Span>,
  name: String
) -> List<&2, Lint.Finding>:
  match hit:
    case True{}:
      Shared.finding(
        Lint.Information{},
        Bool.not(Bound.has(matched, False{}, b, o)),
        span,
        message(name)
      )
    case False{}:
      []

def scan(
  facts: List<&2, Lint.Fact>,
  +values: List<&2, U32>,
  +matched: List<&2, Bound>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match facts:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{
      Lint.Fact{
        Lint.Node{i, p, +o, syntax, name, Some{b}, Some{Lint.Many{}}, span, t},
        Lint.OfBinder{},
        q,
        used,
        c
      },
      rest
    }:
      scan(
        rest,
        values,
        matched,
        Lists.onto(
          &2,
          Lint.Finding,
          unmatched(once(used) && Bool.not(typed(syntax, o, values)), b, o, matched, span, name),
          out
        )
      )
    case Con{fact, rest}:
      scan(rest, values, matched, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +nodes = Lint.Here.nodes(here)
  Lint.done(
    scan(
      Lint.Here.facts(here),
      values(nodes, Shared.definitions(nodes), here, []),
      matched(nodes, here, Lint.Children.of(nodes), []),
      []
    )
  )

def rule() -> Lint.Rule:
  Lint.Rule{"performance/unneeded-plus", Lint.Needs{True{}, False{}}, [], Lint.OnFile{run}}
