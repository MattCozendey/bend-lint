# Logic that more than one Bend rule uses. A rule imports it with
# import ../shared.bend as Shared
import Base
import ../src/bend/lint.bend as Lint

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
