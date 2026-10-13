# performance/deep-call-in-fork: a fork that calls a definition that calls itself outside a tail
# position. A value of a parallel let (`a b = f(x) g(y)`), or of a let just before it, calls a
# definition of the file whose call of itself is not the last thing it does.
# Heuristics: Bend gives a call of itself that is not a tail call a frame per call ("bend guide
# shaders"). In bend-lint's benchmark (Bend 2.0.36, 16 threads), such a call at each fork cut the
# speedup from 10x to 1.9x; the same definition with a tail call kept the 10x. A tail position is the
# body of a definition, a case, or the rest of a block after its lets, through annotations.
import Base
import ../../src/linter/lint.bend as Lint
import ../../src/shared/lists.bend as Lists

# Types
# =====

# What judging the calls in one definition reads: the definitions of the file that call themselves outside a tail
# position (as the check names them), and the definition, by the name the check gives it and as written.
type Owner is Data:
  Owner{deeps: List<&2, String>, target: String, name: String}

# Functions
# =========

# Whether `at` is the place of the last of `nodes`.
def last(nodes: List<&2, Lint.Node>, at: U32) -> Bool:
  U32.is_eq((at + 1: U32), U32.from_nat(Lists.length(&2, Lint.Node, nodes)))

# Whether the node below `path` is in a tail position, if it ends the node above it (`ends`): the body of a definition
# or a case, or the rest of a block after its lets, through annotations.
def tail(path: List<&2, Lint.Above>, ends: Bool) -> Bool:
  match path ends:
    case _ False{}:
      False{}
    case Con{Lint.Above{Lint.Node{Lint.Body{}, n, s, k, f}, at}, rest} True{}:
      True{}
    case Con{Lint.Above{Lint.Node{Lint.Case{}, n, s, k, f}, at}, rest} True{}:
      tail(rest, True{})
    case Con{Lint.Above{Lint.Node{Lint.Match{}, n, s, k, f}, at}, rest} True{}:
      tail(rest, True{})
    case Con{Lint.Above{Lint.Node{Lint.Annotation{}, n, s, k, f}, at}, rest} True{}:
      tail(rest, True{})
    case Con{Lint.Above{Lint.Node{Lint.Destructure{q}, n, s, kids, f}, at}, rest} True{}:
      tail(rest, last(kids, at))
    case Con{Lint.Above{Lint.Node{Lint.Let{}, n, s, kids, f}, at}, rest} True{}:
      tail(rest, last(kids, at))
    case _ _:
      False{}

# Whether a call of its definition to itself below `path` is outside a tail position.
def deep.of(recursive: Bool, path: List<&2, Lint.Above>) -> List<&2, Bool>:
  match recursive:
    case True{}:
      [Bool.not(tail(path, True{}))]
    case False{}:
      []

def deep.visit(+u: Unit, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, Bool>:
  deep.of(Lint.recursive(path, node), path)

# The definitions among `nodes` that call themselves outside a tail position, as the check names them, onto `out`.
def deep(nodes: List<&2, Lint.Node>, out: List<&2, String>) -> List<&2, String>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{Lint.Definition{+t, u}, n, s, k, f}, rest}:
      deep(
        rest,
        Lists.push(
          String,
          Lists.when(
            String,
            List.contains(
              ~Bool,
              ~Bool.and,
              Lint.visit(
                ~Unit,
                ~Bool,
                ~deep.visit,
                Unit{},
                [Lint.Node{Lint.Definition{t, u}, n, s, k, f}]
              ),
              True{}
            ),
            t
          ),
          out
        )
      )
    case Con{node, rest}:
      deep(rest, out)

def pattern(syntax: Lint.Syntax) -> Bool:
  match syntax:
    case Lint.PatternVariable{b, q}:
      True{}
    case Lint.PatternConstructor{t}:
      True{}
    case _:
      False{}

def binders(nodes: List<&2, Lint.Node>, n: Nat) -> Nat:
  match nodes:
    case Nil{}:
      n
    case Con{Lint.Node{Lint.PatternVariable{b, q}, nm, s, k, f}, rest}:
      binders(rest, 1n+n)
    case Con{node, rest}:
      binders(rest, n)

