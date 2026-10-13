# performance/gpu-fit: a call that may run faster on the other side of the GPU: a `!` call (it runs on the
# GPU, if there is one) whose definition receives data, not only numbers; or a call of a definition that
# forks over numbers only, made without `!`, from a definition that does not fork.
# Heuristics: measured on an RTX 4050 laptop GPU against its CPU (`--gpu off`, Bend 2.0.36): a GPU is
# fast on uniform numeric work (a 16,384-leaf numeric fork tree: 0.54 s against 0.95 s) and slow at
# walking data (a tree walk: 2.7x slower; Bend's slash boss draw: 30% slower; its parallel sort: 4.6x
# slower), and it costs about 0.5 s to start, so short work is slower there. Numbers are U32, I32, F32,
# Nat, Bool, Char (and their 64-bit forms), and a record of numbers only, defined in the program's
# files; anything else is data. Erased and template parameters do not count. On unified memory (Apple
# M-series) the GPU's costs differ.
import Base
import ../../linter/lint.bend as Lint
import ../../shared/lists.bend as Lists
import ../../shared/names.bend as Names

# Types
# =====

# A field of a datatype: the datatype, and the field's type as one name ("" if it is not one name).
type Slot is Data:
  Slot{owner: String, ty: String}

# A runtime parameter of a definition: its name, and its type as one name ("" if it is not one name).
type Param is Data:
  Param{name: String, ty: String}

# A definition of the program: its name as the check names it, its runtime parameters, whether it forks.
type Def is Data:
  Def{target: String, params: List<&2, Param>, forks: Bool}

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
def runtime(quantity: Lint.Quantity) -> Bool:
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
    case Con{Lint.Node{Lint.Parameter{b, +q}, n, s, kids, f}, rest}:
      params(rest, Lists.push(Param, Lists.when(Param, runtime(q), Param{n, plain(kids)}), out))
    case Con{node, rest}:
      params(rest, out)

# Whether a parallel let (two binders, at least) is among `nodes` or under them.
def forks(nodes: List<&2, Lint.Node>) -> Bool:
  match nodes:
    case Nil{}:
      False{}
    case Con{
      Lint.Node{
        Lint.Destructure{q},
        n,
        s,
        Con{Lint.Node{Lint.PatternVariable{a, aq}, an, as, ak, af}, Con{Lint.Node{Lint.PatternVariable{b, bq}, bn, bs, bk, bf}, more}},
        f
      },
      rest
    }:
      True{}
    case Con{Lint.Node{syntax, n, s, kids, f}, rest}:
      forks(kids) || forks(rest)

# The definitions among a file's nodes, by the name the check gives them, onto `out`.
def defs(nodes: List<&2, Lint.Node>, out: Map<&2, Maybe<&2, Def>>) -> Map<&2, Maybe<&2, Def>>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{Lint.Definition{+t, u}, n, s, +kids, f}, rest}:
      defs(rest, Map.set(&2, Maybe<&2, Def>, out, t, Some{Def{t, params(kids, []), forks(kids)}}))
    case Con{node, rest}:
      defs(rest, out)

def program.slots(sources: List<&2, Lint.Source>, out: List<&2, Slot>) -> List<&2, Slot>:
  match sources:
    case Nil{}:
      out
    case Con{Lint.Source{path, ns, text, nodes}, rest}:
      program.slots(rest, slots(nodes, "", out))

def program.defs(sources: List<&2, Lint.Source>, out: Map<&2, Maybe<&2, Def>>) -> Map<&2, Maybe<&2, Def>>:
  match sources:
    case Nil{}:
      out
    case Con{Lint.Source{path, ns, text, nodes}, rest}:
      program.defs(rest, defs(nodes, out))

def scalar(t: String) -> Bool:
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

def known(slots: List<&2, Slot>, hit: Bool, +t: String) -> Bool:
  match slots hit:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{Slot{o, ty}, rest} False{}:
      known(rest, String.eq(o, t), t)

