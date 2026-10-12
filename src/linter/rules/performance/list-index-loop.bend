# performance/list-index-loop: a loop that reads a list from its head on each step. A definition passes
# a list parameter unchanged to a call of itself, and, in the same branch, gives it to List.get,
# List.drop, List.take, List.last or List.length, or to a definition of the file that gives its
# parameter to one of those.
# Heuristics: each of those walks the list from its head, so a loop of n steps over a list of n items
# takes O(n²) time, where walking the list takes O(n). A branch is the innermost `case` around the
# read; the loop's call must be in it too. It looks one definition deep, not further.
import Base
import ../../../shared/utils.bend as Utils
import ../../lint.bend as Lint
import ../../shared/utils.bend as LintUtils

# Types
# =====

# A function that walks a list from its head (named as the check names it): which argument is the list,
# and the Base function that walks it.
type Walker is Data:
  Walker{at: Nat, through: String}

# A call of the definition `owner` to itself passes its parameter `binder` unchanged, inside the cases
# `cases` (innermost first).
type Pass is Data:
  Pass{owner: U32, binder: U32, cases: List<&2, U32>}

# Functions
# =========
def bases() -> List<&2, Utils.Named<Walker>>:
  [
    Utils.Named{"List.get", Walker{2n, "List.get"}},
    Utils.Named{"List.drop", Walker{2n, "List.drop"}},
    Utils.Named{"List.take", Walker{2n, "List.take"}},
    Utils.Named{"List.last", Walker{2n, "List.last"}},
    Utils.Named{"List.length", Walker{2n, "List.length"}}
  ]

# The binder of the variable `node` uses, if it is a variable.
def binder(node: Maybe<&2, Lint.Node>) -> Maybe<&2, U32>:
  match node:
    case Some{Lint.Node{i, p, o, Lint.Variable{}, n, b, q, s, t}}:
      b
    case _:
      None{}

def case_ids(nodes: List<&2, Lint.Node>, out: List<&2, U32>) -> List<&2, U32>:
  match nodes:
    case Nil{}:
      List.reverse(&2, U32, out)
    case Con{Lint.Node{id, p, o, Lint.Case{}, n, b, q, s, t}, rest}:
      case_ids(rest, id <> out)
    case Con{node, rest}:
      case_ids(rest, out)

# The cases around the node numbered `id`, innermost first.
def cases.of(here: Lint.Here, id: U32) -> List<&2, U32>:
  case_ids(Lint.Here.ancestors(here, id), [])

# The innermost of the cases `cs`, or 0 for none.
def innermost(cs: List<&2, U32>) -> U32:
  match cs:
    case Con{c, rest}:
      c
    case Nil{}:
      0

# The passes of a call of the loop `owner`: one per argument that is a parameter of `owner`.
def passes(
  args: List<&2, Lint.Node>,
  +owner: U32,
  +params: List<&2, Lint.Node>,
  +cases: List<&2, U32>,
  out: List<&2, Pass>
) -> List<&2, Pass>:
  match args:
    case Nil{}:
      out
    case Con{Lint.Node{i, p, o, Lint.Variable{}, n, Some{+b}, q, s, t}, rest}:
      passes(
        rest,
        owner,
        params,
        cases,
        Utils.push(
          Pass,
          Utils.when(
            Pass,
            Maybe.is_some(&2, Nat, LintUtils.parameter(params, b)),
            Pass{owner, b, cases}
          ),
          out
        )
      )
    case Con{arg, rest}:
      passes(rest, owner, params, cases, out)

# The passes of the node `node`, if it is a call of the loop it is in.
def Pass.of(
  recursive: Bool,
  node: Lint.Node,
  here: Lint.Here,
  +children: Lint.Children,
  out: List<&2, Pass>
) -> List<&2, Pass>:
  match recursive node:
    case True{} Lint.Node{+id, p, +owner, s, n, b, q, sp, t}:
      passes(
        List.tail(&2, Lint.Node, Lint.Children.get(children, id)),
        owner,
        Lint.Children.get(children, owner),
        cases.of(here, id),
        out
      )
    case _ _:
      out

