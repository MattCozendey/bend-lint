# performance/gpu-fit: a call that may run faster on the other side of the GPU: a `!` call (it runs on the
# GPU, if there is one) of a definition under which no parallel let runs, so one GPU lane runs it alone;
# a `!` call of a definition that forks but receives data, not only numbers; or a call of a definition
# that forks over numbers only, made without `!`, from a definition that does not fork.
# Heuristics: measured on an RTX 4050 laptop GPU against 20 threads of its CPU (`--gpu off`): a `!` on
# BendSR's compute_mae, a list walk that never forks, took 6.5 s against 0.08 s without the `!` (0.11 s
# against 0.07 s on the CPU); Bend's slash boss draw, which forks over data, took 10.5 ms against 7.4 ms;
# the GPU also costs a fixed 0.3 to 0.8 s to start there, after which numeric work is nearly free: a
# numeric fork tree of 16,384 leaves took 0.95 s against 3.6 s on the CPU, but one that took 0.06 s on
# the CPU took 0.49 s. The same draw takes 8 ms on an M4 (unified memory), and an RTX 4090 desktop drew
# it at 17 to 19 FPS ("bend guide shaders"): a discrete GPU pays for each page it reads across PCIe,
# whatever its speed. It follows calls through the program's files; a definition outside them is
# Base's, where only Image.free (and Image.drop, through it) forks. Numbers are U32, I32, F32, Nat,
# Bool, Char (and their 64-bit forms), and a record of numbers only, defined in the program's files;
# anything else is data. Erased and template parameters do not count. A `!` call of a definition that
# returns Unit is left to performance/drop-in-bang.
import Base
import ../../src/linter/lint.bend as Lint
import ../../src/shared/lists.bend as Lists
import ../../src/shared/names.bend as Names

# Types
# =====

# A field of a datatype: the datatype, and the field's type as one name ("" if it is not one name).
type Slot is Data:
  Slot{owner: String, ty: String}

# A runtime parameter of a definition: its name, and its type as one name ("" if it is not one name).
type Param is Data:
  Param{name: String, ty: String}

# A definition of the program: its name as the check names it, its runtime parameters, whether it forks, the
# definitions it calls by name, and the type it returns, as one name ("" if it is not one name).
type Def is Data:
  Def{
    target: String,
    params: List<&2, Param>,
    forks: Bool,
    calls: List<&2, String>,
    returns: String
  }

# What judging a file's calls reads: the program's definitions, by the name the check gives them; the fields of its
# datatypes; and where the file writes `!(`.
type Program is Data:
  Program{defs: Map<&2, Maybe<&2, Def>>, slots: List<&2, Slot>, bangs: List<&2, U32>}

# Functions
# =========

# The type the first of `nodes` writes, as one name, or "" for another form (an application, a list).
def plain(nodes: List<&2, Lint.Node>) -> String:
  match nodes:
    case Con{Lint.Node{Lint.Reference{t}, n, s, k, f}, rest}:
      t
    case _:
      ""

# The fields of the datatypes among `nodes` and under them (of `current`, the datatype they are under), onto `out`.
def slots(nodes: List<&2, Lint.Node>, +current: String, out: List<&2, Slot>) -> List<&2, Slot>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{Lint.Datatype{t}, n, s, kids, f}, rest}:
      slots(rest, current, slots(kids, t, out))
    case Con{Lint.Node{Lint.Constructor{t}, n, s, kids, f}, rest}:
      slots(rest, current, slots(kids, current, out))
    case Con{Lint.Node{Lint.Field{b, q}, n, s, kids, f}, rest}:
      slots(rest, current, Slot{current, plain(kids)} <> out)
    case Con{node, rest}:
      slots(rest, current, out)

# Whether a parameter of this quantity is there at run time.
def is_runtime(quantity: Lint.Quantity) -> Bool:
  match quantity:
    case Lint.Erased{}:
      False{}
    case Lint.Template{}:
      False{}
    case _:
      True{}

# The runtime parameters among a definition's nodes, in order, onto `out`.
def params(nodes: List<&2, Lint.Node>, out: List<&2, Param>) -> List<&2, Param>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Param, out)
    case Con{Lint.Node{Lint.Parameter{b, q}, n, s, kids, f}, rest}:
      params(rest, Lists.push(Param, Lists.when(Param, is_runtime(q), Param{n, plain(kids)}), out))
    case Con{node, rest}:
      params(rest, out)

