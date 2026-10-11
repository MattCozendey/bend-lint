# performance/missed-fork: calls of a definition to itself that could run in parallel, but run one
# after the other: two or more in one expression (`f(x) + f(y)`, `Node{f(x), f(y)}`), or in lets that
# follow each other (`l = f(x)`, then `r = f(y)`), where no call uses the result of another.
# Heuristics: Bend forks only the values of a parallel let (`a b = f(x) f(y)`), and its calls are
# independent, as Bend is pure. A fork pays when each call does much work: it costs about 100
# operations of task machinery ("bend guide shaders"), so forking small calls is slower, and the JS
# lane runs on one thread. It skips a definition that returns IO: its calls build effects, they do
# not run them. A call inside another call of itself, or inside a lambda, does not count.
import Base
import ../../lint.bend as Lint
import ../../shared.bend as Shared

# Types
# =====

# A call of a definition to itself: the expression it is in (the node just under the let, case or
# body around it), and its text.
type Call is Data:
  Call{root: U32, text: String}

# A let that binds one name to a call of its definition to itself: its id, its definition's, its
# binder, the binder as written, where the binder starts, the call's text and span, and the id of the
# let's rest of block.
type Bound is Data:
  Bound{
    id: U32,
    owner: U32,
    binder: U32,
    written: String,
    from: U32,
    text: String,
    span: Lint.Span,
    body: U32
  }

# A variable: its binder, and where it starts.
type Use is Data:
  Use{binder: U32, at: U32}

# Functions
# =========
def trim.go(cs: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Con{' ', rest}:
      trim.go(rest)
    case _:
      cs

# `s` without the blanks at its end.
def trimmed(s: String) -> String:
  String.from_list(List.reverse(&2, Char, trim.go(List.reverse(&2, Char, String.to_list(s)))))

def id(node: Lint.Node) -> U32:
  match node:
    case Lint.Node{i, p, o, s, n, b, q, sp, t}:
      i

def syntax(node: Lint.Node) -> Lint.Syntax:
  match node:
    case Lint.Node{i, p, o, s, n, b, q, sp, t}:
      s

# Whether a node of this syntax ends the expression a call is in.
def boundary(syntax: Lint.Syntax) -> Bool:
  match syntax:
    case Lint.Application{}:
      False{}
    case Lint.Construction{}:
      False{}
    case Lint.Annotation{}:
      False{}
    case _:
      True{}

# The expression a call is in, given the nodes above it (`chain`, innermost first): the id of the
# node just under the first boundary, `top` so far; none if a call of the definition to itself holds
# the call (`nested`).
def root(
  chain: List<&2, Lint.Node>,
  stopped: Bool,
  top: U32,
  nested: Bool,
  +here: Lint.Here,
  +children: Lint.Children
) -> Maybe<&2, U32>:
  match chain stopped:
    case Con{+node, rest} False{}:
      +ends = boundary(syntax(node))
      root(
        rest,
        ends,
        Bool.pick(U32, ends, top, id(node)),
        nested || (Bool.not(ends) && Lint.Here.recursive(here, children, node)),
        here,
        children
      )
    case _ _:
      Shared.when(U32, Bool.not(nested), top)

def returns_io.type(nodes: List<&2, Lint.Node>) -> Bool:
  match nodes:
    case Con{Lint.Node{i, p, o, Lint.Reference{}, n, b, q, s, t}, rest}:
      String.eq(t, "IO")
    case _:
      False{}

def returns_io.of(nodes: List<&2, Lint.Node>, children: Lint.Children) -> Bool:
  match nodes:
    case Con{Lint.Node{i, p, o, Lint.Application{}, n, b, q, s, t}, rest}:
      returns_io.type(Lint.Children.get(children, i))
    case Con{Lint.Node{i, p, o, Lint.Reference{}, n, b, q, s, t}, rest}:
      String.eq(t, "IO")
    case _:
      False{}

# Whether the definition whose children are `nodes` returns IO, as written.
def returns_io(nodes: List<&2, Lint.Node>, +children: Lint.Children) -> Bool:
  match nodes:
    case Nil{}:
      False{}
    case Con{Lint.Node{i, p, o, Lint.Returns{}, n, b, q, s, t}, rest}:
      returns_io.of(Lint.Children.get(children, i), children)
    case Con{node, rest}:
      returns_io(rest, children)

def Call.add(
  io_free: Bool,
  root: Maybe<&2, U32>,
  text: String,
  out: List<&2, Call>
) -> List<&2, Call>:
  match io_free root:
    case True{} Some{r}:
      Call{r, text} <> out
    case _ _:
      out

# The calls of the definition `owner` to itself, unless it returns IO.
def Call.of(
  recursive: Bool,
  node: Lint.Node,
  +here: Lint.Here,
  +children: Lint.Children,
  out: List<&2, Call>
) -> List<&2, Call>:
  match recursive node:
    case True{} Lint.Node{+i, p, owner, s, n, b, q, span, t}:
      Call.add(
        Bool.not(returns_io(Lint.Children.get(children, owner), children)),
        root(
          List.tail(&2, Lint.Node, Lint.Here.ancestors(here, i)),
          False{},
          i,
          False{},
          here,
          children
        ),
        Lint.Span.text(Lint.Here.text(here), span),
        out
      )
    case _ _:
      out

def Call.all(
  nodes: List<&2, Lint.Node>,
  +here: Lint.Here,
  +children: Lint.Children,
  out: List<&2, Call>
) -> List<&2, Call>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Call, out)
    case Con{+node, rest}:
      Call.all(
        rest,
        here,
        children,
        Call.of(Lint.Here.recursive(here, children, node), node, here, children, out)
      )

