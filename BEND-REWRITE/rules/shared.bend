# Logic more than one rule uses. Not a rule: do not load it as one.
import Base
import ../main.bend as Lint

# A call in a def's body: its head's name, its arguments (SomeTerms), and its span.
type Call is Data:
  Call{head: String, arguments: Lint.BendTerm, span: Maybe<&2, Lint.BendSourceSpan>}

# A def's name, parameters and checked body.
type Def is Data:
  Def{name: String, params: List<&2, String>, body: Lint.BendTerm}

# A def's name, parameters and calls.
type Body is Data:
  Body{name: String, params: List<&2, String>, calls: List<&2, Call>}

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

# A term without its annotations, written or the checker's.
def get_bare(t: Lint.BendTerm) -> Lint.BendTerm:
  match t:
    case Lint.AnnotatedTerm{value, annotation, span}:
      get_bare(value)
    case Lint.CheckedTerm{term, fact}:
      get_bare(term)
    case _:
      t

def get_term_span(t: Lint.BendTerm) -> Maybe<&2, Lint.BendSourceSpan>:
  match t:
    case Lint.VariableTerm{name, span}:
      span
    case Lint.ReferenceTerm{name, span}:
      span
    case Lint.CallTerm{head, arguments, span}:
      span
    case Lint.LetTerm{names, values, body, span}:
      span
    case Lint.LambdaTerm{name, body, span}:
      span
    case Lint.ConstructorTerm{name, fields, span}:
      span
    case Lint.LiteralTerm{shown, span}:
      span
    case Lint.AnnotatedTerm{value, annotation, span}:
      span
    case Lint.ForallTerm{name, quantity, domain, body, span}:
      span
    case Lint.SortTerm{level, span}:
      span
    case Lint.DatatypeTerm{name, arguments, span}:
      span
    case Lint.OtherTerm{parts, span}:
      span
    case _:
      None{}

# How many terms a list of terms (SomeTerms) holds.
def get_term_count(ts: Lint.BendTerm) -> Nat:
  match ts:
    case Lint.SomeTerms{first, rest}:
      (1n + get_term_count(rest): Nat)
    case _:
      0n

# The term at `n` in a list of terms (SomeTerms), if there is one.
def get_nth_term(ts: Lint.BendTerm, n: Nat) -> Maybe<&2, Lint.BendTerm>:
  match ts n:
    case Lint.SomeTerms{first, rest} 0n:
      Some{first}
    case Lint.SomeTerms{first, rest} 1n+k:
      get_nth_term(rest, k)
    case _ _:
      None{}

def get_span_text.or(+lines: List<&2, String>, span: Maybe<&2, Lint.BendSourceSpan>) -> String:
  match span:
    case Some{s}:
      get_span_text(lines, s)
    case None{}:
      ""

# The text under a term's span, without its annotations; "" if it has none.
def get_term_text(+lines: List<&2, String>, t: Maybe<&2, Lint.BendTerm>) -> String:
  match t:
    case Some{term}:
      get_span_text.or(lines, get_term_span(get_bare(term)))
    case None{}:
      ""

# Where a finding goes: `span`, or the start of the file at `path` when there is none.
def get_span_or_start(+path: String, span: Maybe<&2, Lint.BendSourceSpan>) -> Lint.BendSourceSpan:
  match span:
    case Some{s}:
      s
    case None{}:
      Lint.BendSourceSpan{path, 0, 0}

# The variable a term is, through annotations, or "".
def get_variable_name(t: Lint.BendTerm) -> String:
  match t:
    case Lint.VariableTerm{name, span}:
      name
    case Lint.AnnotatedTerm{value, annotation, span}:
      get_variable_name(value)
    case Lint.CheckedTerm{term, fact}:
      get_variable_name(term)
    case _:
      ""

# The def or constructor a term names, through annotations, or "".
def get_reference_name(t: Lint.BendTerm) -> String:
  match t:
    case Lint.ReferenceTerm{name, span}:
      name
    case Lint.AnnotatedTerm{value, annotation, span}:
      get_reference_name(value)
    case Lint.CheckedTerm{term, fact}:
      get_reference_name(term)
    case _:
      ""

# Whether a type, after its arrows, is a sort (Type, Data or Kind(..)).
def get_ends_in_sort(t: Lint.BendTerm) -> Bool:
  match t:
    case Lint.ForallTerm{name, quantity, domain, body, span}:
      get_ends_in_sort(body)
    case Lint.AnnotatedTerm{value, annotation, span}:
      get_ends_in_sort(value)
    case Lint.SortTerm{level, span}:
      True{}
    case _:
      False{}

