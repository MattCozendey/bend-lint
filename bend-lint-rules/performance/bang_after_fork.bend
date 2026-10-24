# performance/bang_after_fork: a `!` call that runs after a fork of the same evaluation, so Bend runs it
# on the CPU pool, not on the GPU: in its definition, a let before it forks (a parallel let, or a value
# that calls a definition under which a parallel let runs), or one of its arguments does.
# Heuristics: a bang that follows the host's forks in one evaluation runs on the CPU pool ("bend guide
# shaders"); a `!` call is not one of those forks: Bend's radix sort benchmark, three `!` calls in a row,
# took the same time with IO steps between them. Measured on a discrete GPU, a numeric bang that took
# 0.55 s on the GPU after an IO step took 3.9 s, its time on the CPU pool, after a parallel let, after a
# let whose value forked in a call, and with an argument that forked; after a let whose value looped
# without forking, it stayed on the GPU. A short call loses little on the CPU pool. An IO step (`<-` in a
# `do` block) starts a new evaluation, so a fork before one does not count; nor does a fork in a
# definition that calls this one, which the rule does not follow. A `!` call of a definition under which
# no parallel let runs, or of one that returns Unit, is left to performance/gpu_fit and
# performance/drop_in_bang: they ask to remove the `!`.
import Base
import ../../src/linter/lint.bend as Lint
import ../../src/shared/lists.bend as Lists
import ../../src/shared/names.bend as Names
import ./deep_call_in_fork.bend as Deep
import ./gpu_fit.bend as GpuFit

# Types
# =====

# What judging a file's calls reads: the program's definitions, by the name the check gives them; those under which a
# parallel let runs (see GpuFit.program.under); and where the file writes `!(`.
type Program is Data:
  Program{defs: Map<&2, Maybe<&2, GpuFit.Def>>, under: Set(), bangs: List<&2, U32>}

# Functions
# =========
def message(callee: String) -> String:
  callee
    ++ "! runs after a fork in the same evaluation (no IO step between them), so Bend runs it on the CPU pool, not on the GPU. GPU: measured 3.9 s for a numeric fork tree, against 0.55 s after the fix. CPU (`--gpu off`): no change. JS: no GPU, so no change. Confidence: high, as Bend's scheduler decides it. Put an IO step, such as `t : Nat <- IO.now()`, between the forks and this call, as Bend's slash boss demo does. If this call is short, so that the CPU pool runs it as fast, expect this finding."

# The definition an application below `path` calls by name on the host: not with `!`, as a `!` call runs on the GPU,
# and a `!` call after it stays there.
def host.visit(
  +bangs: List<&2, U32>,
  +path: List<&2, Lint.Above>,
  +node: Lint.Node
) -> List<&2, String>:
  match node:
    case Lint.Node{
      Lint.Application{},
      n,
      s,
      Con{Lint.Node{Lint.Reference{t}, rn, Some{Lint.Span{p, beg, end}}, rk, rf}, args},
      f
    }:
      Bool.pick(List<&2, String>, List.contains(~U32, ~U32.is_eq, bangs, end), [], [t])
    case _:
      []

# Whether `nodes` fork on the host when they run: a call among them or under them, made without `!`, is of a
# definition under which a parallel let runs.
def forks(nodes: List<&2, Lint.Node>, program: Program) -> Bool:
  match program:
    case Program{defs, under, bangs}:
      GpuFit.reaches(Lint.visit(~List<&2, U32>, ~String, ~host.visit, bangs, nodes), under, False{})

# The nodes of a let (`kids`) that run before the rest of its block, its last node: its binders and values.
def let.values(+kids: List<&2, Lint.Node>) -> List<&2, Lint.Node>:
  List.take(&2, Lint.Node, kids, Nat.sub(Lists.length(&2, Lint.Node, kids), 1n))

# Whether the let of `kids` forks before the rest of its block, if the node is in it (`last`): it is a parallel let
# (`parallel`), or a value of it forks.
def let.forks(last: Bool, parallel: Bool, kids: List<&2, Lint.Node>, program: Program) -> Bool:
  match last parallel:
    case False{} _:
      False{}
    case True{} True{}:
      True{}
    case True{} False{}:
      forks(let.values(kids), program)

# Whether a fork runs before the node below `path`, in the same evaluation, or `found`: a let above it, whose rest of
# block it is in, forks (a parallel let, or a value that forks), and no lambda (the rest of an IO step) comes between.
def after(path: List<&2, Lint.Above>, +program: Program, found: Bool) -> Bool:
  match path found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{Lint.Above{Lint.Node{Lint.Lambda{b, q}, n, s, k, f}, at}, rest} False{}:
      False{}
    case Con{Lint.Above{Lint.Node{Lint.Body{}, n, s, k, f}, at}, rest} False{}:
      False{}
    case Con{Lint.Above{Lint.Node{Lint.Destructure{q}, n, s, +kids, f}, at}, rest} False{}:
      after(
        rest,
        program,
        let.forks(Deep.is_last(kids, at), Nat.is_gt(Deep.binders(kids, 0n), 1n), kids, program)
      )
    case Con{Lint.Above{Lint.Node{Lint.Let{}, n, s, +kids, f}, at}, rest} False{}:
      after(rest, program, let.forks(Deep.is_last(kids, at), False{}, kids, program))
    case Con{a, rest} False{}:
      after(rest, program, False{})

# Whether a fork runs before a call with `args` below `path`, in the same evaluation, if it is `asked`: an argument
# forks, or a let above it does.
def after.if(
  asked: Bool,
  args: List<&2, Lint.Node>,
  path: List<&2, Lint.Above>,
  +program: Program
) -> Bool:
  match asked:
    case True{}:
      after(path, program, forks(args, program))
    case False{}:
      False{}

# The finding about an application below `path`, if it is a `!` call of a definition that forks, made after a fork.
def visit(
  +program: Program,
  +path: List<&2, Lint.Above>,
  +node: Lint.Node
) -> List<&2, Lint.Finding>:
  match program node:
    case Program{
      +defs,
      +under,
      +bangs
    } Lint.Node{
      Lint.Application{},
      n,
      span,
      Con{Lint.Node{Lint.Reference{+t}, callee, Some{Lint.Span{p, beg, end}}, k, f}, args},
      facts
    }:
      Lint.finding(
        Lint.Warning{},
        after.if(
          List.contains(
            ~U32,
            ~U32.is_eq,
            bangs,
            end
          )
            && GpuFit.is_under(under, t)
            && Bool.not(GpuFit.is_drop(Names.find(GpuFit.Def, defs, t), t)),
          args,
          path,
          Program{defs, under, bangs}
        ),
        span,
        message(callee)
      )
    case _ _:
      []

# The findings in the file of `here`, which writes `!(` where `bangs` say: none, if it writes none.
def scanned(+here: Lint.Here, bangs: List<&2, U32>) -> Lint.Ask(List<&2, Lint.Finding>):
  match bangs:
    case Nil{}:
      Lint.done([])
    case Con{b, rest}:
      +sources = Lint.Here.sources(here)
      +defs = GpuFit.program.defs(sources, Map.new(&2, Maybe<&2, GpuFit.Def>))
      Lint.done(
        Lint.visit(
          ~Program,
          ~Lint.Finding,
          ~visit,
          Program{defs, GpuFit.program.under(sources, defs), Con{b, rest}},
          Lint.Here.nodes(here)
        )
      )

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  scanned(here, GpuFit.bangs(Lint.Here.text(here), 0, []))

def rule() -> Lint.Rule:
  Lint.Rule{Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
