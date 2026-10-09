# performance/missed-fork: calls of a def to itself that could run in
# parallel, but run one after another. Bend forks only the values of a
# parallel let (`a b = f(x) f(y)`). Two such calls in one expression
# (`f(x) + f(y)`, `Node{f(x), f(y)}`), or in lets that follow each other,
# run in sequence. Bend is pure, so the calls are independent: the fix moves
# them into a parallel let, and keeps behavior. A def that returns IO is
# skipped: its calls build effects, they do not run them.
# Run: bun src/lint.ts file.bend --rules rules/performance/missed-fork.bend --fix
import Base
import ../../src/bend/lint.bend as Lint
import ../shared.bend as Shared

# Types
# =====

# Where a node sits: Free{} when it starts an expression of its own, In{}
# inside the expression that `root` starts, where every call is evaluated.
type Ctx is Data:
  Free{}
  In{root: Lint.Node}

type Frame is Data:
  Frame{node: Lint.Node, ctx: Ctx}

# A call of the def to itself, inside the expression that `root` starts.
type Call is Data:
  Call{root: Lint.Node, span: Lint.Span}

type Group is Data:
  Group{root: Lint.Node, spans: List<&2, Lint.Span>}

# What one node of the walk gives: the nodes to visit next, the calls it
# makes, and itself if it is a let with one value.
type Step is Data:
  Step{frames: List<&2, Frame>, calls: List<&2, Call>, lets: List<&2, Lint.Node>}

# What the walk found so far, last first.
type Seen is Data:
  Seen{calls: List<&2, Call>, lets: List<&2, Lint.Node>}

# A let with one value, a call of the def to itself: its node, its binder as
# written, the binder's span, and the call's span.
type Link is Data:
  Link{node: Lint.Node, binder: String, span: Lint.Span, call: Lint.Span}

type Next is Data:
  Next{link: Link, body: Lint.Node}

# Helpers
# =======
def same_node(a: Lint.Node, b: Lint.Node) -> Bool:
  match a b:
    case Lint.Node{x} Lint.Node{y}:
      U32.is_eq(x, y)

def has_node(xs: List<&2, Lint.Node>, +n: Lint.Node) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, rest}:
      Bool.or(same_node(x, n), has_node(rest, n))

def join(xs: List<&2, String>, +sep: String) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, Nil{}}:
      x
    case Con{x, rest}:
      x ++ sep ++ join(rest, sep)

