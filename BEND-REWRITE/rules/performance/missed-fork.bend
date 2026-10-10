# performance/missed-fork: calls of a def to itself that could run in parallel, but run one after another. Bend forks
# only the values of a parallel let (`a b = f(x) f(y)`). Two such calls in one expression (`f(x) + f(y)`,
# `Node{f(x), f(y)}`), or in lets that follow each other, run in sequence. Bend is pure, so the calls are independent:
# the fix moves them into a parallel let, and keeps behavior. A def that returns IO is skipped: its calls build
# effects, they do not run them.
# The fix is Dangerous, where TS has it Safe: it changes a def's body, and the runner shows a Safe fix keeps what the
# file declares, bodies included, so it could not offer it as Safe.
import Base
import ../../main.bend as Lint
import ../shared.bend as Shared

# Where a term sits: Free{} when it starts an expression of its own, In{} inside the expression at `root`, where every
# call is evaluated.
type Ctx is Data:
  Free{}
  In{root: Lint.BendSourceSpan}

# A call of the def to itself, inside the expression at `root`.
type Found is Data:
  Found{root: Lint.BendSourceSpan, call: Lint.BendSourceSpan}

# Calls in one expression: where it is, and the calls, in order.
type Group is Data:
  Group{root: Lint.BendSourceSpan, calls: List<&2, Lint.BendSourceSpan>}

# A let whose one value is a call of the def to itself: the name it binds, the let's binder as written (`at`), the
# call, and the variables the call uses.
type Link is Data:
  Link{name: String, at: Lint.BendSourceSpan, call: Lint.BendSourceSpan, vars: List<&2, String>}

# A let of the body, in order: its number, the number of the let whose body it is, and itself as a link, if it is one.
type LetSeen is Data:
  LetSeen{id: Nat, parent: Maybe<&2, Nat>, link: Maybe<&2, Link>}

# What the walk of a body found, last first: the calls in expressions, the lets, and how many lets.
type Seen is Data:
  Seen{calls: List<&2, Found>, lets: List<&2, LetSeen>, count: Nat}

# A def to check: its name, its written type, and its body.
type Work is Data:
  Work{name: String, written: Lint.BendType, body: Lint.BendTerm}

# A name a new local must not take, with the def it belongs to, if any.
type Taken is Data:
  Taken{name: String, owner: Maybe<&2, String>}

# Helpers
# =======
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
  String.reverse(Shared.get_drop_blank(String.reverse(s)))

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

# Whether a statement starts the line before an expression: `s` is the line's text before it, blanks first. It may be
# blanks, a let's binder and `=`, and opening parentheses.
def starts_statement(+s: String) -> Bool:
  +rest = String.reverse(drop_end_paren(String.reverse(Shared.get_drop_blank(s))))
  String.eq(
    rest,
    ""
  )
    || (String.eq(String.reverse(String.take(String.reverse(rest), 2n)), "= ") && no_bracket(rest))

# Whether a type is IO(..).
def is_io(t: Lint.BendTerm) -> Bool:
  match t:
    case Lint.CallTerm{Lint.ReferenceTerm{"IO", s}, arguments, span}:
      True{}
    case Lint.AnnotatedTerm{value, annotation, span}:
      is_io(value)
    case _:
      False{}

def letters() -> String:
  "abcdefghijklmnopqrstuvwxyz"

# The one-letter names from `cs` that are not in `used`.
def free(cs: String, +used: List<&2, String>) -> List<&2, String>:
  match cs:
    case SNil{}:
      []
    case SCon{c, rest}:
      +x: String = SCon{c, ""}
      Lint.get_kept(String, Bool.not(Shared.get_has(used, x)), x, free(rest, used))

# The first `n` one-letter names from `cs` that are not in `used`.
def fresh(cs: String, +used: List<&2, String>, n: Nat) -> List<&2, String>:
  List.take(&2, String, free(cs, used), n)

# The text under a span, which may cover several lines.
def text_at(+text: String, span: Lint.BendSourceSpan) -> String:
  match span:
    case Lint.BendSourceSpan{path, +beg, end}:
      String.take(String.drop(text, U32.to_nat(beg)), U32.to_nat(U32.sub(end, beg)))

def texts_at(+text: String, spans: List<&2, Lint.BendSourceSpan>) -> List<&2, String>:
  match spans:
    case Nil{}:
      []
    case Con{s, t}:
      text_at(text, s) <> texts_at(text, t)