def Walker.at(
  k: Maybe<&2, Nat>,
  target: String,
  through: String,
  out: List<&2, Utils.Named<Walker>>
) -> List<&2, Utils.Named<Walker>>:
  match k:
    case Some{at}:
      Utils.Named{target, Walker{at, through}} <> out
    case None{}:
      out

def Walker.helped(
  walked: Maybe<&2, U32>,
  through: String,
  +owner: U32,
  here: Lint.Here,
  children: Lint.Children,
  out: List<&2, Utils.Named<Walker>>
) -> List<&2, Utils.Named<Walker>>:
  match walked:
    case Some{b}:
      Walker.at(
        LintUtils.parameter(Lint.Children.get(children, owner), b),
        Lint.Node.target(Lint.Here.node(here, owner)),
        through,
        out
      )
    case None{}:
      out

# The walker the definition `owner` is, if its call `call`, of a Base walker, walks one of its
# parameters.
def Walker.helper(
  base: Maybe<&2, Walker>,
  args: List<&2, Lint.Node>,
  owner: U32,
  here: Lint.Here,
  children: Lint.Children,
  out: List<&2, Utils.Named<Walker>>
) -> List<&2, Utils.Named<Walker>>:
  match base:
    case Some{Walker{at, through}}:
      Walker.helped(binder(List.get(&2, Lint.Node, args, at)), through, owner, here, children, out)
    case None{}:
      out

def Walker.call(
  nodes: List<&2, Lint.Node>,
  owner: U32,
  here: Lint.Here,
  children: Lint.Children,
  out: List<&2, Utils.Named<Walker>>
) -> List<&2, Utils.Named<Walker>>:
  match nodes:
    case Con{Lint.Node{i, p, o, Lint.Reference{}, n, b, q, s, target}, args}:
      Walker.helper(Utils.lookup(Walker, target, bases()), args, owner, here, children, out)
    case _:
      out

# The definitions of the file that give a parameter to a Base walker, as walkers.
def Walker.helpers(
  nodes: List<&2, Lint.Node>,
  +here: Lint.Here,
  +children: Lint.Children,
  out: List<&2, Utils.Named<Walker>>
) -> List<&2, Utils.Named<Walker>>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{id, p, owner, Lint.Application{}, n, b, q, s, t}, rest}:
      Walker.helpers(
        rest,
        here,
        children,
        Walker.call(Lint.Children.get(children, id), owner, here, children, out)
      )
    case Con{node, rest}:
      Walker.helpers(rest, here, children, out)

def Pass.all(
  nodes: List<&2, Lint.Node>,
  +here: Lint.Here,
  +children: Lint.Children,
  out: List<&2, Pass>
) -> List<&2, Pass>:
  match nodes:
    case Nil{}:
      out
    case Con{+node, rest}:
      Pass.all(
        rest,
        here,
        children,
        Pass.of(Lint.Here.recursive(here, children, node), node, here, children, out)
      )

# Whether a pass of `passes` passes `binder` of `owner` unchanged in a call inside the case `inner`
# (0: anywhere).
def Pass.covers(passes: List<&2, Pass>, hit: Bool, +owner: U32, +binder: U32, +inner: U32) -> Bool:
  match passes hit:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{Pass{o, b, cs}, rest} False{}:
      Pass.covers(
        rest,
        U32.is_eq(
          o,
          owner
        )
          && U32.is_eq(b, binder)
          && (U32.is_eq(inner, 0) || List.contains(~U32, ~U32.is_eq, cs, inner)),
        owner,
        binder,
        inner
      )

def advice(through: String, list: String) -> String:
  Bool.pick(
    String,
    String.eq(through, "List.length"),
    "Compute the length once before the loop, and pass it as a parameter.",
    "Walk " ++ list ++ " instead: match it, use its head, and pass its tail to the next call."
  )

