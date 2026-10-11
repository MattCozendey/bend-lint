# performance/append-in-loop: a loop that appends to its accumulator. A definition passes
# `List.append(.., acc, ..)` or `acc ++ ..` to a call of itself, where acc is one of its parameters.
# Heuristics: an append copies acc, so a loop of n steps copies O(n²) items, where adding at the head
# copies none. `++` copies only on the C lane: the JS lane joins strings natively. A loop that also
# keeps each value it builds, by passing acc in another argument too, needs the copies: it is not
# reported. It knows Base's List.append and String.append (`++`), not other functions that copy
# their first argument.
import Base
import ../../lint.bend as Lint
import ../../shared.bend as Shared

# Types
# =====

# A function that copies its first list or text to append to it.
type Append is Data:
  ListAppend{}
  StringAppend{}

# A call of a loop to itself: the loop's name, as written, and where the call starts and ends.
type Loop is Data:
  Loop{name: String, beg: U32, end: U32}

# A variable: its binder, and where it starts.
type Use is Data:
  Use{binder: U32, at: U32}

# Functions
# =========

# The append that a call of `callee` with `count` arguments is.
def Append.of(+callee: String, +count: Nat) -> Maybe<&2, Append>:
  Bool.pick(
    Maybe<&2, Append>,
    String.eq(callee, "List.append") && Nat.is_eq(count, 4n),
    Some{ListAppend{}},
    Shared.when(Append, String.eq(callee, "String.append") && Nat.is_eq(count, 2n), StringAppend{})
  )

# Which argument an append copies.
def Append.at(a: Append) -> Nat:
  match a:
    case ListAppend{}:
      2n
    case StringAppend{}:
      0n

# What a finding says about an append of `acc` in the loop `loop`. `args` are the append's arguments.
def Append.message(
  a: Append,
  +loop: String,
  +acc: String,
  +source: String,
  +args: List<&2, Lint.Node>
) -> String:
  match a:
    case ListAppend{}:
      "List.append copies "
        ++ acc
        ++ " on each call of "
        ++ loop
        ++ ", so a loop of n steps copies O(n²) items. Add each item at the head instead, with `item <> "
        ++ acc
        ++ "`, and reverse "
        ++ acc
        ++ " once when the loop ends: `List.reverse("
        ++ Lint.Span.text(source, Lint.Node.span(List.get(&2, Lint.Node, args, 0n)))
        ++ ", "
        ++ Lint.Span.text(source, Lint.Node.span(List.get(&2, Lint.Node, args, 1n)))
        ++ ", "
        ++ acc
        ++ ")`."
    case StringAppend{}:
      "On the C lane, ++ copies "
        ++ acc
        ++ " on each call of "
        ++ loop
        ++ ", so a loop of n steps copies O(n²) characters (the JS lane joins strings natively). Collect the pieces in a list instead, with `piece <> pieces`, and join them once when the loop ends: `String.concat(List.reverse(&2, String, pieces))`."

# Whether `nodes`, a definition's children, hold a parameter that declares the binder `binder`.
def parameter(nodes: List<&2, Lint.Node>, +binder: U32) -> Bool:
  match nodes:
    case Nil{}:
      False{}
    case Con{Lint.Node{i, p, o, Lint.Parameter{}, n, Some{b}, q, s, t}, rest}:
      U32.is_eq(b, binder) || parameter(rest, binder)
    case Con{node, rest}:
      parameter(rest, binder)

def Use.all(nodes: List<&2, Lint.Node>, out: List<&2, Use>) -> List<&2, Use>:
  match nodes:
    case Nil{}:
      out
    case Con{
      Lint.Node{i, p, o, Lint.Variable{}, n, Some{b}, q, Some{Lint.Span{path, at, end}}, t},
      rest
    }:
      Use.all(rest, Use{b, at} <> out)
    case Con{node, rest}:
      Use.all(rest, out)

def Loop.holds(loop: Loop, +at: U32) -> Bool:
  match loop:
    case Loop{name, beg, end}:
      U32.is_ge(at, beg) && U32.is_lt(at, end)

def Span.holds(span: Lint.Span, +at: U32) -> Bool:
  match span:
    case Lint.Span{path, beg, end}:
      U32.is_ge(at, beg) && U32.is_lt(at, end)

# Whether the call of the loop uses `binder` outside the append: then it keeps each value the loop
# builds, and the copies are needed.
def kept(us: List<&2, Use>, +binder: U32, +loop: Loop, +span: Lint.Span) -> Bool:
  match us:
    case Nil{}:
      False{}
    case Con{Use{b, +at}, rest}:
      (
        U32.is_eq(b, binder) && Loop.holds(loop, at) && Bool.not(Span.holds(span, at))
      )
        || kept(rest, binder, loop, span)

