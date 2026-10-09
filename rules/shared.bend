# Logic that more than one Bend rule uses. A rule imports it with
# import ../shared.bend as Shared
import Base
import ../src/bend/lint.bend as Lint

# Types
# =====

# A call's head and its arguments, without annotations.
type Spine is Data:
  Spine{head: Lint.Node, args: List<&2, Lint.Node>}

# An argument of a call: the variable it is (or ""), and its span.
type Arg is Data:
  Arg{name: String, span: Maybe<&2, Lint.Span>}

# A call in a def's body: its head's name, its arguments, and its span.
type Call is Data:
  Call{head: String, args: List<&2, Arg>, span: Maybe<&2, Lint.Span>}

# A def's name, parameters and calls.
type Body is Data:
  Body{name: String, params: List<&2, String>, calls: List<&2, Call>}

# Constants
# =========

# The fuel to read a call's head and arguments: two steps per argument.
def spine_fuel() -> Nat:
  128n

# Functions
# =========

# The text of the line that holds offset `n` of `s`, up to `n`.
def line_before(s: String, n: Nat, line: String) -> String:
  match s n:
    case _ 0n:
      String.reverse(line)
    case SNil{} _:
      String.reverse(line)
    case SCon{'\n', rest} 1n+k:
      line_before(rest, k, "")
    case SCon{c, rest} 1n+k:
      line_before(rest, k, SCon{c, line})

# Whether `p` is in `xs`.
def known(xs: List<&2, String>, +p: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, rest}:
      Bool.or(String.eq(x, p), known(rest, p))

def drop_blank(+s: String) -> String:
  match s:
    case SCon{' ', rest}:
      drop_blank(rest)
    case SCon{'\t', rest}:
      drop_blank(rest)
    case _:
      s

# The text up to the first blank or line end.
def word(s: String) -> String:
  match s:
    case SCon{' ', rest}:
      ""
    case SCon{'\t', rest}:
      ""
    case SCon{'\r', rest}:
      ""
    case SCon{'\n', rest}:
      ""
    case SCon{c, rest}:
      SCon{c, word(rest)}
    case SNil{}:
      ""

# What follows "import" and its blanks, on a line that ends before an alias.
def after_import(line: String) -> String:
  drop_blank(String.drop(drop_blank(line), 6n))

# The characters from `s` to the end of its line, newline included, plus n.
def line_rest(s: String, n: U32) -> U32:
  match s:
    case SNil{}:
      n
    case SCon{'\n', rest}:
      U32.inc(n)
    case SCon{c, rest}:
      line_rest(rest, U32.inc(n))

# The whole line of a span, newline included.
def line_of(+text: String, span: Lint.Span) -> Lint.Span:
  match span:
    case Lint.Span{path, +beg, +end}:
      Lint.Span{
        path,
        U32.sub(beg, U32.from_nat(String.length(line_before(text, U32.to_nat(beg), "")))),
        line_rest(String.drop(text, U32.to_nat(end)), end)
      }

# The text under each span.
def texts(ss: List<&2, Lint.Span>) -> IO(List<&2, String>):
  match ss:
    case Nil{}:
      IO.pure(List<&2, String>, [])
    case Con{s, rest}:
      do IO<List<&2, String>>:
        t: String <- Lint.text(s)
        ts: List<&2, String> <- texts(rest)
        return Con{t, ts}

# A call's head and arguments.
def spine(
  fuel: Nat,
  got: Maybe<&2, Lint.Shape>,
  +n: Lint.Node,
  args: List<&2, Lint.Node>
) -> IO(Spine):
  match fuel got:
    case 0n _:
      IO.pure(Spine, Spine{n, args})
    case 1n+k None{}:
      do IO<Spine>:
        +bare: Lint.Node <- Lint.strip(n)
        s: Lint.Shape <- Lint.shape(bare)
        spine(k, Some{s}, bare, args)
    case 1n+k Some{Lint.Shape{"App", name, span, Con{f, Con{a, Nil{}}}}}:
      spine(k, None{}, f, Con{a, args})
    case 1n+k Some{s}:
      IO.pure(Spine, Spine{n, args})

# The head and arguments of the call at `n`; none if it is not a call.
def call_of(n: Lint.Node) -> IO(Spine):
  spine(spine_fuel(), None{}, n, [])

def head_shape(sp: Spine) -> IO(Lint.Shape):
  match sp:
    case Spine{head, args}:
      Lint.shape(head)

def nth(xs: List<&2, String>, n: Nat) -> String:
  match xs n:
    case Con{x, rest} 0n:
      x
    case Con{x, rest} 1n+k:
      nth(rest, k)
    case Nil{} _:
      ""