def message(+callee: String, +through: String, +list: String, loop: String) -> String:
  callee
    ++ " walks "
    ++ list
    ++ " from its head"
    ++ Bool.pick(String, String.eq(callee, through), "", " (through " ++ through ++ ")")
    ++ ", and "
    ++ loop
    ++ " passes "
    ++ list
    ++ " unchanged to each call of itself, so a loop that visits each of its n items takes O(n²) time. "
    ++ advice(through, list)

def judged.list(
  walked: Maybe<&2, U32>,
  list: String,
  callee: String,
  through: String,
  +owner: U32,
  id: U32,
  span: Maybe<&2, Lint.Span>,
  +here: Lint.Here,
  passes: List<&2, Pass>
) -> List<&2, Lint.Finding>:
  match walked:
    case Some{b}:
      LintUtils.finding(
        Lint.Warning{},
        Pass.covers(passes, False{}, owner, b, innermost(cases.of(here, id))),
        span,
        message(callee, through, list, Lint.Node.name(Lint.Here.node(here, owner)))
      )
    case None{}:
      []

# The finding about a call of the walker `walker`, with `args`, in the definition `owner`.
def judged(
  walker: Maybe<&2, Walker>,
  +args: List<&2, Lint.Node>,
  callee: String,
  owner: U32,
  id: U32,
  span: Maybe<&2, Lint.Span>,
  here: Lint.Here,
  passes: List<&2, Pass>
) -> List<&2, Lint.Finding>:
  match walker:
    case Some{Walker{+at, through}}:
      judged.list(
        binder(List.get(&2, Lint.Node, args, at)),
        Lint.Node.name(List.get(&2, Lint.Node, args, at)),
        callee,
        through,
        owner,
        id,
        span,
        here,
        passes
      )
    case None{}:
      []

def judge(
  nodes: List<&2, Lint.Node>,
  walkers: List<&2, Utils.Named<Walker>>,
  callee: String,
  owner: U32,
  id: U32,
  span: Maybe<&2, Lint.Span>,
  here: Lint.Here,
  passes: List<&2, Pass>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Con{Lint.Node{i, p, o, Lint.Reference{}, n, b, q, s, target}, args}:
      judged(Utils.lookup(Walker, target, walkers), args, callee, owner, id, span, here, passes)
    case _:
      []

# The callee's name, as written.
def callee(nodes: List<&2, Lint.Node>) -> String:
  match nodes:
    case Con{Lint.Node{i, p, o, s, n, b, q, sp, t}, rest}:
      n
    case Nil{}:
      ""

def visit(
  recursive: Bool,
  node: Lint.Node,
  walkers: List<&2, Utils.Named<Walker>>,
  here: Lint.Here,
  +children: Lint.Children,
  passes: List<&2, Pass>
) -> List<&2, Lint.Finding>:
  match recursive node:
    case False{} Lint.Node{+id, p, owner, Lint.Application{}, n, b, q, span, t}:
      judge(
        Lint.Children.get(children, id),
        walkers,
        callee(Lint.Children.get(children, id)),
        owner,
        id,
        span,
        here,
        passes
      )
    case _ _:
      []

def scan(
  nodes: List<&2, Lint.Node>,
  +walkers: List<&2, Utils.Named<Walker>>,
  +here: Lint.Here,
  +children: Lint.Children,
  +passes: List<&2, Pass>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{+node, rest}:
      scan(
        rest,
        walkers,
        here,
        children,
        passes,
        Utils.onto(
          &2,
          Lint.Finding,
          visit(Lint.Here.recursive(here, children, node), node, walkers, here, children, passes),
          out
        )
      )

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +nodes = Lint.Here.nodes(here)
  +children = Lint.Children.of(nodes)
  Lint.done(
    scan(
      nodes,
      Utils.append(&2, Utils.Named<Walker>, bases(), Walker.helpers(nodes, here, children, [])),
      here,
      children,
      Pass.all(nodes, here, children, []),
      []
    )
  )

def rule() -> Lint.Rule:
  Lint.Rule{"performance/list-index-loop", Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
