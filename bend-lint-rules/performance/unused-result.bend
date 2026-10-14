# performance/unused-result: a value that a loop binds and never uses, and that is data, not a number: a
# lambda's parameter or a let's name, in a definition that calls itself. Bend computes every value it
# binds, so this one is built, and then walked to be freed, on every step.
# Heuristics: measured on llama.bend (SmolLM2-135M, CPU): its generation loop binds each layer's
# activations and never uses them; building them empty made each token 19% to 25% faster, with the same
# tokens. The cost grows with the value: a small one costs little to ignore. It reads how often the
# checker found each binder used, and the type it gave it; numbers, and records of numbers only, are
# those of performance/gpu-fit, and cost nothing to drop. An erased binder holds nothing at run time,
# and a step of a `do` block (`x : T <- m`, a call of a bind) gets its value from the monad, used or not.
import Base
import ../../src/linter/lint.bend as Lint
import ../../src/shared/lists.bend as Lists
import ./gpu-fit.bend as GpuFit

# Types
# =====

# A binder a loop never uses: where it is written, its name, the loop's name, and the type the checker gave it.
type Unused is Data:
  Unused{span: Lint.Span, name: String, loop: String, ty: Lint.TypeRef}

# What judging the binders of one definition reads: whether it is a loop (it calls itself), and its name as written.
type Owner is Data:
  Owner{loop: Bool, name: String}

# Functions
# =========
def message(+name: String, loop: String) -> String:
  name
    ++ " is never used, but Bend computes every value it binds: "
    ++ name
    ++ " is built, then walked to be freed, on every step of "
    ++ loop
    ++ ". All lanes. Measured on the CPU, in llama.bend: not building the activations that its generation loop never used made each token 19% to 25% faster. Confidence: medium, as the cost grows with the value. Have the code that makes "
    ++ name
    ++ " skip it, such as a variant that does not build it. If it is small, expect this finding."

def loop.visit(+u: Unit, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, Unit>:
  Bool.pick(List<&2, Unit>, Lint.is_recursive(path, node), [Unit{}], [])

# Whether a lambda below `path` is the rest of a step of a `do` block (`x : T <- m`, the last argument of a call of a
# bind): its value comes from the monad, which makes it whether it is used or not.
def is_step(path: List<&2, Lint.Above>) -> Bool:
  match path:
    case Con{
      Lint.Above{
        Lint.Node{
          Lint.Application{},
          n,
          s,
          Con{Lint.Node{Lint.Reference{t}, rn, rs, rk, rf}, args},
          f
        },
        at
      },
      rest
    }:
      String.ends_with(t, ".bind")
    case _:
      False{}

# Whether a node of this kind, below `path`, binds a value at run time: a lambda's parameter (not a `do` step's), or a
# let's name (a binding, or the one pattern variable of a let), not erased.
def is_binder(syntax: Lint.Syntax, path: List<&2, Lint.Above>) -> Bool:
  match syntax path:
    case Lint.Lambda{b, Some{Lint.Erased{}}} _:
      False{}
    case Lint.Lambda{b, q} _:
      Bool.not(is_step(path))
    case Lint.Binding{b, Lint.Erased{}} _:
      False{}
    case Lint.Binding{b, q} _:
      True{}
    case Lint.PatternVariable{b, Lint.Erased{}} _:
      False{}
    case Lint.PatternVariable{
      b,
      q
    } Con{Lint.Above{Lint.Node{Lint.Destructure{d}, n, s, k, f}, at}, rest}:
      True{}
    case _ _:
      False{}

# The type of a binder its facts say is never used, if they do.
def unused(facts: List<&2, Lint.Fact>) -> Maybe<&2, Lint.TypeRef>:
  match facts:
    case Nil{}:
      None{}
    case Con{Lint.Fact{Lint.OfBinder{}, q, Some{Lint.Erased{}}, t}, rest}:
      Some{t}
    case Con{f, rest}:
      unused(rest)

def unused.of(
  binder: Bool,
  ty: Maybe<&2, Lint.TypeRef>,
  span: Lint.Span,
  name: String,
  loop: String
) -> List<&2, Unused>:
  match binder ty:
    case True{} Some{t}:
      [Unused{span, name, loop, t}]
    case _ _:
      []

def visit(+owner: Owner, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, Unused>:
  match owner node:
    case Owner{True{}, loop} Lint.Node{syntax, name, Some{span}, k, facts}:
      unused.of(is_binder(syntax, path), unused(facts), span, name, loop)
    case _ _:
      []

# The binders that the loops among `nodes` never use, onto `out` (last first).
def defs(nodes: List<&2, Lint.Node>, out: List<&2, Unused>) -> List<&2, Unused>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{Lint.Definition{t, u}, +n, s, k, f}, rest}:
      +owner = {Lint.Node{Lint.Definition{t, u}, n, s, k, f}: Lint.Node}
      defs(
        rest,
        Lists.onto(
          &2,
          Unused,
          List.reverse(
            &2,
            Unused,
            Lint.visit(
              ~Owner,
              ~Unused,
              ~visit,
              Owner{
                Bool.not(
                  List.is_empty(&2, Unit, Lint.visit(~Unit, ~Unit, ~loop.visit, Unit{}, [owner]))
                ),
                n
              },
              [owner]
            )
          ),
          out
        )
      )
    case Con{node, rest}:
      defs(rest, out)

def types(found: List<&2, Unused>, out: List<&2, Lint.TypeRef>) -> List<&2, Lint.TypeRef>:
  match found:
    case Nil{}:
      List.reverse(&2, Lint.TypeRef, out)
    case Con{Unused{s, n, l, t}, rest}:
      types(rest, t <> out)

# The findings about the unused binders whose types, as shown, are data: not numbers, nor records of numbers only.
def judged(
  found: List<&2, Unused>,
  shown: List<&2, String>,
  +slots: List<&2, GpuFit.Slot>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match found shown:
    case Con{Unused{span, name, loop, t}, rest} Con{ty, more}:
      judged(
        rest,
        more,
        slots,
        Lists.onto(
          &2,
          Lint.Finding,
          Lint.finding(
            Lint.Information{},
            Bool.not(GpuFit.is_flat(64n, Some{[ty]}, slots)),
            Some{span},
            message(name, loop)
          ),
          out
        )
      )
    case _ _:
      List.reverse(&2, Lint.Finding, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +found = List.reverse(&2, Unused, defs(Lint.Here.nodes(here), []))
  slots = GpuFit.program.slots(Lint.Here.sources(here), [])
  do Lint.Ask<List<&2, Lint.Finding>>:
    shown: List<&2, String> <- Lint.show_all(types(found, []))
    return judged(found, shown, slots, [])

def rule() -> Lint.Rule:
  Lint.Rule{Lint.Needs{True{}, False{}}, [], Lint.OnFile{run}}
