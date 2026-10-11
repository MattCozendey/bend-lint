# performance/deep-call-in-fork: a fork that calls a definition that calls itself outside a tail
# position. A value of a parallel let (`a b = f(x) g(y)`), or of a let just before it, calls a
# definition of the file whose call of itself is not the last thing it does.
# Heuristics: Bend gives a call of itself that is not a tail call a frame per call ("bend guide
# shaders"). In bend-lint's benchmark (Bend 2.0.36, 16 threads), such a call at each fork cut the
# speedup from 10x to 1.9x; the same definition with a tail call kept the 10x. A tail position is the
# body of a definition, a case, or the rest of a block after its lets, through annotations.
import Base
import ../../lint.bend as Lint
import ../../shared.bend as Shared

# Functions
# =========

# Whether the node numbered `cur` is in a tail position, given the nodes above it, innermost first.
def tail(above: List<&2, Lint.Node>, ok: Bool, cur: U32, +children: Lint.Children) -> Bool:
  match above ok:
    case _ False{}:
      False{}
    case Con{Lint.Node{i, p, o, Lint.Body{}, n, b, q, s, t}, rest} True{}:
      True{}
    case Con{Lint.Node{+i, p, o, Lint.Case{}, n, b, q, s, t}, rest} True{}:
      tail(rest, True{}, i, children)
    case Con{Lint.Node{+i, p, o, Lint.Match{}, n, b, q, s, t}, rest} True{}:
      tail(rest, True{}, i, children)
    case Con{Lint.Node{+i, p, o, Lint.Annotation{}, n, b, q, s, t}, rest} True{}:
      tail(rest, True{}, i, children)
    case Con{Lint.Node{+i, p, o, Lint.Destructure{}, n, b, q, s, t}, rest} True{}:
      tail(rest, U32.is_eq(Lint.Children.last(children, i), cur), i, children)
    case Con{Lint.Node{+i, p, o, Lint.Let{}, n, b, q, s, t}, rest} True{}:
      tail(rest, U32.is_eq(Lint.Children.last(children, i), cur), i, children)
    case _ True{}:
      False{}

def tail.of(chain: List<&2, Lint.Node>, +children: Lint.Children) -> Bool:
  match chain:
    case Con{Lint.Node{i, p, o, s, n, b, q, sp, t}, above}:
      tail(above, True{}, i, children)
    case Nil{}:
      True{}

def deep.add(
  recursive: Bool,
  node: Lint.Node,
  +here: Lint.Here,
  +children: Lint.Children,
  out: List<&2, String>
) -> List<&2, String>:
  match recursive node:
    case True{} Lint.Node{+id, p, owner, s, n, b, q, sp, t}:
      Shared.push(
        String,
        Shared.when(
          String,
          Bool.not(tail.of(Lint.Here.ancestors(here, id), children)),
          Lint.Node.target(Lint.Here.node(here, owner))
        ),
        out
      )
    case _ _:
      out

# The definitions of the file that call themselves outside a tail position, as the check names them.
def deep(
  nodes: List<&2, Lint.Node>,
  +here: Lint.Here,
  +children: Lint.Children,
  out: List<&2, String>
) -> List<&2, String>:
  match nodes:
    case Nil{}:
      out
    case Con{+node, rest}:
      deep(
        rest,
        here,
        children,
        deep.add(Lint.Here.recursive(here, children, node), node, here, children, out)
      )

def pattern(syntax: Lint.Syntax) -> Bool:
  match syntax:
    case Lint.PatternVariable{}:
      True{}
    case Lint.PatternConstructor{}:
      True{}
    case _:
      False{}

def binders(nodes: List<&2, Lint.Node>, n: Nat) -> Nat:
  match nodes:
    case Nil{}:
      n
    case Con{Lint.Node{i, p, o, Lint.PatternVariable{}, nm, b, q, s, t}, rest}:
      binders(rest, 1n+n)
    case Con{node, rest}:
      binders(rest, n)

# The values of a let whose children are `nodes`: neither its binders nor the rest of its block.
def values(nodes: List<&2, Lint.Node>, out: List<&2, U32>) -> List<&2, U32>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{i, p, o, s, n, b, q, sp, t}, Nil{}}:
      out
    case Con{Lint.Node{i, p, o, s, n, b, q, sp, t}, rest}:
      values(rest, Shared.push(U32, Shared.when(U32, Bool.not(pattern(s)), i), out))

# Whether a let, whose rest of block is the fork or the let after (`rest`), binds one name.
def single(rest: Bool, nodes: List<&2, Lint.Node>) -> Bool:
  match rest:
    case True{}:
      Nat.is_eq(binders(nodes, 0n), 1n)
    case False{}:
      False{}

def values.if(hit: Bool, nodes: List<&2, Lint.Node>) -> List<&2, U32>:
  match hit:
    case True{}:
      values(nodes, [])
    case False{}:
      []