def Call.root(call: Call) -> String:
  match call:
    case Call{r, t}:
      U32.show(r)

def Call.texts(calls: List<&2, Call>, out: List<&2, String>) -> List<&2, String>:
  match calls:
    case Nil{}:
      List.reverse(&2, String, out)
    case Con{Call{r, t}, rest}:
      Call.texts(rest, t <> out)

def roots(calls: List<&2, Call>, +out: List<&2, U32>) -> List<&2, U32>:
  match calls:
    case Nil{}:
      List.reverse(&2, U32, out)
    case Con{Call{+r, t}, rest}:
      roots(rest, Bool.pick(List<&2, U32>, List.contains(~U32, ~U32.is_eq, out, r), out, r <> out))

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

def caveat() -> String:
  " Do it only if each call does much work: each fork costs about 100 operations of task machinery (\"bend guide shaders\"), so forking small calls makes the program slower. The JS lane runs on one thread, so it does not gain. Measured in the hand-tuned slash boss demo of Bend, forks of this kind made it slower: in a merge of quadtree cells, a frame took 16% longer; in a cloth step, that step took 30% longer. Time the program before and after a fork, and keep it only if it is faster."

def count(texts: List<&2, String>) -> String:
  U32.show(U32.from_nat(Shared.length(&2, String, texts)))

def Call.message(loop: String, +texts: List<&2, String>) -> String:
  loop
    ++ " calls itself "
    ++ count(texts)
    ++ " times in this expression ("
    ++ String.join(quoted(texts, []), ", ")
    ++ "), and these calls run one after the other. Bend runs calls in parallel only as the values of a parallel let. To run them in parallel, bind them first with one parallel let of fresh names, such as `"
    ++ String.join(binders(texts, names(), []), " ")
    ++ " = "
    ++ String.join(texts, " ")
    ++ "`, and use those names here."
    ++ caveat()

def Call.finding(
  node: Maybe<&2, Lint.Node>,
  +texts: List<&2, String>,
  here: Lint.Here
) -> List<&2, Lint.Finding>:
  match node:
    case Some{Lint.Node{i, p, o, s, n, b, q, Some{span}, t}}:
      Bool.pick(
        List<&2, Lint.Finding>,
        Nat.is_gt(Shared.length(&2, String, texts), 1n),
        [
          Lint.Finding{
            Lint.Information{},
            span,
            Call.message(Lint.Node.name(Lint.Here.node(here, o)), texts),
            []
          }
        ],
        []
      )
    case _:
      []