def same_span(a: Lint.BendSourceSpan, b: Lint.BendSourceSpan) -> Bool:
  match a b:
    case Lint.BendSourceSpan{p, x, y} Lint.BendSourceSpan{q, u, v}:
      String.eq(p, q) && U32.is_eq(x, u) && U32.is_eq(y, v)

def nat_has(xs: List<&2, Nat>, +x: Nat) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{h, t}:
      Nat.is_eq(h, x) || nat_has(t, x)

def is_parent(p: Maybe<&2, Nat>, +id: Nat) -> Bool:
  match p:
    case Some{x}:
      Nat.is_eq(x, id)
    case None{}:
      False{}

def any_known(xs: List<&2, String>, +known: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, rest}:
      Shared.get_has(known, x) || any_known(rest, known)

# The variables `t` uses, before `done`.
def vars_in(t: Lint.BendTerm, done: List<&2, String>) -> List<&2, String>:
  match t:
    case Lint.VariableTerm{name, span}:
      name <> done
    case Lint.CallTerm{head, arguments, span}:
      vars_in(arguments, vars_in(head, done))
    case Lint.LetTerm{names, values, body, span}:
      vars_in(body, vars_in(values, done))
    case Lint.LambdaTerm{name, body, span}:
      vars_in(body, done)
    case Lint.ConstructorTerm{name, fields, span}:
      vars_in(fields, done)
    case Lint.AnnotatedTerm{value, annotation, span}:
      vars_in(value, done)
    case Lint.CheckedTerm{term, fact}:
      vars_in(term, done)
    case Lint.OtherTerm{parts, span}:
      vars_in(parts, done)
    case Lint.SomeTerms{first, rest}:
      vars_in(rest, vars_in(first, done))
    case _:
      done

# Walk
# ====
def root_of(ctx: Ctx, span: Maybe<&2, Lint.BendSourceSpan>) -> Ctx:
  match ctx span:
    case In{root} _:
      In{root}
    case Free{} Some{s}:
      In{s}
    case Free{} None{}:
      Free{}

def recorded(ctx: Ctx, span: Maybe<&2, Lint.BendSourceSpan>, seen: Seen) -> Seen:
  match ctx span seen:
    case In{root} Some{s} Seen{calls, lets, count}:
      Seen{Found{root, s} <> calls, lets, count}
    case _ _ _:
      seen

def first_name(names: List<&2, String>) -> String:
  match names:
    case Con{n, rest}:
      n
    case Nil{}:
      ""

def link_value(
  value: Lint.BendTerm,
  +self: String,
  names: List<&2, String>,
  at: Maybe<&2, Lint.BendSourceSpan>
) -> Maybe<&2, Link>:
  match value at:
    case Lint.CallTerm{+head, +arguments, Some{call}} Some{+let}:
      Bool.pick(
        Maybe<&2, Link>,
        String.eq(Shared.get_reference_name(head), self),
        Some{Link{first_name(names), let, call, vars_in(arguments, vars_in(head, []))}},
        None{}
      )
    case _ _:
      None{}

# The let as a link, if it has one value, a call of the def to itself.
def link_of(
  values: Lint.BendTerm,
  +self: String,
  names: List<&2, String>,
  at: Maybe<&2, Lint.BendSourceSpan>
) -> Maybe<&2, Link>:
  match values:
    case Lint.SomeTerms{first, Lint.NoTerms{}}:
      link_value(Shared.get_bare(first), self, names, at)
    case _:
      None{}

# Where a call's head and arguments sit: a call of the def to itself starts expressions of its own in its arguments
# (its head names the def, and holds no call); another call's are inside the expression it is in, or starts.
def call_ctx(own: Bool, ctx: Ctx, span: Maybe<&2, Lint.BendSourceSpan>) -> Ctx:
  match own:
    case True{}:
      Free{}
    case False{}:
      root_of(ctx, span)

# A call of the def to itself is recorded in the expression it is in.
def recorded_if(own: Bool, ctx: Ctx, span: Maybe<&2, Lint.BendSourceSpan>, seen: Seen) -> Seen:
  match own:
    case True{}:
      recorded(ctx, span, seen)
    case False{}:
      seen

