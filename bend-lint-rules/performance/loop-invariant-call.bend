# performance/loop-invariant-call: a call that gets the same arguments on every step of a loop, so it
# computes the same value each time: in a definition that calls itself, a call of a definition of the
# file that loops too, in the branch that repeats (the one with the loop's call of itself), whose
# arguments are literals, or parameters that the loop passes unchanged to each call of itself.
# Heuristics: clang hoists plain arithmetic out of a loop (and folds constants), but not a call of a
# definition that loops: Bend runs it through its own calls. Compute it once, before the loop, and pass
# it as a parameter. A definition that does not call itself is cheap, and not reported. A proof (a
# definition that fills a law, or returns an equality) does not run, and is skipped. A loop that repeats
# work on purpose, such as a benchmark's, is the case to expect.
import Base
import ../../src/linter/lint.bend as Lint
import ../../src/shared/lists.bend as Lists

# Types
# =====

# What judging the calls of one definition reads: the definitions of the file that call themselves (as the check
# names them), the definition (as the check names it, and as written), and its parameters that it passes unchanged
# to each call of itself, by binder.
type Owner is Data:
  Owner{loops: List<&2, String>, target: String, name: String, fixed: List<&2, U32>}

# Functions
# =========
def message(callee: String, loop: String) -> String:
  callee
    ++ " gets the same arguments on every step of "
    ++ loop
    ++ ", so it computes the same value each time: clang hoists plain arithmetic out of a loop, but not a call of a definition that loops. Every lane. Confidence: high that it repeats; the gain is what the call costs. Compute it once before the loop, and pass it as a parameter; if the loop repeats it on purpose (a benchmark), expect this finding."

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

# The arguments of each call of the definition below `path` to itself.
def self.visit(
  +u: Unit,
  +path: List<&2, Lint.Above>,
  +node: Lint.Node
) -> List<&2, List<&2, Lint.Node>>:
  match node:
    case Lint.Node{Lint.Application{}, n, s, Con{f, args}, fs}:
      Bool.pick(List<&2, List<&2, Lint.Node>>, Lint.is_recursive(path, node), [args], [])
    case _:
      []

def passed.at(arg: Maybe<&2, Lint.Node>, b: U32) -> Bool:
  match arg:
    case Some{Lint.Node{Lint.Variable{v}, n, s, k, f}}:
      U32.is_eq(v, b)
    case _:
      False{}

# Whether the argument at `at` of each of `calls` is the variable of `b`.
def passed(calls: List<&2, List<&2, Lint.Node>>, +at: Nat, +b: U32, ok: Bool) -> Bool:
  match calls ok:
    case _ False{}:
      False{}
    case Nil{} True{}:
      True{}
    case Con{args, rest} True{}:
      passed(rest, at, b, passed.at(List.get(&2, Lint.Node, args, at), b))

# The runtime parameters among a definition's nodes that it passes unchanged to each of `calls` (its calls of itself),
# by binder; `at` counts the runtime parameters, as the calls' arguments do.
def fixed(
  nodes: List<&2, Lint.Node>,
  +calls: List<&2, List<&2, Lint.Node>>,
  +at: Nat,
  out: List<&2, U32>
) -> List<&2, U32>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{Lint.Parameter{+b, q}, n, s, k, f}, rest}:
      fixed(
        rest,
        calls,
        1n+at,
        Lists.push(U32, Lists.when(U32, passed(calls, at, b, True{}), b), out)
      )
    case Con{node, rest}:
      fixed(rest, calls, at, out)