# The position of `x` in `xs`, from `i`, if it is there.
def position(xs: List<&2, String>, +x: String, +i: Nat) -> Maybe<&2, Nat>:
  match xs:
    case Nil{}:
      None{}
    case Con{y, rest}:
      Bool.pick(Maybe<&2, Nat>, String.eq(y, x), Some{i}, position(rest, x, 1n+i))

def names(args: List<&2, Arg>) -> List<&2, String>:
  match args:
    case Nil{}:
      []
    case Con{Arg{name, span}, rest}:
      Con{name, names(rest)}

def arg_of(s: Lint.Shape) -> Arg:
  match s:
    case Lint.Shape{"Var", name, span, kids}:
      Arg{name, span}
    case Lint.Shape{kind, name, span, kids}:
      Arg{"", span}

def args_of(ns: List<&2, Lint.Node>) -> IO(List<&2, Arg>):
  match ns:
    case Nil{}:
      IO.pure(List<&2, Arg>, [])
    case Con{n, rest}:
      do IO<List<&2, Arg>>:
        bare: Lint.Node <- Lint.strip(n)
        s: Lint.Shape <- Lint.shape(bare)
        as: List<&2, Arg> <- args_of(rest)
        return Con{arg_of(s), as}

def ref_name(s: Lint.Shape) -> String:
  match s:
    case Lint.Shape{"Ref", name, span, kids}:
      name
    case _:
      ""

def call_at(sp: Spine, span: Maybe<&2, Lint.Span>) -> IO(Call):
  match sp:
    case Spine{head, args}:
      do IO<Call>:
        h: Lint.Shape <- Lint.shape(head)
        as: List<&2, Arg> <- args_of(args)
        return Call{ref_name(h), as, span}

def calls_in(s: Lint.Shape, +n: Lint.Node) -> IO(List<&2, Call>):
  match s:
    case Lint.Shape{"App", name, span, kids}:
      do IO<List<&2, Call>>:
        sp: Spine <- call_of(n)
        c: Call <- call_at(sp, span)
        return [c]
    case _:
      IO.pure(List<&2, Call>, [])

# Every call in `ns`, last first. A call of n arguments is n nested App
# nodes; each is listed, with its own count of arguments.
def calls(ns: List<&2, Lint.Node>, acc: List<&2, Call>) -> IO(List<&2, Call>):
  match ns:
    case Nil{}:
      IO.pure(List<&2, Call>, acc)
    case Con{+n, rest}:
      do IO<List<&2, Call>>:
        s: Lint.Shape <- Lint.shape(n)
        cs: List<&2, Call> <- calls_in(s, n)
        calls(rest, List.append(&2, Call, cs, acc))

def body_of(
  +name: String,
  +params: List<&2, String>,
  m: Maybe<&2, Lint.Node>
) -> IO(List<&2, Body>):
  match m:
    case None{}:
      IO.pure(List<&2, Body>, [])
    case Some{b}:
      do IO<List<&2, Body>>:
        ns: List<&2, Lint.Node> <- Lint.nodes(b)
        cs: List<&2, Call> <- calls(ns, [])
        return [Body{name, params, cs}]

def param_name(
  owner: Maybe<&2, String>,
  kind: Lint.DeclarationKind,
  +o: String,
  +name: String,
  +rest: List<&2, String>
) -> List<&2, String>:
  match owner kind:
    case Some{x} Lint.Parameter{}:
      Bool.pick(List<&2, String>, String.eq(x, o), Con{name, rest}, rest)
    case _ _:
      rest

# The parameters of def `o`, in order.
def params_of(ds: List<&2, Lint.Declaration>, +o: String) -> List<&2, String>:
  match ds:
    case Nil{}:
      []
    case Con{Lint.Declaration{kind, name, owner, span, refs, loads, fills, term}, rest}:
      param_name(owner, kind, o, name, params_of(rest, o))

def body(+all: List<&2, Lint.Declaration>, d: Lint.Declaration) -> IO(List<&2, Body>):
  match d:
    case Lint.Declaration{Lint.Definition{}, +name, None{}, span, refs, loads, fills, term}:
      IO.bind(
        Maybe<&2, Lint.Node>,
        List<&2, Body>,
        Lint.body(name),
        m => body_of(name, params_of(all, name), m)
      )
    case _:
      IO.pure(List<&2, Body>, [])

# The body of each top-level def of `ds`, in file order; `all` are the
# file's declarations.
def bodies(
  +all: List<&2, Lint.Declaration>,
  ds: List<&2, Lint.Declaration>,
  acc: List<&2, Body>
) -> IO(List<&2, Body>):
  match ds:
    case Nil{}:
      IO.pure(List<&2, Body>, acc)
    case Con{d, rest}:
      IO.bind(
        List<&2, Body>,
        List<&2, Body>,
        body(all, d),
        b => bodies(all, rest, List.append(&2, Body, acc, b))
      )
