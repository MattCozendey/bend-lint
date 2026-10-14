# language/unneeded_plus: a binder written with `+` that its body uses at most once on each path, so the
# `+` claims a reuse that never happens.
# Heuristics: it reads how often the checker found each binder used, the most over its branches. A
# binder that a match or a let takes apart is skipped: its `+` also makes its fields reusable. So is a
# parameter of a definition used as a value (`OnFile{run}`): the type it must have can ask for the `+`.
# The `+` costs no speed: the compiler counts references from the uses, not from the `+`. Removing
# 1,049 such `+` from Bend's slash boss demo, three-bodies and a raytracer left their C unchanged.
import Base
import ../../src/linter/lint.bend as Lint
import ../../src/shared/lists.bend as Lists

# Types
# =====

# What judging the binders of one definition reads: the definitions of the file used as values (named, not called), as
# the check names them; the definition, as the check names it; and its binders that a match or a let takes apart.
type Owner is Data:
  Owner{values: List<&2, String>, target: String, matched: List<&2, U32>}

# Functions
# =========

# The definition a reference below `path` names, if it is used as a value: not as the function of an application.
def value.visit(+u: Unit, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, String>:
  match path node:
    case Con{
      Lint.Above{Lint.Node{Lint.Application{}, n, s, k, f}, at},
      up
    } Lint.Node{Lint.Reference{t}, rn, rs, rk, rf}:
      Bool.pick(List<&2, String>, U32.is_eq(at, 0), [], [t])
    case _ Lint.Node{Lint.Reference{t}, rn, rs, rk, rf}:
      [t]
    case _ _:
      []

def is_constructed(nodes: List<&2, Lint.Node>) -> Bool:
  match nodes:
    case Con{Lint.Node{Lint.PatternConstructor{t}, n, s, k, f}, rest}:
      True{}
    case _:
      False{}

# The binder a variable below `path` uses, if it is taken apart there: it is a match's scrutinee, or the value of a let
# with a constructor pattern (`Vert{x, y} = v`).
def matched.visit(+u: Unit, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, U32>:
  match path node:
    case Con{
      Lint.Above{Lint.Node{Lint.Match{}, n, s, k, f}, at},
      up
    } Lint.Node{Lint.Variable{b}, vn, vs, vk, vf}:
      [b]
    case Con{
      Lint.Above{Lint.Node{Lint.Destructure{q}, n, s, +kids, f}, +at},
      up
    } Lint.Node{Lint.Variable{b}, vn, vs, vk, vf}:
      Bool.pick(
        List<&2, U32>,
        Bool.not(
          U32.is_eq((at + 1: U32), U32.from_nat(Lists.length(&2, Lint.Node, kids)))
        )
          && is_constructed(kids),
        [b],
        []
      )
    case _ _:
      []

# Whether a binder used `used` times needs no `+`: none or one use.
def is_once(used: Maybe<&2, Lint.Quantity>) -> Bool:
  match used:
    case Some{Lint.Erased{}}:
      True{}
    case Some{Lint.Once{}}:
      True{}
    case _:
      False{}

# The binder a node of this kind declares with `+`, if it does.
def plus(syntax: Lint.Syntax) -> Maybe<&2, U32>:
  match syntax:
    case Lint.Parameter{b, Lint.Many{}}:
      Some{b}
    case Lint.Field{b, Lint.Many{}}:
      Some{b}
    case Lint.Binding{b, Lint.Many{}}:
      Some{b}
    case Lint.Forall{b, Lint.Many{}}:
      Some{b}
    case Lint.Lambda{b, Some{Lint.Many{}}}:
      Some{b}
    case Lint.PatternVariable{b, Lint.Many{}}:
      Some{b}
    case _:
      None{}

def is_parameter(syntax: Lint.Syntax) -> Bool:
  match syntax:
    case Lint.Parameter{b, q}:
      True{}
    case _:
      False{}

def message(+name: String) -> String:
  "+"
    ++ name
    ++ " is used at most once on each path, so it needs no `+`. Write "
    ++ name
    ++ " without it. Speed does not change: Bend counts references from the uses, not from the `+`."

# Whether a `+` binder its body uses at most once (`once`) needs no `+`: not if a match takes it apart, nor if it is a
# parameter of a definition used as a value: the type it must have can ask for the `+`.
def is_needless(once: Bool, parameter: Bool, owner: Owner, b: U32) -> Bool:
  match once parameter owner:
    case True{} True{} Owner{values, target, matched}:
      Bool.not(
        List.contains(~String, ~String.eq, values, target)
      )
        && Bool.not(List.contains(~U32, ~U32.is_eq, matched, b))
    case True{} False{} Owner{values, target, matched}:
      Bool.not(List.contains(~U32, ~U32.is_eq, matched, b))
    case _ _ _:
      False{}

# The findings about a `+` binder (`binder`, if the node declares one) that its facts say its body uses at most once.
def judged(
  binder: Maybe<&2, U32>,
  +parameter: Bool,
  +owner: Owner,
  +span: Maybe<&2, Lint.Span>,
  +name: String,
  facts: List<&2, Lint.Fact>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match binder facts:
    case Some{+b} Con{Lint.Fact{Lint.OfBinder{}, q, used, t}, rest}:
      judged(
        Some{b},
        parameter,
        owner,
        span,
        name,
        rest,
        Lists.onto(
          &2,
          Lint.Finding,
          Lint.finding(
            Lint.Hint{},
            is_needless(is_once(used), parameter, owner, b),
            span,
            message(name)
          ),
          out
        )
      )
    case Some{+b} Con{f, rest}:
      judged(Some{b}, parameter, owner, span, name, rest, out)
    case _ _:
      List.reverse(&2, Lint.Finding, out)

def visit(+owner: Owner, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, Lint.Finding>:
  match node:
    case Lint.Node{+syntax, name, span, k, fs}:
      judged(plus(syntax), is_parameter(syntax), owner, span, name, fs, [])

def defs(
  nodes: List<&2, Lint.Node>,
  +values: List<&2, String>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Node{Lint.Definition{+t, u}, n, s, k, f}, rest}:
      +owner = {Lint.Node{Lint.Definition{t, u}, n, s, k, f}: Lint.Node}
      defs(
        rest,
        values,
        Lists.onto(
          &2,
          Lint.Finding,
          Lint.visit(
            ~Owner,
            ~Lint.Finding,
            ~visit,
            Owner{values, t, Lint.visit(~Unit, ~U32, ~matched.visit, Unit{}, [owner])},
            [owner]
          ),
          out
        )
      )
    case Con{node, rest}:
      defs(rest, values, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +nodes = Lint.Here.nodes(here)
  Lint.done(defs(nodes, Lint.visit(~Unit, ~String, ~value.visit, Unit{}, nodes), []))

def rule() -> Lint.Rule:
  Lint.Rule{Lint.Needs{True{}, False{}}, [], Lint.OnFile{run}}
