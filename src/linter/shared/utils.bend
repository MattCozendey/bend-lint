# Bend helpers that more than one rule uses.
import Base
import ../../shared/utils.bend as Utils
import ../lint.bend as Lint

# Types
# =====

# A variable: its binder, and where it starts.
type Use is Data:
  Use{binder: U32, at: U32}

# Functions
# =========

# A finding at `span`, if `hit` and `span` is known.
def finding(
  severity: Lint.Severity,
  hit: Bool,
  span: Maybe<&2, Lint.Span>,
  text: String
) -> List<&2, Lint.Finding>:
  match hit span:
    case True{} Some{s}:
      [Lint.Finding{severity, s, text, []}]
    case _ _:
      []

def definitions.go(
  nodes: List<&2, Lint.Node>,
  out: Map<&2, Maybe<&2, Lint.Node>>
) -> Map<&2, Maybe<&2, Lint.Node>>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{i, p, o, Lint.Definition{}, n, b, q, s, +t}, rest}:
      definitions.go(
        rest,
        Map.set(
          &2,
          Maybe<&2, Lint.Node>,
          out,
          t,
          Some{Lint.Node{i, p, o, Lint.Definition{}, n, b, q, s, t}}
        )
      )
    case Con{node, rest}:
      definitions.go(rest, out)

# The definitions of `nodes`, by the name the check gives them: read one with `Utils.find`. Of two with one name, the
# later is kept.
def definitions(nodes: List<&2, Lint.Node>) -> Map<&2, Maybe<&2, Lint.Node>>:
  definitions.go(nodes, Map.new(&2, Maybe<&2, Lint.Node>))

def parameter.go(
  nodes: List<&2, Lint.Node>,
  found: Maybe<&2, Nat>,
  +binder: U32,
  +k: Nat
) -> Maybe<&2, Nat>:
  match nodes found:
    case _ Some{at}:
      Some{at}
    case Nil{} None{}:
      None{}
    case Con{Lint.Node{i, p, o, Lint.Parameter{}, n, Some{b}, q, s, t}, rest} None{}:
      parameter.go(rest, Utils.when(Nat, U32.is_eq(b, binder), k), binder, 1n+k)
    case Con{node, rest} None{}:
      parameter.go(rest, None{}, binder, k)

# Where the parameter that declares `binder` is among `nodes`, a definition's children, counting from 0.
def parameter(nodes: List<&2, Lint.Node>, binder: U32) -> Maybe<&2, Nat>:
  parameter.go(nodes, None{}, binder, 0n)

# The variables of `nodes`, last first, onto `out`.
def Use.all(nodes: List<&2, Lint.Node>, out: List<&2, Use>) -> List<&2, Use>:
  match nodes:
    case Nil{}:
      out
    case Con{
      Lint.Node{i, p, o, Lint.Variable{}, n, Some{b}, q, Some{Lint.Span{path, beg, end}}, t},
      rest
    }:
      Use.all(rest, Use{b, beg} <> out)
    case Con{node, rest}:
      Use.all(rest, out)