# Whether a let leads to a fork: it is one (it binds `many` names), or it binds one (`one`), and the last of `nodes`,
# the rest of its block, is a let that leads to one. The values of these lets are what a fork runs, or what runs just
# before it.
def leads(nodes: List<&2, Lint.Node>, many: Bool, one: Bool) -> Bool:
  match nodes many one:
    case _ True{} _:
      True{}
    case _ False{} False{}:
      False{}
    case Con{Lint.Node{Lint.Destructure{q}, n, s, +kids, f}, Nil{}} False{} True{}:
      +count = binders(kids, 0n)
      leads(kids, Nat.is_gt(count, 1n), Nat.is_eq(count, 1n))
    case Con{x, Nil{}} False{} True{}:
      False{}
    case Con{x, rest} False{} True{}:
      leads(rest, False{}, True{})
    case Nil{} False{} True{}:
      False{}

# Whether `x`, the node at `at` under `parent`, is a value of a fork, or of a let just before one: not a binder, nor the
# rest of the block.
def value(x: Lint.Node, +parent: Lint.Node, at: U32) -> Bool:
  match x parent:
    case Lint.Node{s, n, sp, k, f} Lint.Node{ps, pn, psp, +kids, pf}:
      leads([parent], False{}, Bool.not(pattern(s)) && Bool.not(last(kids, at)))

# Whether `x`, below `path`, or a node above it, is a value of a fork, or `found`.
def inside(path: List<&2, Lint.Above>, x: Lint.Node, found: Bool) -> Bool:
  match path found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{Lint.Above{+p, at}, rest} False{}:
      inside(rest, p, value(x, p, at))

def message(+callee: String, loop: String) -> String:
  callee
    ++ " calls itself outside a tail position: Bend runs such a call with a frame per call (\"bend guide shaders\"). "
    ++ loop
    ++ " calls "
    ++ callee
    ++ " in a fork: a value of its parallel let, or of a let just before it. In bend-lint's benchmark (Bend 2.0.36, 16 threads), one such call per fork cut the speedup from 10x to 1.9x, and a tail-recursive version kept the 10x. Make "
    ++ callee
    ++ " tail-recursive with an accumulator, compute its value with native operations (such as U32.shln), or compute it once and pass it down as a parameter. In the slash boss demo of Bend, doing so for such a call changed no timing: the list it walked was short. Time it before and after."

# The finding about a call of a deep definition (if `deep`), when the call is in a fork.
def judge.deep(
  deep: Bool,
  path: List<&2, Lint.Above>,
  +node: Lint.Node,
  callee: String,
  name: String
) -> List<&2, Lint.Finding>:
  match deep:
    case True{}:
      Lint.finding(
        Lint.Warning{},
        inside(path, node, False{}),
        Lint.Node.span(Some{node}),
        message(callee, name)
      )
    case False{}:
      []

def judge.call(
  +owner: Owner,
  path: List<&2, Lint.Above>,
  node: Lint.Node,
  callee: String,
  +called: String
) -> List<&2, Lint.Finding>:
  match owner:
    case Owner{deeps, target, name}:
      judge.deep(
        List.contains(~String, ~String.eq, deeps, called) && Bool.not(String.eq(called, target)),
        path,
        node,
        callee,
        name
      )

def visit(+owner: Owner, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, Lint.Finding>:
  match node:
    case Lint.Node{
      Lint.Application{},
      n,
      s,
      Con{Lint.Node{Lint.Reference{called}, callee, rs, rk, rf}, args},
      f
    }:
      judge.call(owner, path, node, callee, called)
    case _:
      []

def defs(
  nodes: List<&2, Lint.Node>,
  +deeps: List<&2, String>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Node{Lint.Definition{+t, u}, +n, s, k, f}, rest}:
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
            Owner{deeps, t, n},
            [Lint.Node{Lint.Definition{t, u}, n, s, k, f}]
          ),
          out
        )
      )
    case Con{node, rest}:
      defs(rest, deeps, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +nodes = Lint.Here.nodes(here)
  Lint.done(defs(nodes, deep(nodes, []), []))

def rule() -> Lint.Rule:
  Lint.Rule{Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