def flat.expand(
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
def flat.next(
  number: Bool,
  +t: String,
  rest: List<&2, String>,
  +slots: List<&2, Slot>
) -> Maybe<&2, List<&2, String>>:
  match number:
    case True{}:
      Some{rest}
    case False{}:
      flat.expand(known(slots, False{}, t), t, rest, slots)

# Whether the types of `todo` are numbers, or records of numbers. `fuel` bounds the steps, so a
# recursive type, which never ends, is data.
def flat(fuel: Nat, todo: Maybe<&2, List<&2, String>>, +slots: List<&2, Slot>) -> Bool:
  match fuel todo:
    case _ None{}:
      False{}
    case _ Some{Nil{}}:
      True{}
    case 0n _:
      False{}
    case 1n+f Some{Con{+t, rest}}:
      flat(f, flat.next(scalar(t), t, rest, slots), slots)

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
      data(rest, Lists.when(Param, Bool.not(flat(64n, Some{[ty]}, slots)), Param{n, ty}), slots)

def Def.forks(info: Maybe<&2, Def>) -> Bool:
  match info:
    case Some{Def{t, params, forks}}:
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

def slower(callee: String, param: Param) -> String:
  match param:
    case Param{name, +ty}:
      callee
        ++ "! runs on the GPU, if there is one, and receives data ("
        ++ name
        ++ Bool.pick(String, String.is_empty(ty), "", ": " ++ ty)
        ++ "), not only numbers. A GPU is fast on uniform numeric work but slow at walking data, and a discrete GPU (CUDA) also pays for each page of that data it reads from the CPU's memory. Measured against `--gpu off` on an RTX 4050 laptop GPU: the draw of Bend's slash boss demo took 30% longer on the GPU, its parallel sort 4.6x longer, a tree walk 2.7x longer. Time the program with and without `--gpu off` (or this call without its `!`), and keep the faster. On unified memory (Apple M-series), the GPU can still win."

def faster(+callee: String) -> String:
  callee
    ++ " forks over numbers only, so `"
    ++ callee
    ++ "!(..)` would run it on the GPU, if there is one, where uniform numeric work can be faster: measured on an RTX 4050 laptop GPU, a numeric fork tree of 16,384 leaves took 0.54 s against 0.95 s on its CPU. A GPU also costs time to start (about 0.5 s there), so short work gets slower: the parallel sum of Bend's demos took 0.83 s against 0.13 s. Time both, and keep the faster."

def Def.target(info: Maybe<&2, Def>) -> String:
  match info:
    case Some{Def{t, params, forks}}:
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
    case Some{Def{t, params, True{}}}:
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

def banged.data(
  param: Maybe<&2, Param>,
  callee: String,
  span: Maybe<&2, Lint.Span>
) -> List<&2, Lint.Finding>:
  match param:
    case Some{p}:
      Lint.finding(Lint.Information{}, True{}, span, slower(callee, p))
    case None{}:
      []

def banged(
  info: Maybe<&2, Def>,
  callee: String,
  slots: List<&2, Slot>,
  span: Maybe<&2, Lint.Span>
) -> List<&2, Lint.Finding>:
  match info:
    case Some{Def{t, params, forks}}:
      banged.data(data(params, None{}, slots), callee, span)
    case None{}:
      []

def judged(
  bang: Bool,
  info: Maybe<&2, Def>,
  callee: String,
  caller: Maybe<&2, Def>,
  slots: List<&2, Slot>,
  span: Maybe<&2, Lint.Span>
) -> List<&2, Lint.Finding>:
  match bang:
    case True{}:
      banged(info, callee, slots, span)
    case False{}:
      unbanged(info, callee, caller, slots, span)

# The finding about an application below `path`, if its function is a definition of the program.
def visit(+program: Program, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, Lint.Finding>:
  match program node:
    case Program{defs, slots, bangs} Lint.Node{
      Lint.Application{},
      n,
      span,
      Con{Lint.Node{Lint.Reference{t}, callee, Some{Lint.Span{p, beg, end}}, k, f}, args},
      facts
    }:
      judged(
        List.contains(~U32, ~U32.is_eq, bangs, end),
        Names.find(Def, defs, t),
        callee,
        Names.find(Def, defs, Lint.Node.target(Lint.top(path, node))),
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
  Lint.Rule{"performance/gpu-fit", Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