def Loop.name(loop: Loop) -> String:
  match loop:
    case Loop{name, beg, end}:
      name

# The finding about `acc`, the argument an append copies, if it is a parameter of the loop that the
# loop's call does not also keep.
def found(
  acc: Maybe<&2, Lint.Node>,
  a: Append,
  +loop: Loop,
  +owner: U32,
  +span: Lint.Span,
  +args: List<&2, Lint.Node>,
  +here: Lint.Here,
  +children: Lint.Children,
  +us: List<&2, Use>
) -> List<&2, Lint.Finding>:
  match acc:
    case Some{Lint.Node{i, p, o, Lint.Variable{}, +name, Some{+b}, q, s, t}}:
      Bool.pick(
        List<&2, Lint.Finding>,
        parameter(Lint.Children.get(children, owner), b) && Bool.not(kept(us, b, loop, span)),
        [
          Lint.Finding{
            Lint.Warning{},
            span,
            Append.message(a, Loop.name(loop), name, Lint.Here.text(here), args),
            []
          }
        ],
        []
      )
    case _:
      []

def appended(
  append: Maybe<&2, Append>,
  +args: List<&2, Lint.Node>,
  +loop: Loop,
  +owner: U32,
  +span: Lint.Span,
  +here: Lint.Here,
  +children: Lint.Children,
  +us: List<&2, Use>
) -> List<&2, Lint.Finding>:
  match append:
    case Some{+a}:
      found(
        List.get(&2, Lint.Node, args, Append.at(a)),
        a,
        loop,
        owner,
        span,
        args,
        here,
        children,
        us
      )
    case None{}:
      []

# The finding about `call`'s children, if `call` is an append to a parameter of the loop.
def call(
  nodes: List<&2, Lint.Node>,
  +loop: Loop,
  +owner: U32,
  +span: Lint.Span,
  +here: Lint.Here,
  +children: Lint.Children,
  +us: List<&2, Use>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Con{Lint.Node{i, p, o, Lint.Reference{}, n, b, q, s, +callee}, +args}:
      appended(
        Append.of(callee, Shared.length(&2, Lint.Node, args)),
        args,
        loop,
        owner,
        span,
        here,
        children,
        us
      )
    case _:
      []

# The findings about the arguments of a call of the loop `loop`.
def arguments(
  args: List<&2, Lint.Node>,
  +loop: Loop,
  +here: Lint.Here,
  +children: Lint.Children,
  +us: List<&2, Use>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match args:
    case Nil{}:
      out
    case Con{Lint.Node{id, p, owner, Lint.Application{}, n, b, q, Some{span}, t}, rest}:
      arguments(
        rest,
        loop,
        here,
        children,
        us,
        Shared.onto(
          &2,
          Lint.Finding,
          call(Lint.Children.get(children, id), loop, owner, span, here, children, us),
          out
        )
      )
    case Con{arg, rest}:
      arguments(rest, loop, here, children, us, out)

# The findings about a call of the loop, whose children are `nodes` and which spans `beg` to `end`.
def step(
  nodes: List<&2, Lint.Node>,
  beg: U32,
  end: U32,
  +here: Lint.Here,
  +children: Lint.Children,
  +us: List<&2, Use>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Con{Lint.Node{i, p, o, s, loop, b, q, sp, t}, args}:
      arguments(args, Loop{loop, beg, end}, here, children, us, out)
    case Nil{}:
      out

def visit(
  recursive: Bool,
  node: Lint.Node,
  +here: Lint.Here,
  +children: Lint.Children,
  +us: List<&2, Use>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match recursive node:
    case True{} Lint.Node{id, p, o, s, n, b, q, Some{Lint.Span{path, beg, end}}, t}:
      step(Lint.Children.get(children, id), beg, end, here, children, us, out)
    case _ _:
      out

def scan(
  nodes: List<&2, Lint.Node>,
  +here: Lint.Here,
  +children: Lint.Children,
  +us: List<&2, Use>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{+node, rest}:
      scan(
        rest,
        here,
        children,
        us,
        visit(Lint.Here.recursive(here, children, node), node, here, children, us, out)
      )

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +nodes = Lint.Here.nodes(here)
  Lint.done(scan(nodes, here, Lint.Children.of(nodes), Use.all(nodes, []), []))

def rule() -> Lint.Rule:
  Lint.Rule{"performance/append-in-loop", Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
