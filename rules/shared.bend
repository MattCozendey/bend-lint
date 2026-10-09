# Logic that more than one Bend rule uses. A rule imports it with
# import ../shared.bend as Shared
import Base
import ../src/bend/lint.bend as Lint

# Types
# =====

# A call's head and its arguments, without annotations.
type Spine is Data:
  Spine{head: Lint.Node, args: List<&2, Lint.Node>}

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
