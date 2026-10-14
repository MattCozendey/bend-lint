# performance/list-index-loop: a loop that reads a list from its head on each step. A definition passes
# a list parameter unchanged to a call of itself, and, in the same branch, gives it to List.get,
# List.drop, List.take, List.last or List.length, or to a definition of the file that gives its
# parameter to one of those.
# Heuristics: each of those walks the list from its head, so a loop of n steps over a list of n items
# takes O(n²) time, where walking the list takes O(n). A branch is the innermost `case` around the
# read; the loop's call must be in it too. It looks one definition deep, not further. A read in a type
# does not run, and is skipped.
import Base
import ../../src/linter/lint.bend as Lint
import ../../src/shared/lists.bend as Lists
import ../../src/shared/names.bend as Names

# Types
# =====

# A function that walks a list from its head (named as the check names it): which argument is the list,
# and the Base function that walks it.
type Walker is Data:
  Walker{at: Nat, through: String}

# What judging the calls in one definition reads: the walkers of the file, and the definition.
type Loop is Data:
  Loop{walkers: List<&2, Names.Named<Walker>>, owner: Lint.Node}

# Functions
# =========
def bases() -> List<&2, Names.Named<Walker>>:
  [
    Names.Named{"List.get", Walker{2n, "List.get"}},
    Names.Named{"List.drop", Walker{2n, "List.drop"}},
    Names.Named{"List.take", Walker{2n, "List.take"}},
    Names.Named{"List.last", Walker{2n, "List.last"}},
    Names.Named{"List.length", Walker{2n, "List.length"}}
  ]

# The binder of the variable `node` uses, if it is a variable.
def binder(node: Maybe<&2, Lint.Node>) -> Maybe<&2, U32>:
  match node:
    case Some{Lint.Node{Lint.Variable{b}, n, s, k, f}}:
      Some{b}
    case _:
      None{}

def Walker.at(k: Maybe<&2, Nat>, target: String, through: String) -> List<&2, Names.Named<Walker>>:
  match k:
    case Some{at}:
      [Names.Named{target, Walker{at, through}}]
    case None{}:
      []

def Walker.helped(
  walked: Maybe<&2, U32>,
  through: String,
  owner: Lint.Node
) -> List<&2, Names.Named<Walker>>:
  match walked owner:
    case Some{b} Lint.Node{Lint.Definition{t, u}, n, s, kids, f}:
      Walker.at(Lint.parameter(kids, b), t, through)
    case _ _:
      []

# The walker `owner` is, if a call in it of a Base walker (`base`, with `args`) walks one of its parameters.
def Walker.helper(
  base: Maybe<&2, Walker>,
  args: List<&2, Lint.Node>,
  owner: Lint.Node
) -> List<&2, Names.Named<Walker>>:
  match base:
    case Some{Walker{at, through}}:
      Walker.helped(binder(List.get(&2, Lint.Node, args, at)), through, owner)
    case None{}:
      []

def Walker.visit(
  +owner: Lint.Node,
  +path: List<&2, Lint.Above>,
  +node: Lint.Node
) -> List<&2, Names.Named<Walker>>:
  match node:
    case Lint.Node{
      Lint.Application{},
      n,
      s,
      Con{Lint.Node{Lint.Reference{t}, rn, rs, rk, rf}, args},
      f
    }:
      Walker.helper(Names.lookup(Walker, t, bases()), args, owner)
    case _:
      []

# The definitions among `nodes` that give a parameter to a Base walker, as walkers, onto `out`.
def Walker.helpers(
  nodes: List<&2, Lint.Node>,
  out: List<&2, Names.Named<Walker>>
) -> List<&2, Names.Named<Walker>>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{Lint.Definition{t, u}, n, s, k, f}, rest}:
      +owner = {Lint.Node{Lint.Definition{t, u}, n, s, k, f}: Lint.Node}
      Walker.helpers(
        rest,
        Lists.onto(
          &2,
          Names.Named<Walker>,
          Lint.visit(~Lint.Node, ~Names.Named<Walker>, ~Walker.visit, owner, [owner]),
          out
        )
      )
    case Con{node, rest}:
      Walker.helpers(rest, out)

# Whether a variable of the binder `b` is among `args`, or `found`.
def is_passed(args: List<&2, Lint.Node>, +b: U32, found: Bool) -> Bool:
  match args found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{Lint.Node{Lint.Variable{v}, n, s, k, f}, rest} False{}:
      is_passed(rest, b, U32.is_eq(v, b))
    case Con{arg, rest} False{}:
      is_passed(rest, b, False{})

# Whether `args`, the arguments of a call of `target` (if `called`), pass the binder `b` unchanged.
def is_passed.if(called: Bool, args: List<&2, Lint.Node>, b: U32) -> Bool:
  match called:
    case True{}:
      is_passed(args, b, False{})
    case False{}:
      False{}