def Call.findings(
  rs: List<&2, U32>,
  +groups: Map<&2, List<&2, Call>>,
  +here: Lint.Here,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match rs:
    case Nil{}:
      out
    case Con{+r, rest}:
      Call.findings(
        rest,
        groups,
        here,
        Shared.onto(
          &2,
          Lint.Finding,
          Call.finding(
            Lint.Here.node(here, r),
            Call.texts(Shared.Group.get(Call, groups, U32.show(r)), []),
            here
          ),
          out
        )
      )

def called.first(
  nodes: List<&2, Lint.Node>,
  here: Lint.Here,
  children: Lint.Children
) -> Maybe<&2, Lint.Node>:
  match nodes:
    case Con{+node, rest}:
      Shared.when(Lint.Node, Lint.Here.recursive(here, children, node), node)
    case Nil{}:
      None{}

# The call of a let's value, if the value is a call of its definition to itself, typed or not.
def called(+value: Lint.Node, here: Lint.Here, +children: Lint.Children) -> Maybe<&2, Lint.Node>:
  match value:
    case Lint.Node{i, p, o, Lint.Annotation{}, n, b, q, s, t}:
      called.first(Lint.Children.get(children, i), here, children)
    case _:
      Shared.when(Lint.Node, Lint.Here.recursive(here, children, value), value)

def Bound.make(
  call: Maybe<&2, Lint.Node>,
  id: U32,
  binder: U32,
  written: String,
  from: U32,
  body: U32,
  source: String,
  out: List<&2, Bound>
) -> List<&2, Bound>:
  match call:
    case Some{Lint.Node{i, p, o, s, n, b, q, Some{Lint.Span{path, +beg, +end}}, t}}:
      Bound{
        id,
        o,
        binder,
        written,
        from,
        Shared.slice(source, beg, end),
        Lint.Span{path, beg, end},
        body
      }
        <> out
    case _:
      out

# The bound let whose children are `nodes`, if it binds one name to a call of its definition to
# itself.
def Bound.of(
  nodes: List<&2, Lint.Node>,
  id: U32,
  body: U32,
  +here: Lint.Here,
  children: Lint.Children,
  out: List<&2, Bound>
) -> List<&2, Bound>:
  match nodes:
    case Con{
      Lint.Node{
        i,
        p,
        o,
        Lint.PatternVariable{},
        n,
        Some{binder},
        q,
        Some{Lint.Span{path, +from, end}},
        t
      },
      Con{value, Con{rest, more}}
    }:
      Bound.make(
        called(value, here, children),
        id,
        binder,
        trimmed(Shared.slice(Lint.Here.text(here), from, end)),
        from,
        body,
        Lint.Here.text(here),
        out
      )
    case _:
      out

def Bound.all(
  nodes: List<&2, Lint.Node>,
  +here: Lint.Here,
  +children: Lint.Children,
  out: List<&2, Bound>
) -> List<&2, Bound>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Bound, out)
    case Con{Lint.Node{+i, p, o, Lint.Destructure{}, n, b, q, s, t}, rest}:
      Bound.all(
        rest,
        here,
        children,
        Bound.of(
          Lint.Children.get(children, i),
          i,
          Lint.Children.last(children, i),
          here,
          children,
          out
        )
      )
    case Con{node, rest}:
      Bound.all(rest, here, children, out)

def Use.all(nodes: List<&2, Lint.Node>, out: List<&2, Use>) -> List<&2, Use>:
  match nodes:
    case Nil{}:
      out
    case Con{
      Lint.Node{i, p, o, Lint.Variable{}, n, Some{b}, q, Some{Lint.Span{path, beg, end}}, t},
      rest
    }:
      Use.all(rest, Use{b, beg} <> out)
    case Con{node, rest}:
      Use.all(rest, out)

# Whether a variable of `us` uses a binder of `binders` from `beg` to `end`.
def uses(us: List<&2, Use>, hit: Bool, +binders: List<&2, U32>, +beg: U32, +end: U32) -> Bool:
  match us hit:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{Use{b, +at}, rest} False{}:
      uses(
        rest,
        List.contains(~U32, ~U32.is_eq, binders, b) && U32.is_ge(at, beg) && U32.is_lt(at, end),
        binders,
        beg,
        end
      )

def Bound.find(bounds: List<&2, Bound>, found: Maybe<&2, Bound>, +id: U32) -> Maybe<&2, Bound>:
  match bounds found:
    case _ Some{bound}:
      Some{bound}
    case Nil{} None{}:
      None{}
    case Con{Bound{+i, o, b, w, f, x, s, y}, rest} None{}:
      Bound.find(rest, Shared.when(Bound, U32.is_eq(i, id), Bound{i, o, b, w, f, x, s, y}), id)

# The let after a let of a run, if the run goes on (`free`: its call uses no binder of the run).
def Bound.next(free: Bool, bounds: List<&2, Bound>, body: U32) -> Maybe<&2, Bound>:
  match free:
    case True{}:
      Bound.find(bounds, None{}, body)
    case False{}:
      None{}

