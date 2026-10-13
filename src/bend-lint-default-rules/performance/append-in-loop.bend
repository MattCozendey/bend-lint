# performance/append-in-loop: a loop that appends to its accumulator. A definition passes
# `List.append(.., acc, ..)` or `acc ++ ..` to a call of itself, where acc is one of its parameters.
# Heuristics: an append copies acc, so a loop of n steps copies O(n²) items, where adding at the head
# copies none. `++` copies only on the C lane: the JS lane joins strings natively. A loop that also
# keeps each value it builds, by passing acc in another argument too, needs the copies: it is not
# reported. It knows Base's List.append and String.append (`++`), not other functions that copy
# their first argument.
import Base
import ../../linter/lint.bend as Lint
import ../../shared/lists.bend as Lists

# Types
# =====

# A function that copies its first list or text to append to it.
type Append is Data:
  ListAppend{}
  StringAppend{}

# What judging the calls of a loop to itself reads: the loop's parameters, and the file's text.
type Loop is Data:
  Loop{params: List<&2, Lint.Node>, text: String}

# Functions
# =========

# The append that a call of `callee` with `count` arguments is.
def Append.of(+callee: String, +count: Nat) -> Maybe<&2, Append>:
  Bool.pick(
    Maybe<&2, Append>,
    String.eq(callee, "List.append") && Nat.is_eq(count, 4n),
    Some{ListAppend{}},
    Lists.when(Append, String.eq(callee, "String.append") && Nat.is_eq(count, 2n), StringAppend{})
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
  loop: String,
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

# Whether a variable the file writes, of the binder `b`, is among `nodes` or under them.
def has(nodes: List<&2, Lint.Node>, +b: U32) -> Bool:
  match nodes:
    case Nil{}:
      False{}
    case Con{Lint.Node{Lint.Variable{v}, n, Some{s}, k, f}, rest}:
      U32.is_eq(v, b) || has(rest, b)
    case Con{Lint.Node{syntax, n, s, kids, f}, rest}:
      has(kids, b) || has(rest, b)

def judged(
  kept: Bool,
  a: Append,
  name: String,
  acc: String,
  span: Lint.Span,
  text: String,
  args: List<&2, Lint.Node>
) -> List<&2, Lint.Finding>:
  match kept:
    case True{}:
      []
    case False{}:
      [Lint.Finding{Lint.Warning{}, span, Append.message(a, name, acc, text, args), []}]

# The finding about an append (`a`, at `span`, with `args`) to `acc`, if it is a parameter of the loop `name` that its
# call does not also use (in `others`, its nodes but the append): then it keeps each value the loop builds, and the
# copies are needed.
def accumulated(
  acc: Maybe<&2, Lint.Node>,
  a: Append,
  loop: Loop,
  name: String,
  span: Lint.Span,
  args: List<&2, Lint.Node>,
  others: List<&2, Lint.Node>
) -> List<&2, Lint.Finding>:
  match acc loop:
    case Some{Lint.Node{Lint.Variable{+b}, var, s, k, f}} Loop{params, text}:
      Bool.pick(
        List<&2, Lint.Finding>,
        Maybe.is_some(&2, Nat, Lint.parameter(params, b)),
        judged(has(others, b), a, name, var, span, text, args),
        []
      )
    case _ _:
      []

def appended(
  append: Maybe<&2, Append>,
  +args: List<&2, Lint.Node>,
  loop: Loop,
  name: String,
  span: Lint.Span,
  others: List<&2, Lint.Node>
) -> List<&2, Lint.Finding>:
  match append:
    case Some{+a}:
      accumulated(List.get(&2, Lint.Node, args, Append.at(a)), a, loop, name, span, args, others)
    case None{}:
      []

# The findings about the arguments of a call of the loop `name`, from the one numbered `at`; `nodes` are the call's.
def arguments(
  args: List<&2, Lint.Node>,
  +loop: Loop,
  +name: String,
  +nodes: List<&2, Lint.Node>,
  +at: Nat,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match args:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{
      Lint.Node{Lint.Application{}, n, Some{+span}, Con{Lint.Node{Lint.Reference{+callee}, rn, rs, rk, rf}, +parts}, f},
      rest
    }:
      arguments(
        rest,
        loop,
        name,
        nodes,
        1n+at,
        Lists.onto(
          &2,
          Lint.Finding,
          appended(
            Append.of(callee, Lists.length(&2, Lint.Node, parts)),
            parts,
            loop,
            name,
            span,
            Lists.append(&2, Lint.Node, List.take(&2, Lint.Node, nodes, 1n+at), List.drop(&2, Lint.Node, nodes, 2n+at))
          ),
          out
        )
      )
    case Con{arg, rest}:
      arguments(rest, loop, name, nodes, 1n+at, out)

def call.of(+loop: Loop, kids: List<&2, Lint.Node>, +nodes: List<&2, Lint.Node>) -> List<&2, Lint.Finding>:
  match kids:
    case Con{Lint.Node{s, name, sp, k, f}, args}:
      arguments(args, loop, name, nodes, 0n, [])
    case Nil{}:
      []

def call(+loop: Loop, node: Lint.Node) -> List<&2, Lint.Finding>:
  match node:
    case Lint.Node{s, n, sp, +kids, f}:
      call.of(loop, kids, kids)

def calls(recursive: Bool, +loop: Loop, node: Lint.Node) -> List<&2, Lint.Finding>:
  match recursive:
    case True{}:
      call(loop, node)
    case False{}:
      []

def visit(+loop: Loop, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, Lint.Finding>:
  calls(Lint.recursive(path, node), loop, node)

def defs(nodes: List<&2, Lint.Node>, +text: String, out: List<&2, Lint.Finding>) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Node{Lint.Definition{+t, +u}, +n, +s, +k, +f}, rest}:
      defs(
        rest,
        text,
        Lists.onto(
          &2,
          Lint.Finding,
          Lint.visit(~Loop, ~Lint.Finding, ~visit, Loop{k, text}, [Lint.Node{Lint.Definition{t, u}, n, s, k, f}]),
          out
        )
      )
    case Con{node, rest}:
      defs(rest, text, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(defs(Lint.Here.nodes(here), Lint.Here.text(here), []))

def rule() -> Lint.Rule:
  Lint.Rule{"performance/append-in-loop", Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