# Whether a parallel let (two binders, at least) is among `nodes` or under them, or `found`.
def forks(nodes: List<&2, Lint.Node>, found: Bool) -> Bool:
  match nodes found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{
      Lint.Node{
        Lint.Destructure{q},
        n,
        s,
        Con{
          Lint.Node{Lint.PatternVariable{a, aq}, an, as, ak, af},
          Con{Lint.Node{Lint.PatternVariable{b, bq}, bn, bs, bk, bf}, more}
        },
        f
      },
      rest
    } False{}:
      True{}
    case Con{Lint.Node{syntax, n, s, kids, f}, rest} False{}:
      forks(rest, forks(kids, False{}))

# The definition an application below `path` calls by name.
def called.visit(+u: Unit, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, String>:
  match node:
    case Lint.Node{
      Lint.Application{},
      n,
      s,
      Con{Lint.Node{Lint.Reference{t}, rn, rs, rk, rf}, args},
      f
    }:
      [t]
    case _:
      []

# The type a definition's nodes say it returns, as one name, or "".
def returned(nodes: List<&2, Lint.Node>) -> String:
  match nodes:
    case Nil{}:
      ""
    case Con{Lint.Node{Lint.Returns{}, n, s, kids, f}, rest}:
      plain(kids)
    case Con{node, rest}:
      returned(rest)

# The definitions among a file's nodes, by the name the check gives them, onto `out`.
def defs(nodes: List<&2, Lint.Node>, out: Map<&2, Maybe<&2, Def>>) -> Map<&2, Maybe<&2, Def>>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{Lint.Definition{+t, u}, n, s, +kids, f}, rest}:
      defs(
        rest,
        Map.set(
          &2,
          Maybe<&2, Def>,
          out,
          t,
          Some{
            Def{
              t,
              params(kids, []),
              forks(kids, False{}),
              Lint.visit(~Unit, ~String, ~called.visit, Unit{}, kids),
              returned(kids)
            }
          }
        )
      )
    case Con{node, rest}:
      defs(rest, out)

# Whether a call of `t` (`info`, if the program defines it) only frees its inputs: it returns Unit, as Base's
# Image.drop, Image.free and Image.sink do.
def is_drop(info: Maybe<&2, Def>, t: String) -> Bool:
  match info:
    case Some{Def{d, ps, fs, cs, r}}:
      String.eq(r, "Unit")
    case None{}:
      List.contains(~String, ~String.eq, ["Image.drop", "Image.free", "Image.sink"], t)

# Whether Base's definition `t` forks: Image.free does, and Image.drop, through it.
def is_base_fork(t: String) -> Bool:
  List.contains(~String, ~String.eq, ["Image.free", "Image.drop"], t)

# What is left to visit after `t`: none if a parallel let runs in it (the answer is found); `rest` if it was seen;
# else `rest` and what `t` calls. A definition outside the program is Base's.
def reaches.next(
  info: Maybe<&2, Def>,
  seen: Bool,
  t: String,
  rest: List<&2, String>
) -> Maybe<&2, List<&2, String>>:
  match info seen:
    case _ True{}:
      Some{rest}
    case None{} False{}:
      Bool.pick(Maybe<&2, List<&2, String>>, is_base_fork(t), None{}, Some{rest})
    case Some{Def{d, ps, True{}, cs, r}} False{}:
      None{}
    case Some{Def{d, ps, False{}, cs, r}} False{}:
      Some{Lists.onto(&2, String, cs, rest)}

# Whether a parallel let runs under the definitions of `todo` (none: one was found): in them, or in what they call.
# `fuel` bounds the steps; when it runs out, the answer is `unknown`, the one that makes the caller report nothing.
def reaches(
  fuel: Nat,
  todo: Maybe<&2, List<&2, String>>,
  +seen: List<&2, String>,
  +defs: Map<&2, Maybe<&2, Def>>,
  unknown: Bool
) -> Bool:
  match fuel todo:
    case _ None{}:
      True{}
    case _ Some{Nil{}}:
      False{}
    case 0n _:
      unknown
    case 1n+f Some{Con{+t, rest}}:
      reaches(
        f,
        reaches.next(
          Names.find(Def, defs, t),
          List.contains(~String, ~String.eq, seen, t),
          t,
          rest
        ),
        t <> seen,
        defs,
        unknown
      )

def program.slots(sources: List<&2, Lint.Source>, out: List<&2, Slot>) -> List<&2, Slot>:
  match sources:
    case Nil{}:
      out
    case Con{Lint.Source{path, ns, text, nodes}, rest}:
      program.slots(rest, slots(nodes, "", out))

