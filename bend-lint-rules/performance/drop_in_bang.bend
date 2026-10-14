# performance/drop_in_bang: a `!` call of a definition that returns Unit: Base's Image.drop, Image.free
# or Image.sink, or a definition of the program declared `-> Unit`. A pure definition that returns Unit
# does nothing but free what it receives, and a GPU frees slower than its CPU.
# Heuristics: measured on a discrete GPU (CUDA), 30 frames that each dropped a 1M-leaf image with
# `Image.drop!` took 1.55 s, against 0.10 s with `Image.drop` (0.104 s against 0.094 s with `--gpu off`).
# "bend guide shaders" measured freeing Bend's slash boss scene in a bang at 12.9 ms a frame, against 8.0
# ms, on an Apple M-series GPU, whose memory is unified: the GPU loses on both kinds of memory. The JS
# lane has no GPU. A return type written another way (an alias of Unit) is not known.
import Base
import ../../src/linter/lint.bend as Lint
import ../../src/shared/names.bend as Names
import ./gpu_fit.bend as GpuFit

# Types
# =====

# What judging a file's calls reads: the program's definitions, by the name the check gives them, and where the file
# writes `!(`.
type Program is Data:
  Program{defs: Map<&2, Maybe<&2, GpuFit.Def>>, bangs: List<&2, U32>}

# Functions
# =========
def message(callee: String) -> String:
  callee
    ++ "! only frees what it receives, as it returns Unit, and a GPU frees slower than its CPU. GPU: measured 15x slower than without the `!` on a discrete GPU (CUDA), dropping a 1M-leaf image; with unified memory (Apple M-series), freeing a scene in a bang made a frame 12.9 ms, against 8.0 ms (\"bend guide shaders\"). CPU (`--gpu off`): 10% slower. JS: no GPU, so no change. Confidence: high, as a GPU does not speed up freeing. Remove the `!`; to drop the last frame, let the next frame's fork tree drop it, a quadrant per tile (\"bend guide shaders\"). If a timing shows the `!` faster here, expect this finding."

# The finding about an application below `path`, if it is a `!` call that only frees.
def visit(
  +program: Program,
  +path: List<&2, Lint.Above>,
  +node: Lint.Node
) -> List<&2, Lint.Finding>:
  match program node:
    case Program{
      defs,
      bangs
    } Lint.Node{
      Lint.Application{},
      n,
      span,
      Con{Lint.Node{Lint.Reference{+t}, callee, Some{Lint.Span{p, beg, end}}, k, f}, args},
      facts
    }:
      Lint.finding(
        Lint.Warning{},
        List.contains(
          ~U32,
          ~U32.is_eq,
          bangs,
          end
        )
          && GpuFit.is_drop(Names.find(GpuFit.Def, defs, t), t),
        span,
        message(callee)
      )
    case _ _:
      []

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(
    Lint.visit(
      ~Program,
      ~Lint.Finding,
      ~visit,
      Program{
        GpuFit.program.defs(Lint.Here.sources(here), Map.new(&2, Maybe<&2, GpuFit.Def>)),
        GpuFit.bangs(Lint.Here.text(here), 0, [])
      },
      Lint.Here.nodes(here)
    )
  )

def rule() -> Lint.Rule:
  Lint.Rule{Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