# The values of the lets just before a fork: each let above `cur` whose rest of block it is, while
# the let binds one name. `going` says whether the walk goes on.
def before(
  above: List<&2, Lint.Node>,
  going: Bool,
  cur: U32,
  +children: Lint.Children,
  out: List<&2, U32>
) -> List<&2, U32>:
  match above going:
    case Con{Lint.Node{+i, p, o, Lint.Destructure{}, n, b, q, s, t}, rest} True{}:
      +hit = single(U32.is_eq(Lint.Children.last(children, i), cur), Lint.Children.get(children, i))
      before(
        rest,
        hit,
        i,
        children,
        Shared.onto(&2, U32, values.if(hit, Lint.Children.get(children, i)), out)
      )
    case _ _:
      out

def forks.of(
  fork: Bool,
  +id: U32,
  +here: Lint.Here,
  +children: Lint.Children,
  out: List<&2, U32>
) -> List<&2, U32>:
  match fork:
    case True{}:
      before(
        List.tail(&2, Lint.Node, Lint.Here.ancestors(here, id)),
        True{},
        id,
        children,
        values(Lint.Children.get(children, id), out)
      )
    case False{}:
      out

# The values of the forks of the file (parallel lets), and of the lets just before them, by id.
def forks(
  nodes: List<&2, Lint.Node>,
  +here: Lint.Here,
  +children: Lint.Children,
  out: List<&2, U32>
) -> List<&2, U32>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{+id, p, o, Lint.Destructure{}, n, b, q, s, t}, rest}:
      forks(
        rest,
        here,
        children,
        forks.of(
          Nat.is_gt(binders(Lint.Children.get(children, id), 0n), 1n),
          id,
          here,
          children,
          out
        )
      )
    case Con{node, rest}:
      forks(rest, here, children, out)

# Whether a node of `chain` is a fork value of `values`.
def inside(chain: List<&2, Lint.Node>, hit: Bool, +values: List<&2, U32>) -> Bool:
  match chain hit:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{Lint.Node{i, p, o, s, n, b, q, sp, t}, rest} False{}:
      inside(rest, List.contains(~U32, ~U32.is_eq, values, i), values)

def message(+callee: String, +loop: String) -> String:
  callee
    ++ " calls itself outside a tail position: Bend runs such a call with a frame per call (\"bend guide shaders\"). "
    ++ loop
    ++ " calls "
    ++ callee
    ++ " in a fork: a value of its parallel let, or of a let just before it. In bend-lint's benchmark (Bend 2.0.36, 16 threads), one such call per fork cut the speedup from 10x to 1.9x, and a tail-recursive version kept the 10x. Make "
    ++ callee
    ++ " tail-recursive with an accumulator, compute its value with native operations (such as U32.shln), or compute it once and pass it down as a parameter."

def finding(hit: Bool, span: Maybe<&2, Lint.Span>, text: String) -> List<&2, Lint.Finding>:
  match hit span:
    case True{} Some{s}:
      [Lint.Finding{Lint.Warning{}, s, text, []}]
    case _ _:
      []

# The finding about a call of a deep definition (if `deep`), when the call is in a fork.
def forked(
  deep: Bool,
  +id: U32,
  +owner: U32,
  +callee: String,
  span: Maybe<&2, Lint.Span>,
  +here: Lint.Here,
  +forks: List<&2, U32>
) -> List<&2, Lint.Finding>:
  match deep:
    case True{}:
      finding(
        inside(Lint.Here.ancestors(here, id), False{}, forks),
        span,
        message(callee, Lint.Node.name(Lint.Here.node(here, owner)))
      )
    case False{}:
      []

def judge.call(
  nodes: List<&2, Lint.Node>,
  +id: U32,
  +owner: U32,
  span: Maybe<&2, Lint.Span>,
  +here: Lint.Here,
  +deeps: List<&2, String>,
  +forks: List<&2, U32>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Con{Lint.Node{i, p, o, Lint.Reference{}, +callee, b, q, s, +called}, args}:
      forked(
        List.contains(
          ~String,
          ~String.eq,
          deeps,
          called
        )
          && Bool.not(String.eq(called, Lint.Node.target(Lint.Here.node(here, owner)))),
        id,
        owner,
        callee,
        span,
        here,
        forks
      )
    case _:
      []

def judge(
  node: Lint.Node,
  +here: Lint.Here,
  +children: Lint.Children,
  +deeps: List<&2, String>,
  +forks: List<&2, U32>
) -> List<&2, Lint.Finding>:
  match node:
    case Lint.Node{+id, p, owner, Lint.Application{}, n, b, q, span, t}:
      judge.call(Lint.Children.get(children, id), id, owner, span, here, deeps, forks)
    case _:
      []

def scan(
  nodes: List<&2, Lint.Node>,
  +here: Lint.Here,
  +children: Lint.Children,
  +deeps: List<&2, String>,
  +forks: List<&2, U32>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{node, rest}:
      scan(
        rest,
        here,
        children,
        deeps,
        forks,
        Shared.onto(&2, Lint.Finding, judge(node, here, children, deeps, forks), out)
      )

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +nodes = Lint.Here.nodes(here)
  +children = Lint.Children.of(nodes)
  Lint.done(
    scan(
      nodes,
      here,
      children,
      deep(nodes, here, children, []),
      forks(nodes, here, children, []),
      []
    )
  )

def rule() -> Lint.Rule:
  Lint.Rule{"performance/deep-call-in-fork", Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