# Whether a call of `target` among `nodes`, or under them, passes the binder `b` unchanged, or `found`.
def passes(nodes: List<&2, Lint.Node>, +target: String, +b: U32, found: Bool) -> Bool:
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
        Con{Lint.Node{Lint.Reference{t}, rn, rs, rk, rf}, +args},
        f
      },
      rest
    } False{}:
      passes(rest, target, b, passes(args, target, b, is_passed.if(String.eq(t, target), args, b)))
    case Con{Lint.Node{syntax, n, s, kids, f}, rest} False{}:
      passes(rest, target, b, passes(kids, target, b, False{}))

# The innermost case above `path`, if any: a call of the loop must be in it to pass the list on in the same branch.
def innermost(path: List<&2, Lint.Above>, owner: Lint.Node) -> Lint.Node:
  match path:
    case Nil{}:
      owner
    case Con{Lint.Above{Lint.Node{Lint.Case{}, n, s, k, f}, at}, rest}:
      Lint.Node{Lint.Case{}, n, s, k, f}
    case Con{a, rest}:
      innermost(rest, owner)

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
    ++ " unchanged to each call of itself, so a loop that visits each of its n items takes O(n²) time. Every lane. Confidence: high, for a long list. "
    ++ advice(through, list)
    ++ " If the list stays short, expect this finding."

# Whether the loop `owner`, if a parameter of it declares the binder `b` (`param`), passes it unchanged to a call of
# itself (`target`), in the innermost case above `path`.
def loops(
  param: Maybe<&2, Nat>,
  path: List<&2, Lint.Above>,
  owner: Lint.Node,
  target: String,
  b: U32
) -> Bool:
  match param:
    case Some{i}:
      passes([innermost(path, owner)], target, b, False{})
    case None{}:
      False{}

# The finding about a walker's call, below `path`, of the list `arg` with the binder `b` that the loop `owner` passes
# unchanged to a call of itself in the same branch.
def judged.list(
  walked: Maybe<&2, U32>,
  list: String,
  callee: String,
  through: String,
  +owner: Lint.Node,
  +path: List<&2, Lint.Above>,
  span: Maybe<&2, Lint.Span>
) -> List<&2, Lint.Finding>:
  match walked owner:
    case Some{+b} Lint.Node{Lint.Definition{+t, u}, name, s, +kids, f}:
      Lint.finding(
        Lint.Warning{},
        loops(Lint.parameter(kids, b), path, owner, t, b) && Lint.is_live(path),
        span,
        message(callee, through, list, name)
      )
    case _ _:
      []

# The finding about a call of the walker `walker`, with `args`.
def judged(
  walker: Maybe<&2, Walker>,
  +args: List<&2, Lint.Node>,
  callee: String,
  owner: Lint.Node,
  path: List<&2, Lint.Above>,
  span: Maybe<&2, Lint.Span>
) -> List<&2, Lint.Finding>:
  match walker:
    case Some{Walker{+at, through}}:
      judged.list(
        binder(List.get(&2, Lint.Node, args, at)),
        Lint.Node.name(List.get(&2, Lint.Node, args, at)),
        callee,
        through,
        owner,
        path,
        span
      )
    case None{}:
      []

def call(
  recursive: Bool,
  +loop: Loop,
  path: List<&2, Lint.Above>,
  node: Lint.Node
) -> List<&2, Lint.Finding>:
  match recursive loop node:
    case False{} Loop{
      walkers,
      owner
    } Lint.Node{
      Lint.Application{},
      n,
      span,
      Con{Lint.Node{Lint.Reference{t}, callee, rs, rk, rf}, args},
      f
    }:
      judged(Names.lookup(Walker, t, walkers), args, callee, owner, path, span)
    case _ _ _:
      []

def visit(+loop: Loop, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, Lint.Finding>:
  call(Lint.is_recursive(path, node), loop, path, node)

def defs(
  nodes: List<&2, Lint.Node>,
  +walkers: List<&2, Names.Named<Walker>>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Node{Lint.Definition{t, u}, n, s, k, f}, rest}:
      +owner = {Lint.Node{Lint.Definition{t, u}, n, s, k, f}: Lint.Node}
      defs(
        rest,
        walkers,
        Lists.onto(
          &2,
          Lint.Finding,
          Lint.visit(~Loop, ~Lint.Finding, ~visit, Loop{walkers, owner}, [owner]),
          out
        )
      )
    case Con{node, rest}:
      defs(rest, walkers, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +nodes = Lint.Here.nodes(here)
  Lint.done(
    defs(
      nodes,
      Lists.append(
        &2,
        Names.Named<Walker>,
        bases(),
        List.reverse(&2, Names.Named<Walker>, Walker.helpers(nodes, []))
      ),
      []
    )
  )

def rule() -> Lint.Rule:
  Lint.Rule{Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
