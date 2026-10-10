# Logic more than one rule uses. Not a rule: do not load it as one.
import Base
import ../main.bend as Lint

def get_has(xs: List<&2, String>, +x: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{h, t}:
      String.eq(h, x) || get_has(t, x)

def get_declarations_of.pick(
  hit: Bool,
  ds: List<&2, Lint.Declaration>,
  rest: List<&2, Lint.Declaration>
) -> List<&2, Lint.Declaration>:
  match hit:
    case True{}:
      ds
    case False{}:
      rest

def get_declarations_of(
  all: List<&2, Lint.SourceDeclarations>,
  +path: String
) -> List<&2, Lint.Declaration>:
  match all:
    case Nil{}:
      []
    case Con{s, t}:
      match s:
        case Lint.SourceDeclarations{p, ds}:
          get_declarations_of.pick(String.eq(p, path), ds, get_declarations_of(t, path))

def get_head_size(lines: List<&2, String>) -> U32:
  match lines:
    case Nil{}:
      0
    case Con{h, t}:
      U32.from_nat(String.length(h))

def get_span_text.go(
  lines: List<&2, String>,
  inside: Bool,
  +at: U32,
  +beg: U32,
  +end: U32
) -> String:
  match lines inside:
    case Nil{} _:
      ""
    case Con{h, t} True{}:
      String.take(String.drop(h, U32.to_nat(U32.sub(beg, at))), U32.to_nat(U32.sub(end, beg)))
    case Con{h, +t} False{}:
      +next = U32.add(U32.add(at, U32.from_nat(String.length(h))), 1)
      get_span_text.go(
        t,
        U32.is_lt(beg, U32.add(U32.add(next, get_head_size(t)), 1)),
        next,
        beg,
        end
      )

def get_span_text(+lines: List<&2, String>, span: Lint.BendSourceSpan) -> String:
  match span:
    case Lint.BendSourceSpan{path, +beg, end}:
      get_span_text.go(lines, U32.is_lt(beg, U32.add(get_head_size(lines), 1)), 0, beg, end)

def get_option.pick(
  hit: Bool,
  value: Lint.OptionValue,
  later: Maybe<&2, Lint.OptionValue>
) -> Maybe<&2, Lint.OptionValue>:
  match hit:
    case True{}:
      Some{value}
    case False{}:
      later

def get_option(options: List<&2, Lint.OptionGiven>, +key: String) -> Maybe<&2, Lint.OptionValue>:
  match options:
    case Nil{}:
      None{}
    case Con{Lint.OptionGiven{k, value}, t}:
      get_option.pick(String.eq(k, key), value, get_option(t, key))

def get_option_number.of(m: Maybe<&2, Lint.OptionValue>) -> U32:
  match m:
    case Some{Lint.NumberValue{n}}:
      n
    case _:
      0

def get_option_number(options: List<&2, Lint.OptionGiven>, +key: String) -> U32:
  get_option_number.of(get_option(options, key))

def get_option_text.of(m: Maybe<&2, Lint.OptionValue>) -> String:
  match m:
    case Some{Lint.TextValue{s}}:
      s
    case _:
      ""

def get_option_text(options: List<&2, Lint.OptionGiven>, +key: String) -> String:
  get_option_text.of(get_option(options, key))

def get_line_before.go(lines: List<&2, String>, inside: Bool, +beg: U32, +at: U32) -> String:
  match lines inside:
    case Nil{} _:
      ""
    case Con{h, t} True{}:
      String.take(h, U32.to_nat(U32.sub(beg, at)))
    case Con{h, +t} False{}:
      +next = U32.add(U32.add(at, U32.from_nat(String.length(h))), 1)
      get_line_before.go(t, U32.is_lt(beg, U32.add(U32.add(next, get_head_size(t)), 1)), beg, next)

def get_line_before(+lines: List<&2, String>, +beg: U32) -> String:
  get_line_before.go(lines, U32.is_lt(beg, U32.add(get_head_size(lines), 1)), beg, 0)

def get_drop_blank(+s: String) -> String:
  match s:
    case SCon{' ', rest}:
      get_drop_blank(rest)
    case SCon{'\t', rest}:
      get_drop_blank(rest)
    case _:
      s

def get_word(s: String) -> String:
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
      SCon{c, get_word(rest)}
    case SNil{}:
      ""

def get_after_import(line: String) -> String:
  get_drop_blank(String.drop(get_drop_blank(line), 6n))

def get_text_line_before(s: String, n: Nat, line: String) -> String:
  match s n:
    case _ 0n:
      String.reverse(line)
    case SNil{} _:
      String.reverse(line)
    case SCon{'\n', rest} 1n+k:
      get_text_line_before(rest, k, "")
    case SCon{c, rest} 1n+k:
      get_text_line_before(rest, k, SCon{c, line})

def get_line_rest(s: String, n: U32) -> U32:
  match s:
    case SNil{}:
      n
    case SCon{'\n', rest}:
      U32.inc(n)
    case SCon{c, rest}:
      get_line_rest(rest, U32.inc(n))

def get_line_of(+text: String, span: Lint.BendSourceSpan) -> Lint.BendSourceSpan:
  match span:
    case Lint.BendSourceSpan{path, +beg, +end}:
      Lint.BendSourceSpan{
        path,
        U32.sub(beg, U32.from_nat(String.length(get_text_line_before(text, U32.to_nat(beg), "")))),
        get_line_rest(String.drop(text, U32.to_nat(end)), end)
      }