# The calls in expressions and the lets of `t`, in def `self`, in source order; `ctx` is where `t` sits, and `parent`
# the let whose body `t` is, if any.
def walk(t: Lint.BendTerm, +self: String, +ctx: Ctx, +parent: Maybe<&2, Nat>, seen: Seen) -> Seen:
  match t:
    case Lint.CallTerm{+head, arguments, +span}:
      +own = String.eq(Shared.get_reference_name(head), self)
      +inner = call_ctx(own, ctx, span)
      walk(
        arguments,
        self,
        inner,
        None{},
        walk(head, self, inner, None{}, recorded_if(own, ctx, span, seen))
      )
    case Lint.ConstructorTerm{name, fields, span}:
      walk(fields, self, root_of(ctx, span), None{}, seen)
    case Lint.AnnotatedTerm{value, annotation, span}:
      walk(value, self, ctx, parent, seen)
    case Lint.CheckedTerm{term, fact}:
      walk(term, self, ctx, parent, seen)
    case Lint.LetTerm{names, +values, body, span}:
      match seen:
        case Seen{calls, lets, +count}:
          walk(
            body,
            self,
            Free{},
            Some{count},
            walk(
              values,
              self,
              Free{},
              None{},
              Seen{
                calls,
                LetSeen{count, parent, link_of(values, self, names, span)} <> lets,
                (1n + count: Nat)
              }
            )
          )
    case Lint.LambdaTerm{name, body, span}:
      walk(body, self, Free{}, None{}, seen)
    case Lint.ForallTerm{name, quantity, domain, body, span}:
      walk(body, self, Free{}, None{}, walk(domain, self, Free{}, None{}, seen))
    case Lint.SortTerm{level, span}:
      walk(level, self, Free{}, None{}, seen)
    case Lint.DatatypeTerm{name, arguments, span}:
      walk(arguments, self, Free{}, None{}, seen)
    case Lint.OtherTerm{parts, span}:
      walk(parts, self, Free{}, None{}, seen)
    case Lint.SomeTerms{first, rest}:
      walk(rest, self, ctx, None{}, walk(first, self, ctx, None{}, seen))
    case _:
      seen

# Advice
# ======

# Each call as `f(..)`.
def stubs(n: Nat, +self: String) -> List<&2, String>:
  match n:
    case 0n:
      []
    case 1n+k:
      (self ++ "(..)") <> stubs(k, self)

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

# One expression
# ==============
def span_has(ss: List<&2, Lint.BendSourceSpan>, +s: Lint.BendSourceSpan) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case Con{x, rest}:
      same_span(x, s) || span_has(rest, s)

# `calls` and `call`, once: the checker can copy an expression, as it does a match on characters, and a call counts
# once per place in the source.
def with_call(
  +calls: List<&2, Lint.BendSourceSpan>,
  +call: Lint.BendSourceSpan
) -> List<&2, Lint.BendSourceSpan>:
  Bool.pick(
    List<&2, Lint.BendSourceSpan>,
    span_has(calls, call),
    calls,
    List.append(&2, Lint.BendSourceSpan, calls, [call])
  )

def put(
  gs: List<&2, Group>,
  +root: Lint.BendSourceSpan,
  +call: Lint.BendSourceSpan
) -> List<&2, Group>:
  match gs:
    case Nil{}:
      [Group{root, [call]}]
    case Con{Group{+r, +calls}, +rest}:
      Bool.pick(
        List<&2, Group>,
        same_span(r, root),
        Group{r, with_call(calls, call)} <> rest,
        Group{r, calls} <> put(rest, root, call)
      )

def grouped(fs: List<&2, Found>, gs: List<&2, Group>) -> List<&2, Group>:
  match fs:
    case Nil{}:
      gs
    case Con{Found{root, call}, rest}:
      grouped(rest, put(gs, root, call))

# The calls replaced by `names`, last first: each edit applies on the text before it, so the later ones go first.
def renames(
  spans: List<&2, Lint.BendSourceSpan>,
  names: List<&2, String>,
  done: List<&2, Lint.FixEdit>
) -> List<&2, Lint.FixEdit>:
  match spans names:
    case Con{s, srest} Con{n, nrest}:
      renames(srest, nrest, Lint.ReplaceText{s, n} <> done)
    case _ _:
      done

