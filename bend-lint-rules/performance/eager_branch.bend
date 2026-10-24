# performance/eager_branch: a value that Bend computes even when it is not needed, and that runs a loop
# of the program to its end: a value of `Bool.pick`, or the right side of `&&` or `||`. These are
# functions, so their arguments are computed before they choose; a `match` runs only its chosen case.
# Heuristics: measured on the CPU, a Bool.pick whose unused value called a doubly recursive fib took 0.28
# s, against 0.055 s for a match. clang drops an unused loop that compiles to one native loop: under
# Bool.pick, a 2G-step tail loop cost nothing measurable, and under `&&`, a 400M-step one; the JS lane
# still runs it. A tail loop that called Base's List.contains, which applies a closure, at each step did
# not drop: 0.86 s for 40M steps, against 0.09 s for a match. So a call is reported when it is of a loop
# that calls itself outside a tail position, or of one under which a parallel let, a closure's
# application (not a `~` parameter's) or such a loop runs, or of a definition that calls such a loop,
# through the program's files. A loop's own call in `&&` or `||` is never a tail call. Base's
# definitions are not seen: a call of one counts as one native loop, so a loop slow only through Base is
# not reported. A call under a lambda counts, though it runs only when the lambda does. A value in a
# lambda, a type or an equation does not run, and is skipped; an erased argument (a proof's) is not told
# from a live one. A loop that is short in practice makes a finding that costs little to ignore.
import Base
import ../../src/linter/lint.bend as Lint
import ../../src/shared/lists.bend as Lists
import ../../src/shared/names.bend as Names
import ../../src/shared/sets.bend as Sets
import ./deep_call_in_fork.bend as Deep

# Types
# =====

# A value Bend computes whether needed or not: what computes it ("pick", "&&" or "||"), and the value.
type Eager is Data:
  Eager{kind: String, value: Maybe<&2, Lint.Node>}

# What judging the calls in one definition reads: the definitions of the program a call of which runs a loop to its end
# (see costly), and the definition, as the check names them.
type Owner is Data:
  Owner{costly: Set(), target: String}

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
      costly,
      target
    } Lint.Node{
      Lint.Application{},
      n,
      s,
      Con{Lint.Node{Lint.Reference{+called}, callee, rs, rk, rf}, args},
      f
    }:
      looping(
        Sets.has(costly, called) && Lint.is_live(path),
        path,
        callee,
        String.eq(called, target)
      )
    case _ _:
      []

def defs(
  nodes: List<&2, Lint.Node>,
  +costly: Set(),
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Node{Lint.Definition{+t, u}, n, s, k, f}, rest}:
      defs(
        rest,
        costly,
        Lists.onto(
          &2,
          Lint.Finding,
          Lint.visit(
            ~Owner,
            ~Lint.Finding,
            ~visit,
            Owner{costly, t},
            [Lint.Node{Lint.Definition{t, u}, n, s, k, f}]
          ),
          out
        )
      )
    case Con{node, rest}:
      defs(rest, costly, out)

# The binders of the `~` parameters among a definition's nodes, onto `out`: a call of one is inlined, not a closure's.
def templates(nodes: List<&2, Lint.Node>, out: List<&2, U32>) -> List<&2, U32>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{Lint.Parameter{b, Lint.Template{}}, n, s, k, f}, rest}:
      templates(rest, b <> out)
    case Con{node, rest}:
      templates(rest, out)

# A closure's application: of a variable that no `~` parameter (`templates`) binds.
def applies.visit(
  +templates: List<&2, U32>,
  +path: List<&2, Lint.Above>,
  +node: Lint.Node
) -> List<&2, Unit>:
  match node:
    case Lint.Node{
      Lint.Application{},
      n,
      s,
      Con{Lint.Node{Lint.Variable{b}, vn, vs, vk, vf}, args},
      f
    }:
      Lists.push(
        Unit,
        Lists.when(Unit, Bool.not(List.contains(~U32, ~U32.is_eq, templates, b)), Unit{}),
        []
      )
    case _:
      []

# Whether a definition's nodes apply a closure, or `found`.
def applies(+kids: List<&2, Lint.Node>, found: Bool) -> Bool:
  match found:
    case True{}:
      True{}
    case False{}:
      Bool.not(
        List.is_empty(
          &2,
          Unit,
          Lint.visit(~List<&2, U32>, ~Unit, ~applies.visit, templates(kids, []), kids)
        )
      )

# The definitions among a file's `nodes` whose own body keeps them from compiling to a native loop, onto `out`: a
# parallel let is in them, or a closure's application.
def unflat(nodes: List<&2, Lint.Node>, out: List<&2, String>) -> List<&2, String>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{Lint.Definition{t, u}, n, s, +kids, f}, rest}:
      unflat(
        rest,
        Lists.push(String, Lists.when(String, applies(kids, Lint.forks(kids, False{})), t), out)
      )
    case Con{node, rest}:
      unflat(rest, out)

# The definitions of the program whose own body keeps them from compiling to a native loop, onto `out`: those of
# `unflat`, and those that call themselves outside a tail position.
def program.unflat(sources: List<&2, Lint.Source>, out: List<&2, String>) -> List<&2, String>:
  match sources:
    case Nil{}:
      out
    case Con{Lint.Source{path, ns, text, +nodes}, rest}:
      program.unflat(rest, unflat(nodes, Deep.deep(nodes, True{}, out)))

def calls_itself(info: Maybe<&2, Lint.Def>) -> Bool:
  match info:
    case Some{Lint.Def{t, ps, forks, calls, r}}:
      List.contains(~String, ~String.eq, calls, t)
    case None{}:
      False{}

# The definitions among `names` that call themselves and are in `unflat`, onto `out`.
def loops(
  names: List<&2, String>,
  +defs: Map<&2, Maybe<&2, Lint.Def>>,
  +unflat: Set(),
  out: List<&2, String>
) -> List<&2, String>:
  match names:
    case Nil{}:
      out
    case Con{+t, rest}:
      loops(
        rest,
        defs,
        unflat,
        Lists.push(
          String,
          Lists.when(String, Sets.has(unflat, t) && calls_itself(Names.find(Lint.Def, defs, t)), t),
          out
        )
      )

# The definitions of the program a call of which runs a loop to its end, even when its value is unused: a loop that does
# not compile to a native loop, as its body, or one it calls, keeps it from that (see program.unflat); or a definition
# that calls such a loop.
def costly(+sources: List<&2, Lint.Source>, +defs: Map<&2, Maybe<&2, Lint.Def>>) -> Set():
  Lint.Program.callers(
    sources,
    defs,
    Set.from_list(
      loops(
        Map.keys(&2, Maybe<&2, Lint.Def>, defs),
        defs,
        Lint.Program.callers(sources, defs, Set.from_list(program.unflat(sources, []))),
        []
      )
    )
  )

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +sources = Lint.Here.sources(here)
  Lint.done(
    defs(
      Lint.Here.nodes(here),
      costly(sources, Lint.Program.defs(sources, Map.new(&2, Maybe<&2, Lint.Def>))),
      []
    )
  )

def rule() -> Lint.Rule:
  Lint.Rule{Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