# Whether `nodes`, the arguments of a call, are the same on every step: literals, the variables of `fixed`, and calls,
# annotations or constructions of those alone; `fuel` bounds the depth.
def invariant(+fuel: Nat, nodes: List<&2, Lint.Node>, +fixed: List<&2, U32>, ok: Bool) -> Bool:
  match fuel nodes ok:
    case _ _ False{}:
      False{}
    case _ Nil{} True{}:
      True{}
    case 0n _ True{}:
      False{}
    case 1n+f Con{Lint.Node{Lint.Literal{t}, n, s, k, fs}, rest} True{}:
      invariant(f, rest, fixed, True{})
    case 1n+f Con{Lint.Node{Lint.Variable{v}, n, s, k, fs}, rest} True{}:
      invariant(f, rest, fixed, List.contains(~U32, ~U32.is_eq, fixed, v))
    case 1n+f Con{Lint.Node{Lint.Application{}, n, s, Con{h, args}, fs}, rest} True{}:
      invariant(f, rest, fixed, invariant(f, args, fixed, True{}))
    case 1n+f Con{Lint.Node{Lint.Annotation{}, n, s, Con{x, ts}, fs}, rest} True{}:
      invariant(f, rest, fixed, invariant(f, [x], fixed, True{}))
    case 1n+f Con{Lint.Node{Lint.Construction{t}, n, s, k, fs}, rest} True{}:
      invariant(f, rest, fixed, invariant(f, k, fixed, True{}))
    case 1n+f Con{x, rest} True{}:
      False{}

# Whether a call of `target` is among `nodes` or under them, or `found`.
def has_call(nodes: List<&2, Lint.Node>, +target: String, found: Bool) -> Bool:
  match nodes found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{
      Lint.Node{
        Lint.Application{},
        n,
        s,
        Con{Lint.Node{Lint.Reference{t}, rn, rs, rk, rf}, args},
        f
      },
      rest
    } False{}:
      has_call(rest, target, has_call(args, target, String.eq(t, target)))
    case Con{Lint.Node{syntax, n, s, kids, f}, rest} False{}:
      has_call(rest, target, has_call(kids, target, False{}))

# The branch a node below `path` is in: the innermost case above it, or the definition's body (the last of `path`).
def branch(path: List<&2, Lint.Above>, last: Maybe<&2, Lint.Node>) -> Maybe<&2, Lint.Node>:
  match path:
    case Nil{}:
      last
    case Con{Lint.Above{Lint.Node{Lint.Case{}, n, s, k, f}, at}, rest}:
      Some{Lint.Node{Lint.Case{}, n, s, k, f}}
    case Con{Lint.Above{p, at}, rest}:
      branch(rest, Some{p})

def repeats(b: Maybe<&2, Lint.Node>, target: String) -> Bool:
  match b:
    case Some{node}:
      has_call([node], target, False{})
    case None{}:
      False{}

def visit(+owner: Owner, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, Lint.Finding>:
  match owner node:
    case Owner{
      loops,
      +target,
      name,
      fixed
    } Lint.Node{
      Lint.Application{},
      n,
      span,
      Con{Lint.Node{Lint.Reference{+t}, callee, rs, rk, rf}, args},
      facts
    }:
      Lint.finding(
        Lint.Information{},
        invariant(
          64n,
          args,
          fixed,
          Bool.not(String.eq(t, target)) && List.contains(~String, ~String.eq, loops, t)
        )
          && Lint.is_live(path)
          && repeats(branch(path, None{}), target),
        span,
        message(callee, name)
      )
    case _ _:
      []

# Whether a definition's nodes say it is a proof: it has no return type written (it fills a law), or it returns an
# equality.
def is_proof(nodes: List<&2, Lint.Node>) -> Bool:
  match nodes:
    case Nil{}:
      True{}
    case Con{
      Lint.Node{Lint.Returns{}, n, s, Con{Lint.Node{Lint.Equality{}, en, es, ek, ef}, k}, f},
      rest
    }:
      True{}
    case Con{Lint.Node{Lint.Returns{}, n, s, k, f}, rest}:
      False{}
    case Con{node, rest}:
      is_proof(rest)

def defs(
  nodes: List<&2, Lint.Node>,
  +loops: List<&2, String>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Node{Lint.Definition{+t, u}, +n, s, +k, f}, rest}:
      +owner = {Lint.Node{Lint.Definition{t, u}, n, s, k, f}: Lint.Node}
      +calls = Lint.visit(~Unit, ~List<&2, Lint.Node>, ~self.visit, Unit{}, [owner])
      defs(
        rest,
        loops,
        Lists.onto(
          &2,
          Lint.Finding,
          Bool.pick(
            List<&2, Lint.Finding>,
            List.is_empty(&2, List<&2, Lint.Node>, calls) || is_proof(k),
            [],
            Lint.visit(
              ~Owner,
              ~Lint.Finding,
              ~visit,
              Owner{loops, t, n, fixed(k, calls, 0n, [])},
              [owner]
            )
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