def fork_fix.made(
  ok: Bool,
  +path: String,
  +at: U32,
  +before: String,
  names: List<&2, String>,
  +calls: List<&2, String>,
  spans: List<&2, Lint.BendSourceSpan>
) -> List<&2, Lint.Fix>:
  match ok:
    case True{}:
      +bound = names
      [
        Lint.Fix{
          "Fork the calls",
          Lint.Dangerous{},
          List.append(
            &2,
            Lint.FixEdit,
            renames(spans, bound, []),
            [
              Lint.ReplaceText{
                Lint.BendSourceSpan{path, at, at},
                blanks(before) ++ join(bound, " ") ++ " = " ++ join(calls, " ") ++ "\n"
              }
            ]
          )
        }
      ]
    case False{}:
      []

# The fix for calls in one expression: a parallel let of the calls, on its own line before the statement, and the
# calls replaced by its names.
def fork_fix(
  +text: String,
  +lines: List<&2, String>,
  +used: List<&2, String>,
  root: Lint.BendSourceSpan,
  +spans: List<&2, Lint.BendSourceSpan>
) -> List<&2, Lint.Fix>:
  match root:
    case Lint.BendSourceSpan{+path, +beg, end}:
      +n = List.length(&2, Lint.BendSourceSpan, spans)
      +names = fresh(letters(), used, n)
      +before = Shared.get_line_before(lines, beg)
      +calls = texts_at(text, spans)
      fork_fix.made(
        starts_statement(
          before
        )
          && Bool.not(has_newline(join(calls, "")))
          && Nat.is_eq(List.length(&2, String, names), n),
        path,
        U32.sub(beg, U32.from_nat(String.length(before))),
        before,
        names,
        calls,
        spans
      )

def group_findings(
  gs: List<&2, Group>,
  +self: String,
  +text: String,
  +lines: List<&2, String>,
  +used: List<&2, String>
) -> List<&2, Lint.Finding>:
  match gs:
    case Nil{}:
      []
    case Con{Group{+root, +calls}, rest}:
      +n = List.length(&2, Lint.BendSourceSpan, calls)
      List.append(
        &2,
        Lint.Finding,
        Lint.get_kept(
          Lint.Finding,
          Nat.is_ge(n, 2n),
          Lint.Finding{
            Lint.Warning{},
            advice(n, self, fresh(letters(), used, n)),
            root,
            fork_fix(text, lines, used, root, calls)
          },
          []
        ),
        group_findings(rest, self, text, lines, used)
      )

# Lets that follow each other
# ===========================

# The let whose body is the let `id`, if any.
def child_of(lets: List<&2, LetSeen>, +id: Nat) -> Maybe<&2, LetSeen>:
  match lets:
    case Nil{}:
      None{}
    case Con{LetSeen{+i, +p, +l}, rest}:
      Bool.pick(Maybe<&2, LetSeen>, is_parent(p, id), Some{LetSeen{i, p, l}}, child_of(rest, id))

# The links of the chain from `m` on, with their numbers, first first: each let's body is the next let, a link whose
# call uses none of the links before it, `known` their names.
def chain(
  fuel: Nat,
  m: Maybe<&2, LetSeen>,
  +lets: List<&2, LetSeen>,
  +known: List<&2, String>
) -> List<&2, LetSeen>:
  match fuel m:
    case 1n+k Some{LetSeen{+id, parent, Some{Link{+name, at, call, +vars}}}}:
      Bool.pick(
        List<&2, LetSeen>,
        any_known(vars, known),
        [],
        LetSeen{
          id,
          parent,
          Some{Link{name, at, call, vars}}
        }
          <> chain(k, child_of(lets, id), lets, name <> known)
      )
    case _ _:
      []

def chain_ids(ls: List<&2, LetSeen>) -> List<&2, Nat>:
  match ls:
    case Nil{}:
      []
    case Con{LetSeen{id, parent, link}, rest}:
      id <> chain_ids(rest)

def links_of(ls: List<&2, LetSeen>) -> List<&2, Link>:
  match ls:
    case Con{LetSeen{id, parent, Some{l}}, rest}:
      l <> links_of(rest)
    case _:
      []