def program.defs(
  sources: List<&2, Lint.Source>,
  out: Map<&2, Maybe<&2, Def>>
) -> Map<&2, Maybe<&2, Def>>:
  match sources:
    case Nil{}:
      out
    case Con{Lint.Source{path, ns, text, nodes}, rest}:
      program.defs(rest, defs(nodes, out))

def is_scalar(t: String) -> Bool:
  List.contains(
    ~String,
    ~String.eq,
    ["U32", "I32", "F32", "Nat", "Bool", "Char", "U64", "I64", "F64", "Unit"],
    t
  )

def fields(slots: List<&2, Slot>, +t: String, out: List<&2, String>) -> List<&2, String>:
  match slots:
    case Nil{}:
      out
    case Con{Slot{o, ty}, rest}:
      fields(rest, t, Lists.push(String, Lists.when(String, String.eq(o, t), ty), out))

def is_known(slots: List<&2, Slot>, hit: Bool, +t: String) -> Bool:
  match slots hit:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{Slot{o, ty}, rest} False{}:
      is_known(rest, String.eq(o, t), t)

def is_flat.expand(
  known: Bool,
  t: String,
  rest: List<&2, String>,
  slots: List<&2, Slot>
) -> Maybe<&2, List<&2, String>>:
  match known:
    case True{}:
      Some{fields(slots, t, rest)}
    case False{}:
      None{}

# What is left to check after `t`: its fields, if it is a datatype; nothing more, if it is a number;
# none (data), else.
def is_flat.next(
  number: Bool,
  +t: String,
  rest: List<&2, String>,
  +slots: List<&2, Slot>
) -> Maybe<&2, List<&2, String>>:
  match number:
    case True{}:
      Some{rest}
    case False{}:
      is_flat.expand(is_known(slots, False{}, t), t, rest, slots)

# Whether the types of `todo` are numbers, or records of numbers. `fuel` bounds the steps, so a
# recursive type, which never ends, is data.
def is_flat(fuel: Nat, todo: Maybe<&2, List<&2, String>>, +slots: List<&2, Slot>) -> Bool:
  match fuel todo:
    case _ None{}:
      False{}
    case _ Some{Nil{}}:
      True{}
    case 0n _:
      False{}
    case 1n+f Some{Con{+t, rest}}:
      is_flat(f, is_flat.next(is_scalar(t), t, rest, slots), slots)

# The first parameter of `params` that is data, if one is.
def data(
  params: List<&2, Param>,
  found: Maybe<&2, Param>,
  +slots: List<&2, Slot>
) -> Maybe<&2, Param>:
  match params found:
    case _ Some{param}:
      Some{param}
    case Nil{} None{}:
      None{}
    case Con{Param{n, +ty}, rest} None{}:
      data(rest, Lists.when(Param, Bool.not(is_flat(64n, Some{[ty]}, slots)), Param{n, ty}), slots)

def Def.forks(info: Maybe<&2, Def>) -> Bool:
  match info:
    case Some{Def{t, params, forks, calls, r}}:
      forks
    case None{}:
      False{}

# Where `text` writes `!(`, from offset `at`: the end of each bang's name.
def bangs(s: String, +at: U32, out: List<&2, U32>) -> List<&2, U32>:
  match s:
    case SNil{}:
      out
    case SCon{'!', SCon{'(', rest}}:
      bangs(rest, (at + 2: U32), at <> out)
    case SCon{c, rest}:
      bangs(rest, (at + 1: U32), out)

def alone(+callee: String) -> String:
  callee
    ++ "! runs on one GPU lane, alone: no parallel let runs under "
    ++ callee
    ++ ". GPU: measured 80x slower than without the `!` (a list walk of BendSR, RTX 4050 laptop). CPU (`--gpu off`): 1.6x slower. Confidence: high. Remove the `!`, or fork inside "
    ++ callee
    ++ " with a parallel let."

def slower(callee: String, param: Param) -> String:
  match param:
    case Param{name, +ty}:
      callee
        ++ "! receives data ("
        ++ name
        ++ Bool.pick(String, String.is_empty(ty), "", ": " ++ ty)
        ++ "), which a discrete GPU reads across PCIe, page by page. Discrete GPU (CUDA): slower than `--gpu off` for Bend's slash boss draw on an RTX 4050 laptop (1.4x), and for portal-bend on an RTX 4060 desktop. Unified memory (Apple M-series): the GPU wins that draw. Confidence: medium, as it depends on the machine. Time the program with and without `--gpu off`; where the GPU wins, expect this finding."