def get_arg_names(args: Lint.BendTerm) -> List<&2, String>:
  match args:
    case Lint.SomeTerms{first, rest}:
      get_variable_name(first) <> get_arg_names(rest)
    case _:
      []

# Every call in `t`, parents first, last first, before `done`.
def get_calls(t: Lint.BendTerm, done: List<&2, Call>) -> List<&2, Call>:
  match t:
    case Lint.CallTerm{+head, +arguments, span}:
      get_calls(arguments, get_calls(head, Call{get_reference_name(head), arguments, span} <> done))
    case Lint.LetTerm{names, values, body, span}:
      get_calls(body, get_calls(values, done))
    case Lint.LambdaTerm{name, body, span}:
      get_calls(body, done)
    case Lint.ConstructorTerm{name, fields, span}:
      get_calls(fields, done)
    case Lint.AnnotatedTerm{value, annotation, span}:
      get_calls(annotation, get_calls(value, done))
    case Lint.ForallTerm{name, quantity, domain, body, span}:
      get_calls(body, get_calls(domain, done))
    case Lint.SortTerm{level, span}:
      get_calls(level, done)
    case Lint.DatatypeTerm{name, arguments, span}:
      get_calls(arguments, done)
    case Lint.OtherTerm{parts, span}:
      get_calls(parts, done)
    case Lint.CheckedTerm{term, fact}:
      get_calls(term, done)
    case Lint.SomeTerms{first, rest}:
      get_calls(rest, get_calls(first, done))
    case _:
      done

def get_with_param(open: Maybe<&2, Def>, +owner: String, name: String) -> Maybe<&2, Def>:
  match open:
    case None{}:
      None{}
    case Some{Def{+n, params, body}}:
      Some{Def{n, Lint.get_kept(String, String.eq(n, owner), name, params), body}}

def get_closed(open: Maybe<&2, Def>, done: List<&2, Def>) -> List<&2, Def>:
  match open:
    case None{}:
      done
    case Some{Def{name, params, body}}:
      Def{name, List.reverse(&2, String, params), body} <> done

# Walks `ds`; `open` is the def whose parameters come next, its parameters last first.
def get_defs.go(
  ds: List<&2, Lint.Declaration>,
  open: Maybe<&2, Def>,
  done: List<&2, Def>
) -> List<&2, Def>:
  match ds:
    case Nil{}:
      List.reverse(&2, Def, get_closed(open, done))
    case Con{
      Lint.Declaration{
        name,
        span,
        references,
        Lint.DefDeclaration{fills, written_type, Some{body}}
      },
      t
    }:
      get_defs.go(t, Some{Def{name, [], body}}, get_closed(open, done))
    case Con{
      Lint.Declaration{name, span, references, Lint.ParameterDeclaration{owner, written_type}},
      t
    }:
      get_defs.go(t, get_with_param(open, owner, name), done)
    case Con{d, t}:
      get_defs.go(t, open, done)

# The defs of `ds`, a file's declarations, that have a body, in file order.
def get_defs(ds: List<&2, Lint.Declaration>) -> List<&2, Def>:
  get_defs.go(ds, None{}, [])

def get_bodies.of(defs: List<&2, Def>) -> List<&2, Body>:
  match defs:
    case Nil{}:
      []
    case Con{Def{name, params, body}, t}:
      Body{name, params, List.reverse(&2, Call, get_calls(body, []))} <> get_bodies.of(t)

# The name, parameters and calls of each def of `ds`, a file's declarations, in file order.
def get_bodies(ds: List<&2, Lint.Declaration>) -> List<&2, Body>:
  get_bodies.of(get_defs(ds))

def get_nth(xs: List<&2, String>, n: Nat) -> String:
  match xs n:
    case Con{x, rest} 0n:
      x
    case Con{x, rest} 1n+k:
      get_nth(rest, k)
    case Nil{} _:
      ""

# The position of `x` in `xs`, from `i`, if it is there.
def get_position(xs: List<&2, String>, +x: String, +i: Nat) -> Maybe<&2, Nat>:
  match xs:
    case Nil{}:
      None{}
    case Con{y, rest}:
      Bool.pick(Maybe<&2, Nat>, String.eq(y, x), Some{i}, get_position(rest, x, 1n+i))