# Each link's binder, as written.
def link_binders(ls: List<&2, Link>, +lines: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      []
    case Con{Link{name, at, call, vars}, rest}:
      drop_end_blank(Shared.get_span_text(lines, at)) <> link_binders(rest, lines)

def link_calls(ls: List<&2, Link>) -> List<&2, Lint.BendSourceSpan>:
  match ls:
    case Nil{}:
      []
    case Con{Link{name, at, call, vars}, rest}:
      call <> link_calls(rest)

def last_end(ss: List<&2, Lint.BendSourceSpan>, end: U32) -> U32:
  match ss:
    case Nil{}:
      end
    case Con{Lint.BendSourceSpan{path, beg, e}, rest}:
      last_end(rest, e)

def statements(bs: List<&2, String>, cs: List<&2, String>, +indent: String) -> String:
  match bs cs:
    case Con{b, brest} Con{c, crest}:
      indent ++ b ++ " = " ++ c ++ "\n" ++ statements(brest, crest, indent)
    case _ _:
      ""

# The fix for lets that follow each other: one parallel let, when each let is written on its own line as
# `binder = call`, and the first starts its line.
def merge_fix(
  +bs: List<&2, String>,
  +calls: List<&2, String>,
  +indent: String,
  +region: Lint.BendSourceSpan,
  actual: String
) -> List<&2, Lint.Fix>:
  Lint.get_kept(
    Lint.Fix,
    String.eq(
      Shared.get_drop_blank(indent),
      ""
    )
      && String.eq(actual, statements(bs, calls, indent)),
    Lint.Fix{
      "Merge into a parallel let",
      Lint.Dangerous{},
      [Lint.ReplaceText{region, indent ++ join(bs, " ") ++ " = " ++ join(calls, " ") ++ "\n"}]
    },
    []
  )

# The finding for a chain `all`, whose first let starts at `first`.
def chain_finding.of(
  +all: List<&2, Link>,
  first: Lint.BendSourceSpan,
  +self: String,
  +text: String,
  +lines: List<&2, String>
) -> List<&2, Lint.Finding>:
  match first:
    case Lint.BendSourceSpan{+path, +beg, e}:
      +spans = link_calls(all)
      +bs = link_binders(all, lines)
      +stop = last_end(spans, beg)
      +region = Shared.get_line_of(text, Lint.BendSourceSpan{path, beg, stop})
      [
        Lint.Finding{
          Lint.Warning{},
          advice(List.length(&2, String, bs), self, bs),
          Lint.BendSourceSpan{path, beg, stop},
          merge_fix(
            bs,
            texts_at(text, spans),
            Shared.get_line_before(lines, beg),
            region,
            text_at(text, region)
          )
        }
      ]

# A finding for a chain of two lets or more.
def chain_finding(
  ls: List<&2, Link>,
  +self: String,
  +text: String,
  +lines: List<&2, String>
) -> List<&2, Lint.Finding>:
  match ls:
    case Con{Link{n, +at, c, v}, Con{second, more}}:
      chain_finding.of(Link{n, at, c, v} <> Con{second, more}, at, self, text, lines)
    case _:
      []

# Where a chain starts: its first let.
def chain_head(ls: List<&2, LetSeen>) -> List<&2, Lint.BendSourceSpan>:
  match ls:
    case Con{LetSeen{id, parent, Some{Link{name, at, call, vars}}}, rest}:
      [at]
    case _:
      []

def head_seen(link: Maybe<&2, Link>, +heads: List<&2, Lint.BendSourceSpan>) -> Bool:
  match link:
    case Some{Link{name, at, call, vars}}:
      span_has(heads, at)
    case None{}:
      False{}

def chain_unless(skip: Bool, fuel: Nat, l: LetSeen, +lets: List<&2, LetSeen>) -> List<&2, LetSeen>:
  match skip:
    case True{}:
      []
    case False{}:
      chain(fuel, Some{l}, lets, [])

# The findings for the chains from each of `rest` on: a let already in a chain (`done`), or a copy of one that started
# a chain (`heads`), starts none.
def chains(
  +fuel: Nat,
  rest: List<&2, LetSeen>,
  +lets: List<&2, LetSeen>,
  +done: List<&2, Nat>,
  +heads: List<&2, Lint.BendSourceSpan>,
  +self: String,
  +text: String,
  +lines: List<&2, String>
) -> List<&2, Lint.Finding>:
  match rest:
    case Nil{}:
      []
    case Con{LetSeen{+id, parent, +link}, t}:
      +ls = chain_unless(
        nat_has(done, id) || head_seen(link, heads),
        fuel,
        LetSeen{id, parent, link},
        lets
      )
      List.append(
        &2,
        Lint.Finding,
        chain_finding(links_of(ls), self, text, lines),
        chains(
          fuel,
          t,
          lets,
          List.append(&2, Nat, chain_ids(ls), done),
          List.append(&2, Lint.BendSourceSpan, chain_head(ls), heads),
          self,
          text,
          lines
        )
      )

# Rule
# ====
def in_body(
  seen: Seen,
  +self: String,
  +text: String,
  +lines: List<&2, String>,
  +used: List<&2, String>
) -> List<&2, Lint.Finding>:
  match seen:
    case Seen{calls, lets, count}:
      +ordered = List.reverse(&2, LetSeen, lets)
      List.append(
        &2,
        Lint.Finding,
        group_findings(grouped(List.reverse(&2, Found, calls), []), self, text, lines, used),
        chains((1n + count: Nat), ordered, ordered, [], [], self, text, lines)
      )

# The names a new local of def `o` must not take: the top-level ones, and the ones of `o`.
def used_by(ts: List<&2, Taken>, +o: String) -> List<&2, String>:
  match ts:
    case Nil{}:
      []
    case Con{Taken{name, None{}}, rest}:
      name <> used_by(rest, o)
    case Con{Taken{name, Some{x}}, rest}:
      Lint.get_kept(String, String.eq(x, o), name, used_by(rest, o))

def owner_of(kind: Lint.DeclarationKind) -> Maybe<&2, String>:
  match kind:
    case Lint.ConstructorDeclaration{owner}:
      Some{owner}
    case Lint.ParameterDeclaration{owner, written_type}:
      Some{owner}
    case Lint.VariableDeclaration{owner}:
      Some{owner}
    case Lint.FieldDeclaration{owner, written_type}:
      Some{owner}
    case _:
      None{}

# The defs to check, and the names each declaration takes, from the file's declarations: a def with a written type
# and a body.
def split(
  ds: List<&2, Lint.Declaration>,
  works: List<&2, Work>,
  taken: List<&2, Taken>
) -> (List<&2, Work> & List<&2, Taken>):
  match ds:
    case Nil{}:
      (List.reverse(&2, Work, works), taken)
    case Con{Lint.Declaration{+name, span, references, Lint.DefDeclaration{fills, Some{written}, Some{body}}}, t}:
      split(t, Work{name, written, body} <> works, Taken{name, None{}} <> taken)
    case Con{Lint.Declaration{name, span, references, kind}, t}:
      split(t, works, Taken{name, owner_of(kind)} <> taken)

def checks(
  ws: List<&2, Work>,
  +taken: List<&2, Taken>,
  +text: String,
  +lines: List<&2, String>
) -> List<&2, Lint.Finding>:
  match ws:
    case Nil{}:
      []
    case Con{Work{+name, written, body}, rest}:
      List.append(
        &2,
        Lint.Finding,
        in_body(
          walk(body, name, Free{}, None{}, Seen{[], [], 0n}),
          name,
          text,
          lines,
          used_by(taken, name)
        ),
        checks(rest, taken, text, lines)
      )

def written_types(works: List<&2, Work>) -> List<&2, Lint.TypeQuestion>:
  match works:
    case Nil{}:
      []
    case Con{Work{name, written, body}, t}:
      Lint.TermOfType{written} <> written_types(t)

# The defs that do not return IO, by the terms of their written types, in order.
def not_io(works: List<&2, Work>, answers: List<&2, Lint.TypeAnswer>) -> List<&2, Work>:
  match works answers:
    case Con{w, t} Con{Lint.TermAnswer{term}, u}:
      Lint.get_kept(Work, Bool.not(is_io(term)), w, not_io(t, u))
    case _ _:
      []

def run.split(
  found: (List<&2, Work> & List<&2, Taken>),
  +text: String,
  +lines: List<&2, String>
) -> Lint.RuleStep:
  match found:
    case (+works, taken):
      Lint.RuleAsk{written_types(works), answers => Lint.RuleDone{checks(not_io(works, answers), taken, text, lines)}}

def run(input: Lint.RuleInput) -> Lint.RuleStep:
  match input:
    case Lint.RuleInput{root, sources, options, prior, declarations}:
      match root:
        case Lint.BendSource{+path, +text, +lines}:
          run.split(split(Shared.get_declarations_of(declarations, path), [], []), text, lines)

def rules() -> List<&1, Lint.Rule>:
  [Lint.Rule{"performance/missed-fork", Lint.FileScope{}, [], [], [Lint.BodiesNeed{}], run}]
