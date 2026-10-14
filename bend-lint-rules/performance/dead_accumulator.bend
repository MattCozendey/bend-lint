# performance/dead_accumulator: a parameter of a loop that only grows and is never read: each use of it is
# an argument of the loop's call of itself, at its own place, with something added to it (inside a
# constructor, such as `x <> acc`), and the loop never matches it, returns it, or gives it to another
# call. It is built on every step and freed at the end.
# Heuristics: measured on bend-ml's BPE encode (bend-ml-bpe-tokenizer, as llama.bend uses it): its
# `done` keeps the rules applied so far, for its proofs, and `encode` drops it; a 48,900-entry list built
# and freed for each word was half of the time to tokenize 19 KB of text (26.1 s, against 11.5 s with
# `-done`), with the same ids and the same proofs. A parameter that the loop passes unchanged is not
# reported: it grows nothing. A use in a type or a proof does not count, as it does not run: the fix,
# an erased parameter (`-acc`), keeps it there. Only the loop's own calls are read; a call of the loop
# through another definition, or through a template, is not.
import Base
import ../../src/linter/lint.bend as Lint
import ../../src/shared/lists.bend as Lists

# Types
# =====

# What judging the uses of one parameter reads: its loop's name (as the check names it), the place of the parameter
# among the loop's parameters (as a call's arguments are), and its binder.
type Owner is Data:
  Owner{target: String, at: U32, binder: U32}

# Functions
# =========
def message(+name: String, loop: String) -> String:
  name
    ++ " only grows: "
    ++ loop
    ++ " passes it to itself with something added, and nothing reads it, so Bend builds it on every step and frees it at the end. All lanes. Measured on the CPU, in bend-ml's BPE encode, where such a list, built per word, was half of the time: 26.1 s to tokenize 19 KB of text, against 11.5 s after the fix. Confidence: medium, as the gain is what building it costs. Erase it, with `-"
    ++ name
    ++ "`: the checker keeps it for proofs, and the compiler deletes it; or remove it. If it gets only a few small items, expect this finding."

# How a use of the parameter below `path` ends: 0 if it is read (in anything but the loop's call of itself, at the
# parameter's place), 1 if it is passed there as it is, 2 if it is passed there with something added (`grown`).
def kind(path: List<&2, Lint.Above>, target: String, at: U32, grown: Bool) -> U32:
  match path:
    case Con{Lint.Above{Lint.Node{Lint.Construction{t}, n, s, k, f}, a}, rest}:
      kind(rest, target, at, True{})
    case Con{Lint.Above{Lint.Node{Lint.Annotation{}, n, s, k, f}, a}, rest}:
      kind(rest, target, at, grown)
    case Con{
      Lint.Above{
        Lint.Node{
          Lint.Application{},
          n,
          s,
          Con{Lint.Node{Lint.Reference{t}, rn, rs, rk, rf}, args},
          f
        },
        a
      },
      rest
    }:
      Bool.pick(
        U32,
        String.eq(t, target) && U32.is_eq(a, (at + 1: U32)),
        Bool.pick(U32, grown, 2, 1),
        0
      )
    case _:
      0

# How the parameter is used at a node, below `path`, if the node is a use of it in live code.
def use.visit(+owner: Owner, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, U32>:
  match owner node:
    case Owner{target, at, binder} Lint.Node{Lint.Variable{v}, n, s, k, f}:
      Bool.pick(
        List<&2, U32>,
        U32.is_eq(v, binder) && Lint.is_live(path),
        [kind(path, target, at, False{})],
        []
      )
    case _ _:
      []

# Whether a parameter of quantity `q` that is used as `kinds` says is a dead accumulator: it is there at run time, it
# is only passed to the loop's own calls, and grows in one at least.
def is_dead(q: Lint.Quantity, +kinds: List<&2, U32>) -> Bool:
  match q:
    case Lint.Erased{}:
      False{}
    case Lint.Template{}:
      False{}
    case _:
      Bool.not(
        List.contains(~U32, ~U32.is_eq, kinds, 0)
      )
        && List.contains(~U32, ~U32.is_eq, kinds, 2)

# The findings about the parameters among `nodes`, a definition's, onto `out`; `at` is the place of the first.
def params(
  nodes: List<&2, Lint.Node>,
  +loop: Lint.Node,
  +target: String,
  +name: String,
  +at: U32,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{Lint.Parameter{b, q}, pn, ps, pk, pf}, rest}:
      params(
        rest,
        loop,
        target,
        name,
        (at + 1: U32),
        Lists.onto(
          &2,
          Lint.Finding,
          Lint.finding(
            Lint.Information{},
            is_dead(q, Lint.visit(~Owner, ~U32, ~use.visit, Owner{target, at, b}, [loop])),
            ps,
            message(pn, name)
          ),
          out
        )
      )
    case Con{node, rest}:
      params(rest, loop, target, name, at, out)

def defs(nodes: List<&2, Lint.Node>, out: List<&2, Lint.Finding>) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Node{Lint.Definition{+t, u}, +n, s, +k, f}, rest}:
      defs(rest, params(k, Lint.Node{Lint.Definition{t, u}, n, s, k, f}, t, n, 0, out))
    case Con{node, rest}:
      defs(rest, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(defs(Lint.Here.nodes(here), []))

def rule() -> Lint.Rule:
  Lint.Rule{Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
