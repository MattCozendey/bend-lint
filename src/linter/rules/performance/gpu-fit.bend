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
import ../../../shared/utils.bend as Utils
import ../../lint.bend as Lint
import ../../shared/utils.bend as LintUtils

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

# The definition being read: its node's id, and what is known of it so far.
type Open is Data:
  Open{id: U32, info: Def}

# Functions
# =========

# A type node as one name, or "" for another form (an application, a list).
def plain(node: Lint.Node) -> String:
  match node:
    case Lint.Node{i, p, o, Lint.Reference{}, n, b, q, s, t}:
      t
    case _:
      ""

def Slot.scan(nodes: List<&2, Lint.Node>, +current: String, out: List<&2, Slot>) -> List<&2, Slot>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{i, p, o, Lint.Datatype{}, n, b, q, s, t}, rest}:
      Slot.scan(rest, t, out)
    case Con{Lint.Node{i, p, o, Lint.Field{}, n, b, q, s, t}, Con{ty, rest}}:
      Slot.scan(rest, current, Slot{current, plain(ty)} <> out)
    case Con{node, rest}:
      Slot.scan(rest, current, out)

# Whether a parameter of this quantity is there at run time.
def runtime(quantity: Maybe<&2, Lint.Quantity>) -> Bool:
  match quantity:
    case Some{Lint.Erased{}}:
      False{}
    case Some{Lint.Template{}}:
      False{}
    case _:
      True{}

def Open.close(current: Maybe<&2, Open>, out: Map<&2, Maybe<&2, Def>>) -> Map<&2, Maybe<&2, Def>>:
  match current:
    case Some{Open{i, Def{+t, params, forks}}}:
      Map.set(&2, Maybe<&2, Def>, out, t, Some{Def{t, List.reverse(&2, Param, params), forks}})
    case None{}:
      out

def Open.param(current: Maybe<&2, Open>, parent: U32, keep: Bool, param: Param) -> Maybe<&2, Open>:
  match current keep:
    case Some{Open{+i, Def{t, params, forks}}} True{}:
      Some{
        Open{
          i,
          Def{t, Utils.push(Param, Utils.when(Param, U32.is_eq(i, parent), param), params), forks}
        }
      }
    case other _:
      other

def Open.fork(current: Maybe<&2, Open>, hit: Bool) -> Maybe<&2, Open>:
  match current hit:
    case Some{Open{i, Def{t, params, forks}}} True{}:
      Some{Open{i, Def{t, params, True{}}}}
    case other _:
      other

# The definitions of one file's nodes, by the name the check gives them, onto `out`. A definition's
# nodes come right after it, until the next node at the top.
def Def.scan(
  nodes: List<&2, Lint.Node>,
  current: Maybe<&2, Open>,
  out: Map<&2, Maybe<&2, Def>>
) -> Map<&2, Maybe<&2, Def>>:
  match nodes:
    case Nil{}:
      Open.close(current, out)
    case Con{Lint.Node{i, p, o, Lint.Definition{}, n, b, q, s, t}, rest}:
      Def.scan(rest, Some{Open{i, Def{t, [], False{}}}}, Open.close(current, out))
    case Con{Lint.Node{i, p, o, Lint.Parameter{}, n, b, q, s, t}, Con{ty, rest}}:
      Def.scan(rest, Open.param(current, p, runtime(q), Param{n, plain(ty)}), out)
    case Con{
      Lint.Node{+i, p, o, Lint.Destructure{}, n, b, q, s, t},
      Con{
        Lint.Node{i2, p2, o2, Lint.PatternVariable{}, n2, b2, q2, s2, t2},
        Con{Lint.Node{i3, p3, o3, Lint.PatternVariable{}, n3, b3, q3, s3, t3}, rest}
      }
    }:
      Def.scan(rest, Open.fork(current, U32.is_eq(p2, i) && U32.is_eq(p3, i)), out)
    case Con{node, rest}:
      Def.scan(rest, current, out)

def program.slots(sources: List<&2, Lint.Source>, out: List<&2, Slot>) -> List<&2, Slot>:
  match sources:
    case Nil{}:
      out
    case Con{Lint.Source{path, ns, text, nodes, facts}, rest}:
      program.slots(rest, Slot.scan(nodes, "", out))

def program.defs(
  sources: List<&2, Lint.Source>,
  out: Map<&2, Maybe<&2, Def>>
) -> Map<&2, Maybe<&2, Def>>:
  match sources:
    case Nil{}:
      out
    case Con{Lint.Source{path, ns, text, nodes, facts}, rest}:
      program.defs(rest, Def.scan(nodes, None{}, out))

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
      fields(rest, t, Utils.push(String, Utils.when(String, String.eq(o, t), ty), out))

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
      data(rest, Utils.when(Param, Bool.not(flat(64n, Some{[ty]}, slots)), Param{n, ty}), slots)

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
      LintUtils.finding(
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
      LintUtils.finding(Lint.Information{}, True{}, span, slower(callee, p))
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

# The finding about the application `node`, whose function is `callee`.
def call(
  callee: Maybe<&2, Lint.Node>,
  owner: U32,
  span: Maybe<&2, Lint.Span>,
  here: Lint.Here,
  +defs: Map<&2, Maybe<&2, Def>>,
  slots: List<&2, Slot>,
  bangs: List<&2, U32>
) -> List<&2, Lint.Finding>:
  match callee:
    case Some{Lint.Node{i, p, o, Lint.Reference{}, n, b, q, Some{Lint.Span{path, beg, end}}, t}}:
      judged(
        List.contains(~U32, ~U32.is_eq, bangs, end),
        Utils.find(Def, defs, t),
        n,
        Utils.find(Def, defs, Lint.Node.target(Lint.Here.node(here, owner))),
        slots,
        span
      )
    case _:
      []

def scan(
  nodes: List<&2, Lint.Node>,
  +here: Lint.Here,
  +defs: Map<&2, Maybe<&2, Def>>,
  +slots: List<&2, Slot>,
  +bangs: List<&2, U32>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Node{i, p, o, Lint.Application{}, n, b, q, span, t}, rest}:
      scan(
        rest,
        here,
        defs,
        slots,
        bangs,
        Utils.onto(
          &2,
          Lint.Finding,
          call(Lint.Here.node(here, (i + 1: U32)), o, span, here, defs, slots, bangs),
          out
        )
      )
    case Con{node, rest}:
      scan(rest, here, defs, slots, bangs, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +sources = Lint.Here.sources(here)
  Lint.done(
    scan(
      Lint.Here.nodes(here),
      here,
      program.defs(sources, Map.new(&2, Maybe<&2, Def>)),
      program.slots(sources, []),
      bangs(Lint.Here.text(here), 0, []),
      []
    )
  )

def rule() -> Lint.Rule:
  Lint.Rule{"performance/gpu-fit", Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
