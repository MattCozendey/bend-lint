# performance/eager-branch: a value that Bend computes even when it is not needed, and that calls a
# definition of the file that loops: a value of `Bool.pick`, or the right side of `&&` or `||`. These
# are functions, so their arguments are computed before they choose; a `match` runs only its chosen
# case.
# Heuristics: measured on the C lane (Bend 2.0.36), a Bool.pick whose unused value ran a 300M-step loop
# took 0.63 s, against 0.26 s for a match, and `False && loop` took 0.71 s. It reports a call of a
# definition that calls itself, as a loop may do much work; a call of a definition that does not, or
# of Base, is cheap and not reported. A loop that is short in practice makes a finding that costs
# little to ignore. A value inside a lambda is not run, and is skipped.
import Base
import ../../src/linter/lint.bend as Lint
import ../../src/shared/lists.bend as Lists

# Types
# =====

# A value Bend computes whether needed or not: what computes it ("pick", "&&" or "||"), and the value.
type Eager is Data:
  Eager{kind: String, value: Maybe<&2, Lint.Node>}

# What judging the calls in one definition reads: the definitions of the file that call themselves (as the check names
# them), and the definition, as the check names it.
type Owner is Data:
  Owner{loops: List<&2, String>, target: String}

# Functions
# =========
def loop.visit(+u: Unit, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, Unit>:
  Bool.pick(List<&2, Unit>, Lint.is_recursive(path, node), [Unit{}], [])

# The definitions among `nodes` that call themselves, as the check names them, onto `out`.
def loops(nodes: List<&2, Lint.Node>, out: List<&2, String>) -> List<&2, String>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{Lint.Definition{+t, u}, n, s, k, f}, rest}:
      loops(
        rest,
        Lists.push(
          String,
          Lists.when(
            String,
            Bool.not(
              List.is_empty(
                &2,
                Unit,
                Lint.visit(
                  ~Unit,
                  ~Unit,
                  ~loop.visit,
                  Unit{},
                  [Lint.Node{Lint.Definition{t, u}, n, s, k, f}]
                )
              )
            ),
            t
          ),
          out
        )
      )
    case Con{node, rest}:
      loops(rest, out)

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
    ++ ". Measured on the C lane, a Bool.pick whose unused value ran a 300M-step loop took 0.63 s, against 0.26 s for a match. Choose with a match instead: pass the condition to a helper whose match runs only the needed value. Inside a loop, where such a helper would call the loop back (Bend refuses mutual recursion), pass the condition to the next call as a parameter, and match on it there. If "
    ++ callee
    ++ " loops only a few steps here, ignore this."

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
      loops,
      target
    } Lint.Node{
      Lint.Application{},
      n,
      s,
      Con{Lint.Node{Lint.Reference{+called}, callee, rs, rk, rf}, args},
      f
    }:
      looping(
        List.contains(~String, ~String.eq, loops, called),
        path,
        callee,
        String.eq(called, target)
      )
    case _ _:
      []

def defs(
  nodes: List<&2, Lint.Node>,
  +loops: List<&2, String>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Node{Lint.Definition{+t, u}, n, s, k, f}, rest}:
      defs(
        rest,
        loops,
        Lists.onto(
          &2,
          Lint.Finding,
          Lint.visit(
            ~Owner,
            ~Lint.Finding,
            ~visit,
            Owner{loops, t},
            [Lint.Node{Lint.Definition{t, u}, n, s, k, f}]
          ),
          out
        )
      )
    case Con{node, rest}:
      defs(rest, loops, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +nodes = Lint.Here.nodes(here)
  Lint.done(defs(nodes, loops(nodes, []), []))

def rule() -> Lint.Rule:
  Lint.Rule{Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
