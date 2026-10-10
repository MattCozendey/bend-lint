# Logic more than one rule uses. Not a rule: do not load it as one.
import Base
import ../main.bend as Lint

# A call in a def's body: its head's name, the variable each argument is (or ""), and its span.
type Call is Data:
  Call{head: String, args: List<&2, String>, span: Maybe<&2, Lint.BendSourceSpan>}

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

def get_node_hit(hit: Bool, node: Lint.BodyNode) -> Maybe<&2, Lint.BodyNode>:
  match hit:
    case True{}:
      Some{node}
    case False{}:
      None{}

# The node at `at` in `nodes`; `found` is what the step before found. A node's sub-terms come after it, so the nodes
# after the one asking hold them.
def get_node(
  nodes: List<&2, Lint.BodyNode>,
  +at: U32,
  found: Maybe<&2, Lint.BodyNode>
) -> Maybe<&2, Lint.BodyNode>:
  match nodes found:
    case _ Some{n}:
      Some{n}
    case Nil{} None{}:
      None{}
    case Con{Lint.BodyNode{+index, parent, span, term}, t} None{}:
      get_node(t, at, get_node_hit(U32.is_eq(index, at), Lint.BodyNode{index, parent, span, term}))

# The node at `at`, without its annotations.
def get_stripped(
  fuel: Nat,
  +after: List<&2, Lint.BodyNode>,
  at: Maybe<&2, Lint.BodyNode>
) -> Maybe<&2, Lint.BodyNode>:
  match fuel at:
    case 1n+k Some{Lint.BodyNode{index, parent, span, Lint.AnnotatedTerm{value, annotation}}}:
      get_stripped(k, after, get_node(after, value, None{}))
    case _ _:
      at

def get_variable_name(at: Maybe<&2, Lint.BodyNode>) -> String:
  match at:
    case Some{Lint.BodyNode{index, parent, span, Lint.VariableTerm{name}}}:
      name
    case _:
      ""

def get_reference_name(at: Maybe<&2, Lint.BodyNode>) -> String:
  match at:
    case Some{Lint.BodyNode{index, parent, span, Lint.ReferenceTerm{name}}}:
      name
    case _:
      ""

def get_arg_names(
  args: List<&2, U32>,
  +fuel: Nat,
  +after: List<&2, Lint.BodyNode>
) -> List<&2, String>:
  match args:
    case Nil{}:
      []
    case Con{a, t}:
      get_variable_name(
        get_stripped(fuel, after, get_node(after, a, None{}))
      )
        <> get_arg_names(t, fuel, after)

# Every call in `ns`, parents first, after `done` reversed.
def get_calls(ns: List<&2, Lint.BodyNode>, +fuel: Nat, done: List<&2, Call>) -> List<&2, Call>:
  match ns:
    case Nil{}:
      List.reverse(&2, Call, done)
    case Con{Lint.BodyNode{index, parent, span, Lint.CallTerm{head, args}}, +t}:
      get_calls(
        t,
        fuel,
        Call{
          get_reference_name(get_node(t, head, None{})),
          get_arg_names(args, fuel, t),
          span
        }
          <> done
      )
    case Con{n, t}:
      get_calls(t, fuel, done)

# The parameters of def `o`, in order.
def get_params(ds: List<&2, Lint.Declaration>, +o: String) -> List<&2, String>:
  match ds:
    case Nil{}:
      []
    case Con{
      Lint.Declaration{name, span, references, Lint.ParameterDeclaration{owner, written_type}},
      t
    }:
      Lint.get_kept(String, String.eq(owner, o), name, get_params(t, o))
    case Con{d, t}:
      get_params(t, o)

# The name, parameters and calls of each def of `ds`; `all` are the file's declarations.
def get_bodies(ds: List<&2, Lint.Declaration>, +all: List<&2, Lint.Declaration>) -> List<&2, Body>:
  match ds:
    case Nil{}:
      []
    case Con{
      Lint.Declaration{+name, span, references, Lint.DefDeclaration{fills, written_type, +body}},
      t
    }:
      Body{
        name,
        get_params(all, name),
        get_calls(body, List.length(&2, Lint.BodyNode, body), [])
      }
        <> get_bodies(t, all)
    case Con{d, t}:
      get_bodies(t, all)

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