def has_newline(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{'\n', rest}:
      True{}
    case SCon{c, rest}:
      has_newline(rest)

def drop_end_blank(s: String) -> String:
  String.reverse(Shared.drop_blank(String.reverse(s)))

def drop_end_paren(s: String) -> String:
  match s:
    case SCon{'(', rest}:
      drop_end_paren(rest)
    case _:
      s

# The leading blanks of `s`.
def blanks(s: String) -> String:
  match s:
    case SCon{' ', rest}:
      SCon{' ', blanks(rest)}
    case SCon{'\t', rest}:
      SCon{'\t', blanks(rest)}
    case _:
      ""

def no_bracket(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{'(', rest}:
      False{}
    case SCon{',', rest}:
      False{}
    case SCon{c, rest}:
      no_bracket(rest)

# Whether a statement starts the line before `s`'s expression: `s` is the
# line's text before it, blanks first. It may be blanks, a let's binder and
# `=`, and opening parentheses.
def starts_statement(+s: String) -> Bool:
  +rest = String.reverse(drop_end_paren(String.reverse(Shared.drop_blank(s))))
  Bool.or(
    String.eq(rest, ""),
    Bool.and(
      String.eq(String.reverse(String.take(String.reverse(rest), 2n)), "= "),
      no_bracket(rest)
    )
  )

def is_io(shown: String) -> Bool:
  String.eq(String.take(shown, 3n), "IO(")

def unplus(s: String) -> String:
  match s:
    case SCon{'+', rest}:
      rest
    case _:
      s

def letters() -> String:
  "abcdefghijklmnopqrstuvwxyz"

# The first `n` one-letter names from `cs` that are not in `used`.
def fresh(cs: String, +used: List<&2, String>, n: Nat) -> List<&2, String>:
  match cs n:
    case _ 0n:
      []
    case SNil{} _:
      []
    case SCon{c, +rest} 1n++k:
      +x: String = SCon{c, ""}
      Bool.pick(
        List<&2, String>,
        Shared.known(used, x),
        fresh(rest, used, 1n+k),
        Con{x, fresh(rest, used, k)}
      )

def visible_name(
  owner: Maybe<&2, String>,
  +o: String,
  +name: String,
  +rest: List<&2, String>
) -> List<&2, String>:
  match owner:
    case None{}:
      Con{name, rest}
    case Some{x}:
      Bool.pick(List<&2, String>, String.eq(x, o), Con{name, rest}, rest)

# The names a new local of def `o` must not take: the top-level ones, and
# the ones declared inside `o`.
def visible(ds: List<&2, Lint.Declaration>, +o: String) -> List<&2, String>:
  match ds:
    case Nil{}:
      []
    case Con{Lint.Declaration{kind, name, owner, span, refs, loads, fills, term}, rest}:
      visible_name(owner, o, name, visible(rest, o))

def var_name(s: Lint.Shape, vs: List<&2, String>) -> List<&2, String>:
  match s:
    case Lint.Shape{"Var", name, span, kids}:
      Con{name, vs}
    case _:
      vs

# The names the Var nodes of `ns` point to.
def var_names(ns: List<&2, Lint.Node>) -> IO(List<&2, String>):
  match ns:
    case Nil{}:
      IO.pure(List<&2, String>, [])
    case Con{n, rest}:
      do IO<List<&2, String>>:
        s: Lint.Shape <- Lint.shape(n)
        vs: List<&2, String> <- var_names(rest)
        return var_name(s, vs)

def any_known(xs: List<&2, String>, +used: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, rest}:
      Bool.or(Shared.known(used, x), any_known(rest, used))

# Walk
# ====
def frames(ns: List<&2, Lint.Node>, +ctx: Ctx) -> List<&2, Frame>:
  match ns:
    case Nil{}:
      []
    case Con{n, rest}:
      Con{Frame{n, ctx}, frames(rest, ctx)}

def root_of(ctx: Ctx, n: Lint.Node) -> Lint.Node:
  match ctx:
    case Free{}:
      n
    case In{root}:
      root

def call_in(ctx: Ctx, span: Maybe<&2, Lint.Span>) -> List<&2, Call>:
  match ctx span:
    case In{root} Some{s}:
      [Call{root, s}]
    case _ _:
      []

def calls_self(+self: String, s: Lint.Shape) -> Bool:
  match s:
    case Lint.Shape{"Ref", name, span, kids}:
      String.eq(name, self)
    case _:
      False{}

# A call's step: a call of the def to itself is recorded, and its
# arguments start expressions of their own; another call's head and
# arguments are inside the expression this call is in, or starts.
def app_step(
  own: Bool,
  sp: Shared.Spine,
  +ctx: Ctx,
  +bare: Lint.Node,
  span: Maybe<&2, Lint.Span>
) -> Step:
  match own sp:
    case True{} Shared.Spine{head, args}:
      Step{frames(args, Free{}), call_in(ctx, span), []}
    case False{} Shared.Spine{head, args}:
      Step{frames(Con{head, args}, In{root_of(ctx, bare)}), [], []}

def one_value(kids: List<&2, Lint.Node>, n: Lint.Node) -> List<&2, Lint.Node>:
  match kids:
    case Con{v, Con{b, Nil{}}}:
      [n]
    case _:
      []

def dispatch(+self: String, +ctx: Ctx, +bare: Lint.Node, s: Lint.Shape) -> IO(Step):
  match s:
    case Lint.Shape{"App", name, span, kids}:
      do IO<Step>:
        +sp: Shared.Spine <- Shared.call_of(bare)
        h: Lint.Shape <- Shared.head_shape(sp)
        return app_step(calls_self(self, h), sp, ctx, bare, span)
    case Lint.Shape{"Ctr", name, span, kids}:
      IO.pure(Step, Step{frames(kids, In{root_of(ctx, bare)}), [], []})
    case Lint.Shape{"Let", name, span, +kids}:
      IO.pure(Step, Step{frames(kids, Free{}), [], one_value(kids, bare)})
    case Lint.Shape{kind, name, span, kids}:
      IO.pure(Step, Step{frames(kids, Free{}), [], []})

def visit(+self: String, frame: Frame) -> IO(Step):
  match frame:
    case Frame{n, +ctx}:
      do IO<Step>:
        +bare: Lint.Node <- Lint.strip(n)
        s: Lint.Shape <- Lint.shape(bare)
        dispatch(self, ctx, bare, s)

def rev_onto(~A: Data, xs: List<&2, A>, acc: List<&2, A>) -> List<&2, A>:
  match xs:
    case Nil{}:
      acc
    case Con{x, rest}:
      rev_onto(~A, rest, Con{x, acc})

# The calls and the lets with one value in a def's body, in source order.
# `fuel` is the number of its nodes: each is visited once.
def walk(
  fuel: Nat,
  got: Maybe<&2, Step>,
  +self: String,
  stack: List<&2, Frame>,
  seen: Seen
) -> IO(Seen):
  match fuel got stack seen:
    case 1n+k Some{Step{fs, cs, ls}} _ Seen{calls, lets}:
      walk(
        k,
        None{},
        self,
        List.append(&2, Frame, fs, stack),
        Seen{rev_onto(~Call, cs, calls), rev_onto(~Lint.Node, ls, lets)}
      )
    case 1n+k None{} Con{f, rest} _:
      do IO<Seen>:
        step: Step <- visit(self, f)
        walk(k, Some{step}, self, rest, seen)
    case _ _ _ Seen{calls, lets}:
      IO.pure(Seen, Seen{List.reverse(&2, Call, calls), List.reverse(&2, Lint.Node, lets)})

# One expression
# ==============
def put(gs: List<&2, Group>, +root: Lint.Node, +span: Lint.Span) -> List<&2, Group>:
  match gs:
    case Nil{}:
      [Group{root, [span]}]
    case Con{Group{+r, +spans}, +rest}:
      Bool.pick(
        List<&2, Group>,
        same_node(r, root),
        Con{Group{r, List.append(&2, Lint.Span, spans, [span])}, rest},
        Con{Group{r, spans}, put(rest, root, span)}
      )

def grouped(cs: List<&2, Call>, gs: List<&2, Group>) -> List<&2, Group>:
  match cs:
    case Nil{}:
      gs
    case Con{Call{root, span}, rest}:
      grouped(rest, put(gs, root, span))

def edits_to(ss: List<&2, Lint.Span>, ns: List<&2, String>) -> List<&2, Lint.Edit>:
  match ss ns:
    case Con{s, srest} Con{n, nrest}:
      Con{Lint.Edit{s, n}, edits_to(srest, nrest)}
    case _ _:
      []

# The fix for calls in one expression: a parallel let of the calls, on its
# own line before the statement, and the calls replaced by its names.
def fork_fix(
  +text: String,
  +used: List<&2, String>,
  root: Maybe<&2, Lint.Span>,
  +spans: List<&2, Lint.Span>,
  +calls: List<&2, String>
) -> List<&2, Lint.Fix>:
  match root:
    case Some{Lint.Span{path, +beg, end}}:
      +names = fresh(letters(), used, List.length(&2, Lint.Span, spans))
      +before = Shared.line_before(text, U32.to_nat(beg), "")
      +at = U32.sub(beg, U32.from_nat(String.length(before)))
      Bool.pick(
        List<&2, Lint.Fix>,
        Bool.and(
          Bool.and(starts_statement(before), Bool.not(has_newline(join(calls, "")))),
          Nat.is_eq(List.length(&2, String, names), List.length(&2, Lint.Span, spans))
        ),
        [
          Lint.Fix{
            "Fork the calls",
            Lint.Safe{},
            Con{
              Lint.Edit{
                Lint.Span{path, at, at},
                blanks(before) ++ join(names, " ") ++ " = " ++ join(calls, " ") ++ "\n"
              },
              edits_to(spans, names)
            }
          }
        ],
        []
      )
    case None{}:
      []

def shape_span(s: Lint.Shape) -> Maybe<&2, Lint.Span>:
  match s:
    case Lint.Shape{kind, name, span, kids}:
      span

# Each call as `f(..)`.
def stubs(n: Nat, +self: String) -> List<&2, String>:
  match n:
    case 0n:
      []
    case 1n+k:
      Con{self ++ "(..)", stubs(k, self)}

# What a finding of `n` calls asks for, binding them to `names`.
def advice(+n: Nat, +self: String, names: List<&2, String>) -> String:
  "These "
    ++ Nat.show(n)
    ++ " calls to "
    ++ self
    ++ " run one after another. Bend forks only the values of a parallel let: `"
    ++ join(names, " ")
    ++ " = "
    ++ join(stubs(n, self), " ")
    ++ "`."

def group_diag(
  +self: String,
  +text: String,
  +used: List<&2, String>,
  g: Group
) -> IO(List<&2, Lint.Diag>):
  match g:
    case Group{root, +spans}:
      do IO<List<&2, Lint.Diag>>:
        s: Lint.Shape <- Lint.shape(root)
        calls: List<&2, String> <- Shared.texts(spans)
        +at: Maybe<&2, Lint.Span> = shape_span(s)
        +n: Nat = List.length(&2, Lint.Span, spans)
        return [
          Lint.Diag{
            Lint.Warning{},
            advice(n, self, fresh(letters(), used, n)),
            at,
            fork_fix(text, used, at, spans, calls),
            None{}
          }
        ]

def group_diags(
  +self: String,
  +text: String,
  +used: List<&2, String>,
  gs: List<&2, Group>,
  +acc: List<&2, Lint.Diag>
) -> IO(List<&2, Lint.Diag>):
  match gs:
    case Nil{}:
      IO.pure(List<&2, Lint.Diag>, acc)
    case Con{Group{+root, +spans}, +rest}:
      Bool.pick(
        IO(List<&2, Lint.Diag>),
        Nat.is_ge(List.length(&2, Lint.Span, spans), 2n),
        IO.bind(
          List<&2, Lint.Diag>,
          List<&2, Lint.Diag>,
          group_diag(self, text, used, Group{root, spans}),
          ds => group_diags(self, text, used, rest, List.append(&2, Lint.Diag, acc, ds))
        ),
        group_diags(self, text, used, rest, acc)
      )

# Lets that follow each other
# ===========================
def binders(ls: List<&2, Link>) -> List<&2, String>:
  match ls:
    case Nil{}:
      []
    case Con{Link{node, binder, span, call}, rest}:
      Con{unplus(binder), binders(rest)}

def link_end(
  +self: String,
  +known: List<&2, String>,
  +n: Lint.Node,
  +span: Lint.Span,
  bt: String,
  value: Lint.Shape,
  head: Lint.Shape,
  vars: List<&2, String>,
  +body: Lint.Node
) -> Maybe<&2, Next>:
  match value:
    case Lint.Shape{"App", name, Some{call}, kids}:
      Bool.pick(
        Maybe<&2, Next>,
        Bool.and(calls_self(self, head), Bool.not(any_known(vars, known))),
        Some{Next{Link{n, drop_end_blank(bt), span, call}, body}},
        None{}
      )
    case _:
      None{}

def link_let(
  +self: String,
  +known: List<&2, String>,
  +n: Lint.Node,
  +span: Lint.Span,
  v: Lint.Node,
  +b: Lint.Node
) -> IO(Maybe<&2, Next>):
  do IO<Maybe<&2, Next>>:
    +vb: Lint.Node <- Lint.strip(v)
    vs: Lint.Shape <- Lint.shape(vb)
    sp: Shared.Spine <- Shared.call_of(vb)
    h: Lint.Shape <- Shared.head_shape(sp)
    inner: List<&2, Lint.Node> <- Lint.nodes(vb)
    vars: List<&2, String> <- var_names(inner)
    bt: String <- Lint.text(span)
    return link_end(self, known, n, span, bt, vs, h, vars, b)

# The let at `n` as a link of a chain whose binders are `known`, if it is
# one: a let with one value, a call of the def to itself that uses none
# of them.
def link(
  +self: String,
  +known: List<&2, String>,
  +n: Lint.Node,
  s: Lint.Shape
) -> IO(Maybe<&2, Next>):
  match s:
    case Lint.Shape{"Let", name, Some{span}, Con{v, Con{b, Nil{}}}}:
      link_let(self, known, n, span, v, b)
    case _:
      IO.pure(Maybe<&2, Next>, None{})

# The lets from `n` on that form a chain, first first.
def chain(
  fuel: Nat,
  got: Maybe<&2, Maybe<&2, Next>>,
  +self: String,
  +n: Lint.Node,
  +links: List<&2, Link>
) -> IO(List<&2, Link>):
  match fuel got:
    case 1n+k None{}:
      do IO<List<&2, Link>>:
        +bare: Lint.Node <- Lint.strip(n)
        s: Lint.Shape <- Lint.shape(bare)
        m: Maybe<&2, Next> <- link(self, binders(links), bare, s)
        chain(k, Some{m}, self, bare, links)
    case 1n+k Some{Some{Next{l, body}}}:
      chain(k, None{}, self, body, Con{l, links})
    case _ _:
      IO.pure(List<&2, Link>, List.reverse(&2, Link, links))

def link_nodes(ls: List<&2, Link>) -> List<&2, Lint.Node>:
  match ls:
    case Nil{}:
      []
    case Con{Link{node, binder, span, call}, rest}:
      Con{node, link_nodes(rest)}

def link_spans(ls: List<&2, Link>) -> List<&2, Lint.Span>:
  match ls:
    case Nil{}:
      []
    case Con{Link{node, binder, span, call}, rest}:
      Con{call, link_spans(rest)}

def link_binders(ls: List<&2, Link>) -> List<&2, String>:
  match ls:
    case Nil{}:
      []
    case Con{Link{node, binder, span, call}, rest}:
      Con{binder, link_binders(rest)}

def lines(bs: List<&2, String>, cs: List<&2, String>, +indent: String) -> String:
  match bs cs:
    case Con{b, brest} Con{c, crest}:
      indent ++ b ++ " = " ++ c ++ "\n" ++ lines(brest, crest, indent)
    case _ _:
      ""

def last_end(ss: List<&2, Lint.Span>, end: U32) -> U32:
  match ss:
    case Nil{}:
      end
    case Con{Lint.Span{path, beg, e}, rest}:
      last_end(rest, e)

# The fix for lets that follow each other: one parallel let, when each let
# is written on its own line as `binder = call`.
def merge_fix(
  +bs: List<&2, String>,
  +calls: List<&2, String>,
  +indent: String,
  +region: Lint.Span,
  actual: String
) -> List<&2, Lint.Fix>:
  +want = lines(bs, calls, indent)
  Bool.pick(
    List<&2, Lint.Fix>,
    String.eq(actual, want),
    [
      Lint.Fix{
        "Merge into a parallel let",
        Lint.Safe{},
        [Lint.Edit{region, indent ++ join(bs, " ") ++ " = " ++ join(calls, " ") ++ "\n"}]
      }
    ],
    []
  )

def chain_diag(
  +self: String,
  +text: String,
  +ls: List<&2, Link>,
  first: Lint.Span
) -> IO(List<&2, Lint.Diag>):
  match first:
    case Lint.Span{+path, +beg, e}:
      +spans = link_spans(ls)
      +bs = link_binders(ls)
      +before = Shared.line_before(text, U32.to_nat(beg), "")
      +start = U32.sub(beg, U32.from_nat(String.length(before)))
      +stop = last_end(spans, beg)
      +region: Lint.Span = Lint.Span{
        path,
        start,
        Shared.line_rest(String.drop(text, U32.to_nat(stop)), stop)
      }
      do IO<List<&2, Lint.Diag>>:
        calls: List<&2, String> <- Shared.texts(spans)
        actual: String <- Lint.text(region)
        return [
          Lint.Diag{
            Lint.Warning{},
            advice(List.length(&2, String, bs), self, bs),
            Some{Lint.Span{path, beg, stop}},
            Bool.pick(
              List<&2, Lint.Fix>,
              String.eq(Shared.drop_blank(before), ""),
              merge_fix(bs, calls, before, region, actual),
              []
            ),
            None{}
          }
        ]

# A finding for a chain of two lets or more.
def chain_found(+self: String, +text: String, ls: List<&2, Link>) -> IO(List<&2, Lint.Diag>):
  match ls:
    case Con{Link{node, +binder, +span, call}, Con{second, more}}:
      chain_diag(self, text, Con{Link{node, binder, span, call}, Con{second, more}}, span)
    case _:
      IO.pure(List<&2, Lint.Diag>, [])

def chains(
  +fuel: Nat,
  +self: String,
  +text: String,
  lets: List<&2, Lint.Node>,
  +done: List<&2, Lint.Node>,
  +acc: List<&2, Lint.Diag>
) -> IO(List<&2, Lint.Diag>):
  match lets:
    case Nil{}:
      IO.pure(List<&2, Lint.Diag>, acc)
    case Con{+l, +rest}:
      Bool.pick(
        IO(List<&2, Lint.Diag>),
        has_node(done, l),
        chains(fuel, self, text, rest, done, acc),
        do IO<List<&2, Lint.Diag>>:
          +ls: List<&2, Link> <- chain(fuel, None{}, self, l, [])
          ds: List<&2, Lint.Diag> <- chain_found(self, text, ls)
          chains(fuel, self, text, rest, List.append(&2, Lint.Node, link_nodes(ls), done), List.append(&2, Lint.Diag, acc, ds)))

# Each link of a chain costs two steps of fuel.
def all_chains(+self: String, +text: String, +lets: List<&2, Lint.Node>) -> IO(List<&2, Lint.Diag>):
  chains(Nat.double(1n+List.length(&2, Lint.Node, lets)), self, text, lets, [], [])

# Rule
# ====
def found(
  +self: String,
  +text: String,
  +used: List<&2, String>,
  seen: Seen
) -> IO(List<&2, Lint.Diag>):
  match seen:
    case Seen{calls, +lets}:
      do IO<List<&2, Lint.Diag>>:
        a: List<&2, Lint.Diag> <- group_diags(self, text, used, grouped(calls, []), [])
        b: List<&2, Lint.Diag> <- all_chains(self, text, lets)
        return List.append(&2, Lint.Diag, a, b)

def in_body(
  +self: String,
  +text: String,
  +used: List<&2, String>,
  m: Maybe<&2, Lint.Node>
) -> IO(List<&2, Lint.Diag>):
  match m:
    case None{}:
      IO.pure(List<&2, Lint.Diag>, [])
    case Some{+b}:
      do IO<List<&2, Lint.Diag>>:
        all: List<&2, Lint.Node> <- Lint.nodes(b)
        seen: Seen <- walk(
          1n+List.length(&2, Lint.Node, all),
          None{},
          self,
          [Frame{b, Free{}}],
          Seen{[], []}
        )
        found(self, text, used, seen)

def in_def(
  +text: String,
  +ds: List<&2, Lint.Declaration>,
  +name: String,
  shown: String
) -> IO(List<&2, Lint.Diag>):
  Bool.pick(
    IO(List<&2, Lint.Diag>),
    is_io(shown),
    IO.pure(List<&2, Lint.Diag>, []),
    IO.bind(
      Maybe<&2, Lint.Node>,
      List<&2, Lint.Diag>,
      Lint.body(name),
      m => in_body(name, text, visible(ds, name), m)
    )
  )

def check(
  +text: String,
  +all: List<&2, Lint.Declaration>,
  d: Lint.Declaration
) -> IO(List<&2, Lint.Diag>):
  match d:
    case Lint.Declaration{Lint.Definition{}, +name, None{}, span, refs, loads, fills, Some{t}}:
      IO.bind(String, List<&2, Lint.Diag>, Lint.show(t), s => in_def(text, all, name, s))
    case _:
      IO.pure(List<&2, Lint.Diag>, [])

def checks(
  +text: String,
  +all: List<&2, Lint.Declaration>,
  ds: List<&2, Lint.Declaration>,
  acc: List<&2, Lint.Diag>
) -> IO(List<&2, Lint.Diag>):
  match ds:
    case Nil{}:
      IO.pure(List<&2, Lint.Diag>, acc)
    case Con{d, rest}:
      IO.bind(
        List<&2, Lint.Diag>,
        List<&2, Lint.Diag>,
        check(text, all, d),
        found => checks(text, all, rest, List.append(&2, Lint.Diag, acc, found))
      )

def id() -> String:
  "performance/missed-fork"

def facts() -> Lint.Want:
  Lint.NoFacts{}

def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
  match input:
    case Lint.Input{Lint.Source{path, +text, is_root}, sources, options, prior}:
      IO.bind(
        List<&2, Lint.Declaration>,
        List<&2, Lint.Diag>,
        Lint.declarations(),
        +ds => checks(text, ds, ds, [])
      )

def main() -> IO(Unit):
  Lint.serve(run)
