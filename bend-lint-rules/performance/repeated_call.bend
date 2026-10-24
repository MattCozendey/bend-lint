# performance/repeated_call: a call made again, with the same arguments, on one path of a definition: a
# second call of a definition of the file that loops and returns a number, with its arguments written the
# same way, in the same branch (the innermost case around both, or the definition's body).
# Heuristics: clang does not merge two calls of a definition that loops: Bend runs each through its own
# calls. Measured on the CPU, pow2(30) written `Nat.add(pow2(q), pow2(q))` took 3.4 s; with the two calls
# forked (a parallel let), 0.6 s; computed once (`+h = pow2(q)`), 0.1 s, the program's start. In
# eldergrove-faire and in llama.bend's tokenizer, computing such calls once changed nothing measurable:
# they walk short lists. Arguments are the same when written the same way: the same variables, literals,
# and calls or constructions of them. Calls in a lambda, in a type, in a proof, or in the values of
# Bool.pick, `&&` or `||` (which performance/eager_branch judges) do not count, nor do the values of one
# parallel let: copies made in parallel on purpose, as benchmarks do. A call that
# performance/loop_invariant_call reports is left to it: computing it once before the loop also ends the
# repeat. Only a number is sure to be shareable at no cost: data may be affine (an Array), so that it
# must be built twice, and sharing it counts references; it is skipped. Numbers are those of
# performance/gpu_fit, as the callee's return type is written.
import Base
import ../../src/linter/lint.bend as Lint
import ../../src/shared/lists.bend as Lists
import ../../src/shared/names.bend as Names
import ./deep_call_in_fork.bend as Deep
import ./gpu_fit.bend as GpuFit
import ./loop_invariant_call.bend as Invariant
import ./missed_fork.bend as Fork

# Types
# =====

# A call of a definition that loops: the definition (as the check names it, and as written), its arguments, where it
# is written, and where its branch starts (0 for a definition's body).
type Call is Data:
  Call{target: String, callee: String, args: List<&2, Lint.Node>, span: Lint.Span, branch: U32}

# What finding the calls of one definition reads: what performance/loop_invariant_call reads to judge them, with the
# definitions of the file that call themselves (as the check names them), and the program's definitions, by the name
# the check gives them.
type Scope is Data:
  Scope{owner: Invariant.Owner, defs: Map<&2, Maybe<&2, Lint.Def>>}

# Functions
# =========
def Call.target(c: Call) -> String:
  match c:
    case Call{t, callee, args, span, b}:
      t

def Call.callee(c: Call) -> String:
  match c:
    case Call{t, callee, args, span, b}:
      callee

def Call.args(c: Call) -> List<&2, Lint.Node>:
  match c:
    case Call{t, callee, args, span, b}:
      args

def Call.span(c: Call) -> Lint.Span:
  match c:
    case Call{t, callee, args, span, b}:
      span

def Call.branch(c: Call) -> U32:
  match c:
    case Call{t, callee, args, span, b}:
      b

def message(callee: String, loop: String) -> String:
  callee
    ++ " is called again here, with the same arguments, on this path of "
    ++ loop
    ++ ", so Bend computes it twice: clang does not merge calls of a definition that loops. All lanes. Measured on the CPU: pow2(30) written `Nat.add(pow2(q), pow2(q))` took 3.4 s, against 0.1 s after the fix; in eldergrove-faire and in llama.bend's tokenizer, the fix changed nothing measurable, as those calls walk short lists. Confidence: medium, as the gain is what the call costs. Bind its value once, with `+` if it is used twice, and use that name. If the call is cheap, such as a walk of a short list, expect this finding."

# Whether a node below `path` may not run on the path of its branch, or runs as a copy made on purpose: under a lambda,
# a value of a choice (Bool.pick, Bool.and, Bool.or), or a value of a parallel let.
def is_guarded(path: List<&2, Lint.Above>, found: Bool) -> Bool:
  match path found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{Lint.Above{Lint.Node{Lint.Lambda{b, q}, n, s, k, f}, at}, rest} False{}:
      True{}
    case Con{Lint.Above{Lint.Node{Lint.Application{}, n, s, +kids, f}, at}, rest} False{}:
      is_guarded(rest, Fork.is_choice(kids))
    case Con{Lint.Above{Lint.Node{Lint.Destructure{q}, n, s, +kids, f}, at}, rest} False{}:
      is_guarded(rest, Nat.is_gt(Deep.binders(kids, 0n), 1n) && Bool.not(Deep.is_last(kids, at)))
    case Con{a, rest} False{}:
      is_guarded(rest, False{})

# Where the first of `nodes`, or a node under it, that has a place starts.
def first_beg(+fuel: Nat, nodes: List<&2, Lint.Node>) -> U32:
  match fuel nodes:
    case 0n _:
      0
    case _ Nil{}:
      0
    case 1n+f Con{Lint.Node{syntax, n, Some{Lint.Span{p, beg, end}}, k, fs}, rest}:
      beg
    case 1n+f Con{Lint.Node{syntax, n, None{}, k, fs}, rest}:
      first_beg(f, List.append(&2, Lint.Node, k, rest))

# Where a branch starts (a case has no place of its own: its first node with one), or 0 for a definition's body.
def branch.at(b: Maybe<&2, Lint.Node>) -> U32:
  match b:
    case Some{node}:
      first_beg(64n, [node])
    case None{}:
      0

# Whether a definition of the program says it returns a number.
def returns_number(info: Maybe<&2, Lint.Def>) -> Bool:
  match info:
    case Some{Lint.Def{t, ps, fk, cs, r}}:
      GpuFit.is_scalar(r)
    case None{}:
      False{}

