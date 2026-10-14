# performance/eager-branch: a value that Bend computes even when it is not needed, and that calls a
# definition of the file that calls itself outside a tail position: a value of `Bool.pick`, or the right
# side of `&&` or `||`. These are functions, so their arguments are computed before they choose; a
# `match` runs only its chosen case.
# Heuristics: measured on the CPU, a Bool.pick whose unused value called a doubly recursive fib took 0.28
# s, against 0.055 s for a match. A loop whose calls of itself are all tail calls is not reported: clang
# drops it when its value is unused (under Bool.pick, a 2G-step loop cost nothing measurable), though the
# JS lane still runs it. A loop's own call in `&&` or `||` is never a tail call. A call of a definition
# that does not call itself, or of Base, is cheap and not reported. A value in a lambda, a type or an
# equation does not run, and is skipped; an erased argument (a proof's) is not told from a live one. A
# loop that is short in practice makes a finding that costs little to ignore.
import Base
import ../../src/linter/lint.bend as Lint
import ../../src/shared/lists.bend as Lists
import ./deep-call-in-fork.bend as Deep

# Types
# =====

# A value Bend computes whether needed or not: what computes it ("pick", "&&" or "||"), and the value.
type Eager is Data:
  Eager{kind: String, value: Maybe<&2, Lint.Node>}

# What judging the calls in one definition reads: the definitions of the file that call themselves outside a tail
# position (as the check names them), and the definition, as the check names it.
type Owner is Data:
  Owner{deeps: List<&2, String>, target: String}

# Functions
# =========
# What an application with the nodes `kids` computes whether needed or not, as its node at `at` is one of its
# arguments: "pick" for a value of Bool.pick, "&&" or "||" for their right side, "" for none.
def eager(kids: List<&2, Lint.Node>, +at: U32) -> String:
  match kids:
    case Con{Lint.Node{Lint.Reference{t}, n, s, k, f}, Con{ty, Con{c, Con{x, Con{y, rest}}}}}:
      Bool.pick(
        String,
        String.eq(t, "Bool.pick") && (U32.is_eq(at, 3) || U32.is_eq(at, 4)),
        "pick",
        ""
      )
    case Con{Lint.Node{Lint.Reference{+t}, n, s, k, f}, Con{left, Con{right, Nil{}}}}:
      Bool.pick(
        String,
        U32.is_eq(at, 2),
        Bool.pick(
          String,
          String.eq(t, "Bool.and"),
          "&&",
          Bool.pick(String, String.eq(t, "Bool.or"), "||", "")
        ),
        ""
      )
    case _:
      ""

def Eager.of(+kind: String, value: Maybe<&2, Lint.Node>) -> Maybe<&2, Eager>:
  Lists.when(Eager, Bool.not(String.eq(kind, "")), Eager{kind, value})

# The eager value a call below `path` is in, if one is above it and no lambda comes between. `found` stops the walk
# once one is found.
def eagerly(path: List<&2, Lint.Above>, found: Maybe<&2, Eager>) -> Maybe<&2, Eager>:
  match path found:
    case _ Some{e}:
      Some{e}
    case Con{Lint.Above{Lint.Node{Lint.Application{}, n, s, +kids, f}, +at}, rest} None{}:
      eagerly(rest, Eager.of(eager(kids, at), List.get(&2, Lint.Node, kids, U32.to_nat(at))))
    case Con{Lint.Above{Lint.Node{Lint.Lambda{b, q}, n, s, k, f}, at}, rest} None{}:
      None{}
    case Con{Lint.Above{Lint.Node{Lint.Body{}, n, s, k, f}, at}, rest} None{}:
      None{}
    case Con{a, rest} None{}:
      eagerly(rest, None{})
    case Nil{} None{}:
      None{}

def why(+kind: String, +callee: String) -> String:
  Bool.pick(
    String,
    String.eq(kind, "pick"),
    "Bool.pick computes both of its values before it picks one, so this call of "
      ++ callee
      ++ " runs even when the condition picks the other value",
    kind
      ++ " computes its right side even when its left side decides the result ("
      ++ Bool.pick(String, String.eq(kind, "&&"), "False", "True")
      ++ "), so this call of "
      ++ callee
      ++ " runs even then"
  )

def message(kind: String, +callee: String, own: Bool) -> String:
  why(
    kind,
    callee
  )
    ++ Bool.pick(
      String,
      own,
      ": it is the loop's own call, so the loop walks to its end instead of stopping where the condition decides",
      ""
    )
    ++ ". CPU and GPU: measured 5x slower than a match, for an unused call that calls itself outside a tail position. JS: computes both values too. Confidence: medium, as the cost is what the unneeded call computes. Choose with a match: pass the condition to a helper whose match runs only the needed value; inside a loop, where that helper would call the loop back (Bend refuses mutual recursion), pass the condition to the next call, and match on it there. If "
    ++ callee
    ++ " runs only a few steps here, expect this finding."

def judged(eager: Maybe<&2, Eager>, callee: String, own: Bool) -> List<&2, Lint.Finding>:
  match eager:
    case Some{Eager{kind, value}}:
      Lint.finding(Lint.Information{}, True{}, Lint.Node.span(value), message(kind, callee, own))
    case None{}:
      []

def looping(
  hit: Bool,
  path: List<&2, Lint.Above>,
  callee: String,
  own: Bool
) -> List<&2, Lint.Finding>:
  match hit:
    case True{}:
      judged(eagerly(path, None{}), callee, own)
    case False{}:
      []

def visit(+owner: Owner, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, Lint.Finding>:
  match owner node:
    case Owner{
      deeps,
      target
    } Lint.Node{
      Lint.Application{},
      n,
      s,
      Con{Lint.Node{Lint.Reference{+called}, callee, rs, rk, rf}, args},
      f
    }:
      looping(
        List.contains(~String, ~String.eq, deeps, called) && Lint.is_live(path),
        path,
        callee,
        String.eq(called, target)
      )
    case _ _:
      []

def defs(
  nodes: List<&2, Lint.Node>,
  +deeps: List<&2, String>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Node{Lint.Definition{+t, u}, n, s, k, f}, rest}:
      defs(
        rest,
        deeps,
        Lists.onto(
          &2,
          Lint.Finding,
          Lint.visit(
            ~Owner,
            ~Lint.Finding,
            ~visit,
            Owner{deeps, t},
            [Lint.Node{Lint.Definition{t, u}, n, s, k, f}]
          ),
          out
        )
      )
    case Con{node, rest}:
      defs(rest, deeps, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +nodes = Lint.Here.nodes(here)
  Lint.done(defs(nodes, Deep.deep(nodes, True{}, []), []))

def rule() -> Lint.Rule:
  Lint.Rule{Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
