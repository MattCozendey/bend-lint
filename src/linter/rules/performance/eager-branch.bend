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
import ../../../shared/utils.bend as Utils
import ../../lint.bend as Lint
import ../../shared/utils.bend as LintUtils

# Types
# =====

# A value Bend computes whether needed or not: what computes it ("pick", "&&" or "||"), and its id.
type Eager is Data:
  Eager{kind: String, value: U32}

# Functions
# =========

# The definitions of the file that call themselves, as the check names them.
def loops(
  nodes: List<&2, Lint.Node>,
  +here: Lint.Here,
  +children: Lint.Children,
  out: List<&2, String>
) -> List<&2, String>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{i, p, +o, s, n, b, q, sp, t}, rest}:
      loops(
        rest,
        here,
        children,
        Utils.push(
          String,
          Utils.when(
            String,
            Lint.Here.recursive(here, children, Lint.Node{i, p, o, s, n, b, q, sp, t}),
            Lint.Node.target(Lint.Here.node(here, o))
          ),
          out
        )
      )

# What an application whose children are `nodes` computes whether needed or not, as `value` is one of
# its arguments: "pick" for a value of Bool.pick, "&&" or "||" for their right side, "" for none.
def eager(nodes: List<&2, Lint.Node>, +value: U32) -> String:
  match nodes:
    case Con{
      Lint.Node{i, p, o, Lint.Reference{}, n, b, q, s, t},
      Con{
        ty,
        Con{
          c,
          Con{
            Lint.Node{x, xp, xo, xs, xn, xb, xq, xsp, xt},
            Con{Lint.Node{y, yp, yo, ys, yn, yb, yq, ysp, yt}, rest}
          }
        }
      }
    }:
      Bool.pick(
        String,
        String.eq(t, "Bool.pick") && (U32.is_eq(value, x) || U32.is_eq(value, y)),
        "pick",
        ""
      )
    case Con{
      Lint.Node{i, p, o, Lint.Reference{}, n, b, q, s, +t},
      Con{left, Con{Lint.Node{r, rp, ro, rs, rn, rb, rq, rsp, rt}, Nil{}}}
    }:
      Bool.pick(
        String,
        U32.is_eq(value, r),
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

def Eager.of(+kind: String, value: U32) -> Maybe<&2, Eager>:
  Utils.when(Eager, Bool.not(String.eq(kind, "")), Eager{kind, value})

# The eager value a call, the node before `chain` (numbered `prev`), is in, if one is above it and no
# lambda comes between. `found` stops the walk once one is found.
def eagerly(
  chain: List<&2, Lint.Node>,
  found: Maybe<&2, Eager>,
  +prev: U32,
  +children: Lint.Children
) -> Maybe<&2, Eager>:
  match chain found:
    case _ Some{e}:
      Some{e}
    case Con{Lint.Node{+i, p, o, Lint.Application{}, n, b, q, s, t}, rest} None{}:
      eagerly(rest, Eager.of(eager(Lint.Children.get(children, i), prev), prev), i, children)
    case Con{Lint.Node{i, p, o, Lint.Lambda{}, n, b, q, s, t}, rest} None{}:
      None{}
    case Con{Lint.Node{i, p, o, Lint.Body{}, n, b, q, s, t}, rest} None{}:
      None{}
    case Con{Lint.Node{i, p, o, s, n, b, q, sp, t}, rest} None{}:
      eagerly(rest, None{}, i, children)
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

def judged(
  eager: Maybe<&2, Eager>,
  callee: String,
  own: Bool,
  here: Lint.Here
) -> List<&2, Lint.Finding>:
  match eager:
    case Some{Eager{kind, v}}:
      LintUtils.finding(
        Lint.Information{},
        True{},
        Lint.Node.span(Lint.Here.node(here, v)),
        message(kind, callee, own)
      )
    case None{}:
      []

def looping(
  hit: Bool,
  +id: U32,
  callee: String,
  own: Bool,
  +here: Lint.Here,
  children: Lint.Children
) -> List<&2, Lint.Finding>:
  match hit:
    case True{}:
      judged(
        eagerly(List.tail(&2, Lint.Node, Lint.Here.ancestors(here, id)), None{}, id, children),
        callee,
        own,
        here
      )
    case False{}:
      []

def call(
  nodes: List<&2, Lint.Node>,
  id: U32,
  owner: U32,
  loops: List<&2, String>,
  +here: Lint.Here,
  children: Lint.Children
) -> List<&2, Lint.Finding>:
  match nodes:
    case Con{Lint.Node{i, p, o, Lint.Reference{}, callee, b, q, s, +target}, args}:
      looping(
        List.contains(~String, ~String.eq, loops, target),
        id,
        callee,
        String.eq(target, Lint.Node.target(Lint.Here.node(here, owner))),
        here,
        children
      )
    case _:
      []

def scan(
  nodes: List<&2, Lint.Node>,
  +loops: List<&2, String>,
  +here: Lint.Here,
  +children: Lint.Children,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Node{+i, p, o, Lint.Application{}, n, b, q, s, t}, rest}:
      scan(
        rest,
        loops,
        here,
        children,
        Utils.onto(
          &2,
          Lint.Finding,
          call(Lint.Children.get(children, i), i, o, loops, here, children),
          out
        )
      )
    case Con{node, rest}:
      scan(rest, loops, here, children, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +nodes = Lint.Here.nodes(here)
  +children = Lint.Children.of(nodes)
  Lint.done(scan(nodes, loops(nodes, here, children, []), here, children, []))

def rule() -> Lint.Rule:
  Lint.Rule{"performance/eager-branch", Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