# A run of lets that follow each other, from `next`, last first: each next let is the rest of block of
# the one before, while its call uses no binder of the run. `fuel` bounds the steps.
def run.go(
  fuel: Nat,
  next: Maybe<&2, Bound>,
  +bounds: List<&2, Bound>,
  +us: List<&2, Use>,
  +binders: List<&2, U32>,
  out: List<&2, Bound>
) -> List<&2, Bound>:
  match fuel next:
    case 1n+f Some{Bound{i, o, +b, w, fr, x, Lint.Span{path, +beg, +end}, +body}}:
      +free = Bool.not(uses(us, False{}, binders, beg, end))
      run.go(
        f,
        Bound.next(free, bounds, body),
        bounds,
        us,
        b <> binders,
        Shared.push(
          Bound,
          Shared.when(Bound, free, Bound{i, o, b, w, fr, x, Lint.Span{path, beg, end}, body}),
          out
        )
      )
    case _ _:
      out

def Bound.ids(run: List<&2, Bound>, out: List<&2, U32>) -> List<&2, U32>:
  match run:
    case Nil{}:
      out
    case Con{Bound{i, o, b, w, f, x, s, y}, rest}:
      Bound.ids(rest, i <> out)

def Bound.texts(
  run: List<&2, Bound>,
  written: List<&2, String>,
  called: List<&2, String>
) -> List<&2, String>
  & List<&2, String>:
  match run:
    case Nil{}:
      (written, called)
    case Con{Bound{i, o, b, w, f, x, s, y}, rest}:
      Bound.texts(rest, w <> written, x <> called)

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
        ++ "), and these calls run one after the other. Bend runs calls in parallel only as the values of a parallel let. To run them in parallel, merge the lets into one: `"
        ++ String.join(written, " ")
        ++ " = "
        ++ String.join(called, " ")
        ++ "`."
        ++ caveat()

def Run.spanned(
  run: List<&2, Bound>,
  path: String,
  end: U32,
  loop: String
) -> List<&2, Lint.Finding>:
  match run:
    case Con{Bound{i, o, b, w, +from, x, s, y}, rest}:
      [
        Lint.Finding{
          Lint.Information{},
          Lint.Span{path, from, end},
          Run.message(
            loop,
            Bound.texts(
              List.reverse(&2, Bound, Con{Bound{i, o, b, w, from, x, s, y}, rest}),
              [],
              []
            )
          ),
          []
        }
      ]
    case Nil{}:
      []

# The finding about a run of lets, last first, if it has two lets or more.
def Run.finding(run: List<&2, Bound>, here: Lint.Here) -> List<&2, Lint.Finding>:
  match run:
    case Con{Bound{i, +o, b, w, fr, x, Lint.Span{+path, beg, +end}, y}, Con{second, more}}:
      Run.spanned(
        List.reverse(
          &2,
          Bound,
          Con{Bound{i, o, b, w, fr, x, Lint.Span{path, beg, end}, y}, Con{second, more}}
        ),
        path,
        end,
        Lint.Node.name(Lint.Here.node(here, o))
      )
    case _:
      []

# The run of lets from `bound`, unless an earlier run holds it.
def run.from(
  consumed: Bool,
  bound: Bound,
  +bounds: List<&2, Bound>,
  us: List<&2, Use>
) -> List<&2, Bound>:
  match consumed:
    case True{}:
      []
    case False{}:
      run.go(Shared.length(&2, Bound, bounds), Some{bound}, bounds, us, [], [])

def runs(
  bs: List<&2, Bound>,
  +bounds: List<&2, Bound>,
  +us: List<&2, Use>,
  +consumed: List<&2, U32>,
  +here: Lint.Here,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match bs:
    case Nil{}:
      out
    case Con{Bound{+i, o, b, w, f, x, s, y}, rest}:
      +run = run.from(
        List.contains(~U32, ~U32.is_eq, consumed, i),
        Bound{i, o, b, w, f, x, s, y},
        bounds,
        us
      )
      runs(
        rest,
        bounds,
        us,
        Bound.ids(run, consumed),
        here,
        Shared.onto(&2, Lint.Finding, Run.finding(run, here), out)
      )

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +nodes = Lint.Here.nodes(here)
  +children = Lint.Children.of(nodes)
  +calls = Call.all(nodes, here, children, [])
  +bounds = Bound.all(nodes, here, children, [])
  Lint.done(
    runs(
      bounds,
      bounds,
      Use.all(nodes, []),
      [],
      here,
      Call.findings(
        roots(calls, []),
        Shared.Group.of(~Call, ~Call.root, calls, Map.new(&2, List<&2, Call>)),
        here,
        []
      )
    )
  )

def rule() -> Lint.Rule:
  Lint.Rule{"performance/missed-fork", Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