def faster(+callee: String) -> String:
  callee
    ++ " forks over numbers only, so `"
    ++ callee
    ++ "!(..)` can run faster on the GPU, if the call is long: a discrete GPU costs a fixed 0.3 to 0.8 s to start, then numeric work is nearly free. Measured on an RTX 4050 laptop: 3.8x faster for a fork tree that took 3.6 s on 20 CPU threads, 8x slower for one that took 0.06 s. Confidence: low, as it depends on how long this call runs and on the machine. Add the `!` if this call takes over a second on the CPU, and time both; if it is short, expect this finding."

def Def.target(info: Maybe<&2, Def>) -> String:
  match info:
    case Some{Def{t, params, forks, calls, r}}:
      t
    case None{}:
      ""

# The finding about a call of `info` without `!`, if it forks over numbers only and the caller does not
# fork.
def unbanged(
  info: Maybe<&2, Def>,
  callee: String,
  +caller: Maybe<&2, Def>,
  slots: List<&2, Slot>,
  span: Maybe<&2, Lint.Span>
) -> List<&2, Lint.Finding>:
  match info:
    case Some{Def{t, params, True{}, calls, r}}:
      Lint.finding(
        Lint.Hint{},
        Bool.not(
          Maybe.is_some(&2, Param, data(params, None{}, slots))
        )
          && Bool.not(Def.forks(caller))
          && Bool.not(String.eq(t, Def.target(caller))),
        span,
        faster(callee)
      )
    case _:
      []

# The finding about a `!` call: of a definition under which no parallel let runs (`forks` is false), or of one that
# forks and receives data (`param`).
def banged.of(
  forks: Bool,
  param: Maybe<&2, Param>,
  callee: String,
  span: Maybe<&2, Lint.Span>
) -> List<&2, Lint.Finding>:
  match forks param:
    case False{} _:
      Lint.finding(Lint.Warning{}, True{}, span, alone(callee))
    case True{} Some{p}:
      Lint.finding(Lint.Information{}, True{}, span, slower(callee, p))
    case True{} None{}:
      []

# The finding about a `!` call of a definition of the program (`info`), unless the call only frees (`drop`):
# performance/drop-in-bang reports that.
def banged(
  info: Maybe<&2, Def>,
  drop: Bool,
  callee: String,
  defs: Map<&2, Maybe<&2, Def>>,
  slots: List<&2, Slot>,
  span: Maybe<&2, Lint.Span>
) -> List<&2, Lint.Finding>:
  match info drop:
    case Some{Def{t, params, forks, calls, r}} False{}:
      banged.of(
        reaches(4096n, Some{[t]}, [], defs, True{}),
        data(params, None{}, slots),
        callee,
        span
      )
    case _ _:
      []

def judged(
  bang: Bool,
  info: Maybe<&2, Def>,
  drop: Bool,
  callee: String,
  caller: Maybe<&2, Def>,
  defs: Map<&2, Maybe<&2, Def>>,
  slots: List<&2, Slot>,
  span: Maybe<&2, Lint.Span>
) -> List<&2, Lint.Finding>:
  match bang:
    case True{}:
      banged(info, drop, callee, defs, slots, span)
    case False{}:
      unbanged(info, callee, caller, slots, span)

# The finding about an application below `path`, if its function is a definition of the program.
def visit(
  +program: Program,
  +path: List<&2, Lint.Above>,
  +node: Lint.Node
) -> List<&2, Lint.Finding>:
  match program node:
    case Program{
      +defs,
      slots,
      bangs
    } Lint.Node{
      Lint.Application{},
      n,
      span,
      Con{Lint.Node{Lint.Reference{t}, callee, Some{Lint.Span{p, beg, end}}, k, f}, args},
      facts
    }:
      judged(
        List.contains(~U32, ~U32.is_eq, bangs, end),
        Names.find(Def, defs, t),
        is_drop(Names.find(Def, defs, t), t),
        callee,
        Names.find(Def, defs, Lint.Node.target(Lint.top(path, node))),
        defs,
        slots,
        span
      )
    case _ _:
      []

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +sources = Lint.Here.sources(here)
  Lint.done(
    Lint.visit(
      ~Program,
      ~Lint.Finding,
      ~visit,
      Program{
        program.defs(sources, Map.new(&2, Maybe<&2, Def>)),
        program.slots(sources, []),
        bangs(Lint.Here.text(here), 0, [])
      },
      Lint.Here.nodes(here)
    )
  )

def rule() -> Lint.Rule:
  Lint.Rule{Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
