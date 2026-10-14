# performance/missed-fork: calls of a definition to itself that could run in parallel, but run one after
# the other: two or more in one expression (`f(x) + f(y)`, `Node{f(x), f(y)}`), or in lets that follow
# each other (`l = f(x)`, then `r = f(y)`), where no call uses the result of another.
# Heuristics: Bend forks only the values of a parallel let (`a b = f(x) f(y)`), and its calls are
# independent, as Bend is pure. Whether a fork pays depends on how much work each call does, which the
# rule cannot see: measured on the CPU, forking a walk of a 1M-leaf tree, called 10 times, made it 2.5x
# faster; forking the same walk of 1k-leaf trees, called 100,000 times in a loop, made it 3.9x slower;
# forking a small expression tree that BendSR evaluates once per data point made it 230x slower. The JS
# lane runs on one thread, so it does not gain. Calls in different values of Bool.pick, or on the two
# sides of `&&` or `||`, are alternatives, not both needed (see performance/eager-branch): they do not
# count together. Calls written the same way compute the same value, so they are left to
# performance/repeated-call, which asks to compute it once (pow2(30): 0.1 s, against 0.6 s forked). It
# skips a definition that returns IO: its calls build effects, they do not run them. A call inside
# another call of itself, inside a lambda, or in a type, does not count.
import Base
import ../../src/linter/lint.bend as Lint
import ../../src/shared/lists.bend as Lists
import ../../src/shared/strings.bend as Strings

# Types
# =====

# What judging one definition reads: its name as the check names it and as written, whether it returns IO (its calls
# build effects, they do not run them), and the file's text.
type Owner is Data:
  Owner{target: String, name: String, io: Bool, text: String}

# A let that binds one name to a call of its definition to itself: where its binder starts, the binder as written, the
# binder, and the call.
type Bound is Data:
  Bound{from: U32, written: String, binder: U32, call: Lint.Node}

# The lets of a run so far (last first), their binders, and the findings so far (last first).
type Run is Data:
  Run{bounds: List<&2, Bound>, binders: List<&2, U32>, out: List<&2, Lint.Finding>}