# Whether a call that counts so far (if `ok`) still counts: not if performance/loop_invariant_call reports it.
def is_kept(ok: Bool, owner: Invariant.Owner, path: List<&2, Lint.Above>, node: Lint.Node) -> Bool:
  match ok:
    case True{}:
      List.is_empty(&2, Lint.Finding, Invariant.visit(owner, path, node))
    case False{}:
      False{}

# The call of a definition that loops at an application below `path`, if it counts.
def visit(+scope: Scope, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, Call>:
  match scope node:
    case Scope{
      Invariant.Owner{+loops, target, name, fixed},
      defs
    } Lint.Node{
      Lint.Application{},
      n,
      Some{span},
      Con{Lint.Node{Lint.Reference{+t}, callee, rs, rk, rf}, args},
      f
    }:
      Bool.pick(
        List<&2, Call>,
        is_kept(
          List.contains(
            ~String,
            ~String.eq,
            loops,
            t
          )
            && returns_number(Names.find(Lint.Def, defs, t))
            && Lint.is_live(path)
            && Bool.not(is_guarded(path, False{})),
          Invariant.Owner{loops, target, name, fixed},
          path,
          node
        ),
        [Call{t, callee, args, span, branch.at(Invariant.branch(path, None{}))}],
        []
      )
    case _ _:
      []

# Whether two nodes, as written, are the same at their top: the same variable, literal or reference, or the same kind
# of application, annotation or construction (their nodes below are compared next).
def is_shallow(x: Lint.Node, y: Lint.Node) -> Bool:
  match x y:
    case Lint.Node{Lint.Variable{a}, n, s, k, f} Lint.Node{Lint.Variable{b}, m, r, j, g}:
      U32.is_eq(a, b)
    case Lint.Node{Lint.Literal{a}, n, s, k, f} Lint.Node{Lint.Literal{b}, m, r, j, g}:
      String.eq(a, b) && String.eq(n, m)
    case Lint.Node{Lint.Reference{a}, n, s, k, f} Lint.Node{Lint.Reference{b}, m, r, j, g}:
      String.eq(a, b)
    case Lint.Node{Lint.Application{}, n, s, k, f} Lint.Node{Lint.Application{}, m, r, j, g}:
      True{}
    case Lint.Node{Lint.Annotation{}, n, s, k, f} Lint.Node{Lint.Annotation{}, m, r, j, g}:
      True{}
    case Lint.Node{Lint.Construction{a}, n, s, k, f} Lint.Node{Lint.Construction{b}, m, r, j, g}:
      String.eq(a, b)
    case _ _:
      False{}

# Whether `xs` and `ys` are written the same way, node by node and below (if `ok`); `fuel` bounds the nodes compared.
def is_same(+fuel: Nat, xs: List<&2, Lint.Node>, ys: List<&2, Lint.Node>, ok: Bool) -> Bool:
  match fuel xs ys ok:
    case _ _ _ False{}:
      False{}
    case _ Nil{} Nil{} True{}:
      True{}
    case 0n _ _ True{}:
      False{}
    case 1n+f Con{+x, xt} Con{+y, yt} True{}:
      is_same(
        f,
        List.append(&2, Lint.Node, Lint.Node.kids(x), xt),
        List.append(&2, Lint.Node, Lint.Node.kids(y), yt),
        is_shallow(x, y)
      )
    case _ _ _ True{}:
      False{}

# Whether `c` repeats a call of `seen`: the same definition, in the same branch, with arguments written the same way.
def repeats(seen: List<&2, Call>, +c: Call, found: Bool) -> Bool:
  match seen found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{Call{t, callee, args, span, b}, rest} False{}:
      repeats(
        rest,
        c,
        is_same(
          256n,
          args,
          Call.args(c),
          String.eq(t, Call.target(c)) && U32.is_eq(b, Call.branch(c))
        )
      )

# The findings about the calls of one definition (`loop`, as written) that repeat an earlier one, onto `out`.
def judged(
  calls: List<&2, Call>,
  +seen: List<&2, Call>,
  +loop: String,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match calls:
    case Nil{}:
      out
    case Con{+c, rest}:
      judged(
        rest,
        c <> seen,
        loop,
        Lists.onto(
          &2,
          Lint.Finding,
          Lint.finding(
            Lint.Information{},
            repeats(seen, c, False{}),
            Some{Call.span(c)},
            message(Call.callee(c), loop)
          ),
          out
        )
      )

# The calls of a definition (`node`) that count, unless it is a proof.
def calls.of(
  proof: Bool,
  loops: List<&2, String>,
  defs: Map<&2, Maybe<&2, Lint.Def>>,
  +node: Lint.Node
) -> List<&2, Call>:
  match proof:
    case True{}:
      []
    case False{}:
      Lint.visit(~Scope, ~Call, ~visit, Scope{Invariant.Owner.of(loops, node), defs}, [node])

def defs(
  nodes: List<&2, Lint.Node>,
  +loops: List<&2, String>,
  +program: Map<&2, Maybe<&2, Lint.Def>>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Node{Lint.Definition{t, u}, +n, s, +k, f}, rest}:
      defs(
        rest,
        loops,
        program,
        judged(
          calls.of(
            Invariant.is_proof(k),
            loops,
            program,
            Lint.Node{Lint.Definition{t, u}, n, s, k, f}
          ),
          [],
          n,
          out
        )
      )
    case Con{node, rest}:
      defs(rest, loops, program, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +nodes = Lint.Here.nodes(here)
  Lint.done(
    defs(
      nodes,
      Invariant.loops(nodes, []),
      Lint.Program.defs(Lint.Here.sources(here), Map.new(&2, Maybe<&2, Lint.Def>)),
      []
    )
  )

def rule() -> Lint.Rule:
  Lint.Rule{Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