# Functions
# =========
def trim.go(cs: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Con{' ', rest}:
      trim.go(rest)
    case _:
      cs

def trimmed(s: String) -> String:
  String.from_list(List.reverse(&2, Char, trim.go(List.reverse(&2, Char, String.to_list(s)))))

# Whether an application's nodes call Bool.pick, Bool.and or Bool.or: its arguments are alternatives, each an
# expression of its own.
def is_choice(kids: List<&2, Lint.Node>) -> Bool:
  match kids:
    case Con{Lint.Node{Lint.Reference{t}, n, s, k, f}, rest}:
      List.contains(~String, ~String.eq, ["Bool.pick", "Bool.and", "Bool.or"], t)
    case _:
      False{}

# Whether a node of this syntax ends the expression a call is in.
def is_boundary(syntax: Lint.Syntax) -> Bool:
  match syntax:
    case Lint.Application{}:
      False{}
    case Lint.Construction{t}:
      False{}
    case Lint.Annotation{}:
      False{}
    case _:
      True{}

# Whether a definition's nodes say it returns IO, as written.
def returns_io(nodes: List<&2, Lint.Node>) -> Bool:
  match nodes:
    case Nil{}:
      False{}
    case Con{
      Lint.Node{Lint.Returns{}, n, s, Con{Lint.Node{Lint.Reference{t}, rn, rs, rk, rf}, k}, f},
      rest
    }:
      String.eq(t, "IO")
    case Con{
      Lint.Node{
        Lint.Returns{},
        n,
        s,
        Con{
          Lint.Node{
            Lint.Application{},
            an,
            as,
            Con{Lint.Node{Lint.Reference{t}, rn, rs, rk, rf}, ak},
            af
          },
          k
        },
        f
      },
      rest
    }:
      String.eq(t, "IO")
    case Con{node, rest}:
      returns_io(rest)

# Whether an application's nodes call `target`: its function is a reference to it.
def calls.to(kids: List<&2, Lint.Node>, target: String) -> Bool:
  match kids:
    case Con{Lint.Node{Lint.Reference{t}, n, s, k, f}, rest}:
      String.eq(t, target)
    case _:
      False{}

# `out` with the span of a call of `target` (if `call`), where the call is.
def called.at(
  call: Bool,
  span: Maybe<&2, Lint.Span>,
  out: List<&2, Lint.Span>
) -> List<&2, Lint.Span>:
  match call:
    case True{}:
      Lists.push(Lint.Span, span, out)
    case False{}:
      out

# Where the calls of `target` among `nodes` and under them are (onto `out`, last first), in the expression they start:
# a node that ends it starts another, and so does each argument of a choice (Bool.pick, Bool.and, Bool.or); a call
# inside another call of `target` does not count: none does if `nodes` are the parts of one, or of a choice (`inside`).
def calls(
  nodes: List<&2, Lint.Node>,
  +target: String,
  out: List<&2, Lint.Span>,
  inside: Bool
) -> List<&2, Lint.Span>:
  match nodes inside:
    case _ True{}:
      out
    case Nil{} False{}:
      out
    case Con{Lint.Node{Lint.Application{}, n, span, +kids, f}, rest} False{}:
      +call = calls.to(kids, target)
      calls(
        rest,
        target,
        calls(kids, target, called.at(call, span, out), call || is_choice(kids)),
        False{}
      )
    case Con{Lint.Node{Lint.Construction{t}, n, s, kids, f}, rest} False{}:
      calls(rest, target, calls(kids, target, out, False{}), False{})
    case Con{Lint.Node{Lint.Annotation{}, n, s, kids, f}, rest} False{}:
      calls(rest, target, calls(kids, target, out, False{}), False{})
    case Con{node, rest} False{}:
      calls(rest, target, out, False{})

def texts(spans: List<&2, Lint.Span>, +text: String, out: List<&2, String>) -> List<&2, String>:
  match spans:
    case Nil{}:
      out
    case Con{s, rest}:
      texts(rest, text, Lint.Span.text(text, Some{s}) <> out)

def names() -> List<&2, String>:
  ["a", "b", "c", "d", "e", "g", "h", "k"]

# Fresh names for `n` values, as a parallel let binds them.
def binders(
  texts: List<&2, String>,
  ns: List<&2, String>,
  out: List<&2, String>
) -> List<&2, String>:
  match texts ns:
    case Con{t, rest} Con{n, more}:
      binders(rest, more, n <> out)
    case Con{t, rest} Nil{}:
      binders(rest, [], "x" <> out)
    case Nil{} _:
      List.reverse(&2, String, out)

def quoted(texts: List<&2, String>, out: List<&2, String>) -> List<&2, String>:
  match texts:
    case Nil{}:
      List.reverse(&2, String, out)
    case Con{t, rest}:
      quoted(rest, ("`" ++ t ++ "`") <> out)

def costs() -> String:
  "Bend runs calls in parallel only as the values of a parallel let. CPU, and GPU under a `!`: measured 2.5x faster for a few calls over a 1M-leaf tree, but 3.9x slower for 100,000 calls over 1k-leaf trees, and 230x slower for a small tree walked once per data point. JS: one thread, so no gain. Confidence: low, as it depends on how much work each call does."

def expected() -> String:
  " If this definition runs once per item of a loop, or below a fork that already fills the cores, expect this finding."

def count(texts: List<&2, String>) -> String:
  U32.show(U32.from_nat(Lists.length(&2, String, texts)))

def Call.message(loop: String, +texts: List<&2, String>) -> String:
  loop
    ++ " calls itself "
    ++ count(texts)
    ++ " times in this expression ("
    ++ String.join(quoted(texts, []), ", ")
    ++ "), and these calls run one after the other. "
    ++ costs()
    ++ " To run them in parallel, bind them first with one parallel let of fresh names, such as `"
    ++ String.join(binders(texts, names(), []), " ")
    ++ " = "
    ++ String.join(texts, " ")
    ++ "`, and use those names here."
    ++ expected()

# The finding about an expression at `span` that holds the calls at `spans` (last first), if they are two or more.
def alike.go(texts: List<&2, String>, +first: String, ok: Bool) -> Bool:
  match texts ok:
    case _ False{}:
      False{}
    case Nil{} True{}:
      True{}
    case Con{t, rest} True{}:
      alike.go(rest, first, String.eq(t, first))

# Whether `texts`, the calls of one finding, are all written the same way.
def is_alike(texts: List<&2, String>) -> Bool:
  match texts:
    case Con{t, rest}:
      alike.go(rest, t, True{})
    case Nil{}:
      True{}

def Call.finding.of(
  many: Bool,
  +spans: List<&2, Lint.Span>,
  span: Maybe<&2, Lint.Span>,
  +owner: Owner
) -> List<&2, Lint.Finding>:
  match many owner:
    case True{} Owner{target, name, io, +text}:
      Lint.finding(
        Lint.Hint{},
        Bool.not(is_alike(texts(spans, text, []))),
        span,
        Call.message(name, texts(spans, text, []))
      )
    case _ _:
      []

def Call.finding(
  +spans: List<&2, Lint.Span>,
  span: Maybe<&2, Lint.Span>,
  owner: Owner
) -> List<&2, Lint.Finding>:
  Call.finding.of(Nat.is_gt(Lists.length(&2, Lint.Span, spans), 1n), spans, span, owner)

# Whether the node below `path` starts an expression: the node above it ends one, or is a choice.
def starts(path: List<&2, Lint.Above>) -> Bool:
  match path:
    case Nil{}:
      True{}
    case Con{Lint.Above{Lint.Node{Lint.Application{}, n, s, kids, f}, at}, rest}:
      is_choice(kids)
    case Con{Lint.Above{Lint.Node{syntax, n, s, k, f}, at}, rest}:
      is_boundary(syntax)

# The call of a let's value, if the value is a call of `target`, typed or not.
def called(value: Lint.Node, target: String) -> Maybe<&2, Lint.Node>:
  match value:
    case Lint.Node{Lint.Application{}, n, s, +kids, f}:
      Lists.when(Lint.Node, calls.to(kids, target), Lint.Node{Lint.Application{}, n, s, kids, f})
    case Lint.Node{
      Lint.Annotation{},
      n,
      s,
      Con{Lint.Node{Lint.Application{}, cn, cs, +kids, cf}, k},
      f
    }:
      Lists.when(Lint.Node, calls.to(kids, target), Lint.Node{Lint.Application{}, cn, cs, kids, cf})
    case _:
      None{}

# A let that binds one name to a call of `target`, if `node` is one.
def bound(+node: Lint.Node, +owner: Owner) -> Maybe<&2, Bound>:
  match node owner:
    case Lint.Node{
      Lint.Destructure{q},
      n,
      s,
      Con{
        Lint.Node{Lint.PatternVariable{b, pq}, pn, Some{Lint.Span{p, +from, end}}, pk, pf},
        Con{value, Con{rest, Nil{}}}
      },
      f
    } Owner{target, name, io, text}:
      Maybe.map(
        &2,
        Lint.Node,
        Bound,
        call => Bound{from, trimmed(Strings.slice(text, from, end)), b, call},
        called(value, target)
      )
    case _ _:
      None{}

# Whether a variable the file writes, of one of `binders`, is among `nodes` or under them, or `found`.
def uses(nodes: List<&2, Lint.Node>, +binders: List<&2, U32>, found: Bool) -> Bool:
  match nodes found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{Lint.Node{Lint.Variable{v}, n, Some{s}, k, f}, rest} False{}:
      uses(rest, binders, List.contains(~U32, ~U32.is_eq, binders, v))
    case Con{Lint.Node{syntax, n, s, kids, f}, rest} False{}:
      uses(rest, binders, uses(kids, binders, False{}))

def Bound.texts(
  bounds: List<&2, Bound>,
  +text: String,
  written: List<&2, String>,
  called: List<&2, String>
) -> List<&2, String>
  & List<&2, String>:
  match bounds:
    case Nil{}:
      (written, called)
    case Con{Bound{f, w, b, Lint.Node{s, n, span, k, fs}}, rest}:
      Bound.texts(rest, text, w <> written, Lint.Span.text(text, span) <> called)

def Run.lets(
  written: List<&2, String>,
  called: List<&2, String>,
  out: List<&2, String>
) -> List<&2, String>:
  match written called:
    case Con{w, rest} Con{c, more}:
      Run.lets(rest, more, ("`" ++ w ++ " = " ++ c ++ "`") <> out)
    case _ _:
      List.reverse(&2, String, out)

def Run.message(loop: String, texts: List<&2, String> & List<&2, String>) -> String:
  match texts:
    case Tuple{+written, +called}:
      loop
        ++ " calls itself in "
        ++ count(called)
        ++ " lets that follow each other ("
        ++ String.join(Run.lets(written, called, []), ", ")
        ++ "), and these calls run one after the other. "
        ++ costs()
        ++ " To run them in parallel, merge the lets into one: `"
        ++ String.join(written, " ")
        ++ " = "
        ++ String.join(called, " ")
        ++ "`."
        ++ expected()

# Whether the calls of a run of lets are all written the same way.
def Run.alike(texts: List<&2, String> & List<&2, String>) -> Bool:
  match texts:
    case Tuple{written, called}:
      is_alike(called)

def Bound.from(bound: Maybe<&2, Bound>) -> U32:
  match bound:
    case Some{Bound{from, w, b, c}}:
      from
    case None{}:
      0

# The finding about a run of lets (last first), if it has two lets or more: from the first's binder to the last's call.
def Run.finding(+bounds: List<&2, Bound>, +owner: Owner) -> List<&2, Lint.Finding>:
  match bounds owner:
    case Con{
      Bound{f, w, b, Lint.Node{s, n, Some{Lint.Span{path, beg, end}}, k, fs}},
      Con{second, more}
    } Owner{target, name, io, +text}:
      Lint.finding(
        Lint.Hint{},
        Bool.not(Run.alike(Bound.texts(bounds, text, [], []))),
        Some{Lint.Span{path, Bound.from(List.last(&2, Bound, bounds)), end}},
        Run.message(name, Bound.texts(bounds, text, [], []))
      )
    case _ _:
      []

# The run after a let (`bound`, if it is one): the let joins it if its call uses no binder of the run; else the run
# ends, and the let starts the next.
def Run.add(bound: Maybe<&2, Bound>, owner: Owner, run: Run) -> Run:
  match bound run:
    case Some{Bound{+f, +w, +b, +c}} Run{+bounds, +binders, +out}:
      Bool.pick(
        Run,
        uses([c], binders, False{}),
        Run{
          [Bound{f, w, b, c}],
          [b],
          Lists.onto(&2, Lint.Finding, Run.finding(bounds, owner), out)
        },
        Run{Bound{f, w, b, c} <> bounds, b <> binders, out}
      )
    case None{} Run{bounds, binders, out}:
      Run{[], [], Lists.onto(&2, Lint.Finding, Run.finding(bounds, owner), out)}

def Run.finding.end(run: Run, owner: Owner) -> List<&2, Lint.Finding>:
  match run:
    case Run{bounds, binders, out}:
      List.reverse(&2, Lint.Finding, Lists.onto(&2, Lint.Finding, Run.finding(bounds, owner), out))

# The findings about the runs of lets that follow each other from `node`, a let, after `run`: each next let is the rest
# of block of the one before, while its call uses no binder of the run.
def chain(node: Lint.Node, +owner: Owner, run: Run) -> List<&2, Lint.Finding>:
  match node:
    case Lint.Node{Lint.Destructure{q}, n, s, Con{binder, Con{value, Con{+rest, Nil{}}}}, f}:
      chain(
        rest,
        owner,
        Run.add(
          bound(Lint.Node{Lint.Destructure{q}, n, s, [binder, value, rest], f}, owner),
          owner,
          run
        )
      )
    case _:
      Run.finding.end(run, owner)

# Whether a let below `path` goes on a run from the let above it: it is that let's rest of block, and that let binds
# one name to a call.
def follows(path: List<&2, Lint.Above>, owner: Owner) -> Bool:
  match path:
    case Con{Lint.Above{Lint.Node{Lint.Destructure{q}, n, s, +kids, f}, at}, rest}:
      U32.is_eq(
        (at + 1: U32),
        U32.from_nat(Lists.length(&2, Lint.Node, kids))
      )
        && Maybe.is_some(&2, Bound, bound(Lint.Node{Lint.Destructure{q}, n, s, kids, f}, owner))
    case _:
      False{}

# The finding about the calls of the expression a node starts, if it starts one (`root`).
def roots(
  root: Bool,
  node: Lint.Node,
  span: Maybe<&2, Lint.Span>,
  +owner: Owner
) -> List<&2, Lint.Finding>:
  match root owner:
    case True{} Owner{target, name, io, text}:
      Call.finding(calls([node], target, [], False{}), span, owner)
    case _ _:
      []

# The findings about the runs of lets from a node, if it starts one (`head`).
def lets(head: Bool, node: Lint.Node, owner: Owner) -> List<&2, Lint.Finding>:
  match head:
    case True{}:
      chain(node, owner, Run{[], [], []})
    case False{}:
      []

# The findings at a node of a definition below `path`: about the calls of the expression it starts, and about the runs
# of lets from it, if it starts one.
def visit(+owner: Owner, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, Lint.Finding>:
  match owner node:
    case Owner{target, name, io, text} Lint.Node{syntax, n, span, k, f}:
      Lists.append(
        &2,
        Lint.Finding,
        roots(
          Bool.not(io) && Bool.not(is_boundary(syntax)) && starts(path) && Lint.is_live(path),
          node,
          span,
          owner
        ),
        lets(
          Maybe.is_some(
            &2,
            Bound,
            bound(node, owner)
          )
            && Bool.not(follows(path, owner))
            && Lint.is_live(path),
          node,
          owner
        )
      )

def defs(
  nodes: List<&2, Lint.Node>,
  +text: String,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Node{Lint.Definition{+t, u}, +n, s, +k, f}, rest}:
      defs(
        rest,
        text,
        Lists.onto(
          &2,
          Lint.Finding,
          Lint.visit(
            ~Owner,
            ~Lint.Finding,
            ~visit,
            Owner{t, n, returns_io(k), text},
            [Lint.Node{Lint.Definition{t, u}, n, s, k, f}]
          ),
          out
        )
      )
    case Con{node, rest}:
      defs(rest, text, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(defs(Lint.Here.nodes(here), Lint.Here.text(here), []))

def rule() -> Lint.Rule:
  Lint.Rule{Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
