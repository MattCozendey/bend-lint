import Base
import ../shared/lists.bend as Lists
import ../shared/names.bend as Names
import ../shared/places.bend as Places
import ../shared/strings.bend as Strings
import ./lint.bend as Lint

# Scanning
# ========

# A comment: where it is (code points), its line (from 0), whether code comes before it on its line, and its text
# after the #.
type Comment is Data:
  Comment{beg: U32, end: U32, line: U32, trailing: Bool, body: String}

type Glyph is Data:
  LineEnd{}
  CarriageReturn{}
  Hash{}
  DoubleQuote{}
  SingleQuote{}
  Backslash{}
  Blank{}
  Other{}

# Where the scan is: in code, a comment, or a string or char literal (`string`), maybe just after a \ in it.
type Mode is Data:
  InCode{}
  InComment{}
  InQuote{string: Bool, escaped: Bool}

# The scan so far: where it is, its offset and line, whether its line holds code, the comment it is in (its body last
# first), the comments before (last first), and whether each line before holds code (last first).
type Scan is Data:
  Scan{
    mode: Mode,
    at: U32,
    line: U32,
    code: Bool,
    open: Comment,
    comments: List<&2, Comment>,
    lines: List<&2, Bool>
  }

type Scanned is Data:
  Scanned{comments: List<&2, Comment>, lines: List<&2, Bool>}

def Glyph.of(+c: Char) -> Glyph:
  Bool.pick(
    Glyph,
    Char.is_eq(c, '\n'),
    LineEnd{},
    Bool.pick(
      Glyph,
      Char.is_eq(c, '#'),
      Hash{},
      Bool.pick(
        Glyph,
        Char.is_eq(c, '"'),
        DoubleQuote{},
        Bool.pick(
          Glyph,
          Char.is_eq(c, '\''),
          SingleQuote{},
          Bool.pick(
            Glyph,
            Char.is_eq(c, '\\'),
            Backslash{},
            Bool.pick(
              Glyph,
              Char.is_eq(c, '\r'),
              CarriageReturn{},
              Bool.pick(Glyph, Char.is_eq(c, ' ') || Char.is_eq(c, '\t'), Blank{}, Other{})
            )
          )
        )
      )
    )
  )

# No comment: what the scan holds as its open comment outside one.
def Comment.none() -> Comment:
  Comment{0, 0, 0, False{}, ""}

# The comment `open`, ended at `at`, its body in order.
def Comment.closed(open: Comment, at: U32) -> Comment:
  match open:
    case Comment{beg, end, line, trailing, body}:
      Comment{beg, at, line, trailing, String.reverse(body)}

def Comment.push(open: Comment, c: Char) -> Comment:
  match open:
    case Comment{beg, end, line, trailing, body}:
      Comment{beg, end, line, trailing, SCon{c, body}}

def Scan.in_code(
  glyph: Glyph,
  +at: U32,
  +line: U32,
  +code: Bool,
  open: Comment,
  comments: List<&2, Comment>,
  lines: List<&2, Bool>
) -> Scan:
  match glyph:
    case LineEnd{}:
      Scan{InCode{}, (at + 1: U32), (line + 1: U32), False{}, open, comments, code <> lines}
    case Hash{}:
      Scan{InComment{}, (at + 1: U32), line, code, Comment{at, at, line, code, ""}, comments, lines}
    case DoubleQuote{}:
      Scan{InQuote{True{}, False{}}, (at + 1: U32), line, True{}, open, comments, lines}
    case SingleQuote{}:
      Scan{InQuote{False{}, False{}}, (at + 1: U32), line, True{}, open, comments, lines}
    case Blank{}:
      Scan{InCode{}, (at + 1: U32), line, code, open, comments, lines}
    case CarriageReturn{}:
      Scan{InCode{}, (at + 1: U32), line, code, open, comments, lines}
    case _:
      Scan{InCode{}, (at + 1: U32), line, True{}, open, comments, lines}

def Scan.in_comment(
  glyph: Glyph,
  c: Char,
  +at: U32,
  line: U32,
  code: Bool,
  open: Comment,
  comments: List<&2, Comment>,
  lines: List<&2, Bool>
) -> Scan:
  match glyph:
    case LineEnd{}:
      Scan{
        InCode{},
        (at + 1: U32),
        (line + 1: U32),
        False{},
        Comment.none(),
        Comment.closed(open, at) <> comments,
        code <> lines
      }
    case CarriageReturn{}:
      Scan{
        InCode{},
        (at + 1: U32),
        line,
        code,
        Comment.none(),
        Comment.closed(open, at) <> comments,
        lines
      }
    case _:
      Scan{InComment{}, (at + 1: U32), line, code, Comment.push(open, c), comments, lines}

# Where a quote leaves the scan: a string's " and a char's ' close it; the other quote does not.
def Scan.quote(string: Bool, double: Bool) -> Mode:
  match string double:
    case True{} True{}:
      InCode{}
    case False{} False{}:
      InCode{}
    case _ _:
      InQuote{string, False{}}

# A step in a string or a char literal (`string`): a \ escapes the next character, its closing quote ends it, and a
# line it spans holds code.
def Scan.in_quote(
  string: Bool,
  escaped: Bool,
  glyph: Glyph,
  at: U32,
  line: U32,
  code: Bool,
  open: Comment,
  comments: List<&2, Comment>,
  lines: List<&2, Bool>
) -> Scan:
  match escaped glyph:
    case _ LineEnd{}:
      Scan{
        InQuote{string, False{}},
        (at + 1: U32),
        (line + 1: U32),
        True{},
        open,
        comments,
        True{} <> lines
      }
    case True{} _:
      Scan{InQuote{string, False{}}, (at + 1: U32), line, code, open, comments, lines}
    case False{} Backslash{}:
      Scan{InQuote{string, True{}}, (at + 1: U32), line, code, open, comments, lines}
    case False{} DoubleQuote{}:
      Scan{Scan.quote(string, True{}), (at + 1: U32), line, code, open, comments, lines}
    case False{} SingleQuote{}:
      Scan{Scan.quote(string, False{}), (at + 1: U32), line, code, open, comments, lines}
    case False{} _:
      Scan{InQuote{string, False{}}, (at + 1: U32), line, code, open, comments, lines}

def Scan.step(glyph: Glyph, c: Char, s: Scan) -> Scan:
  match s:
    case Scan{InCode{}, at, line, code, open, comments, lines}:
      Scan.in_code(glyph, at, line, code, open, comments, lines)
    case Scan{InComment{}, at, line, code, open, comments, lines}:
      Scan.in_comment(glyph, c, at, line, code, open, comments, lines)
    case Scan{InQuote{string, escaped}, at, line, code, open, comments, lines}:
      Scan.in_quote(string, escaped, glyph, at, line, code, open, comments, lines)

def Scan.go(text: String, s: Scan) -> Scan:
  match text:
    case SNil{}:
      s
    case SCon{+c, t}:
      Scan.go(t, Scan.step(Glyph.of(c), c, s))

def Scan.done(s: Scan) -> Scanned:
  match s:
    case Scan{InComment{}, at, line, code, open, comments, lines}:
      Scanned{
        List.reverse(&2, Comment, Comment.closed(open, at) <> comments),
        List.reverse(&2, Bool, code <> lines)
      }
    case Scan{mode, at, line, code, open, comments, lines}:
      Scanned{List.reverse(&2, Comment, comments), List.reverse(&2, Bool, code <> lines)}

def Scan.of(text: String) -> Scanned:
  Scan.done(Scan.go(text, Scan{InCode{}, 0, 0, False{}, Comment.none(), [], []}))

# Parsing
# =======
type Action is Data:
  Disable{}
  Expect{}

type Scope is Data:
  WholeFile{}
  Begin{}
  End{}
  NextLine{}
  SameLine{}

type Keyword is Data:
  Keyword{action: Action, scope: Scope}

# What a directive names: a rule, and the severity it pins, as written.
type Target is Data:
  Target{rule: String, pinned: Maybe<&2, String>}

# A directive as written, before its severity and rule are checked: its reasons are the texts after each `--`.
type Draft is Data:
  Draft{keyword: Keyword, target: Target, reasons: List<&2, String>}

# A directive: what it does, how far, the rule it names, the severity it pins, its comment, and its place among the
# file's comments.
type Directive is Data:
  Directive{
    action: Action,
    scope: Scope,
    rule: String,
    severity: Maybe<&2, Lint.Severity>,
    comment: Comment,
    index: U32
  }

# A comment that says bend-lint: a directive, or what is wrong with it.
type Said is Data:
  Said{directive: Directive}
  Wrong{comment: Comment, why: String}

def Action.show(a: Action) -> String:
  match a:
    case Disable{}:
      "disable"
    case Expect{}:
      "expect"

def Scope.show(s: Scope) -> String:
  match s:
    case WholeFile{}:
      "file"
    case Begin{}:
      "begin"
    case End{}:
      "end"
    case NextLine{}:
      "next"
    case SameLine{}:
      "line"

def Action.names() -> List<&2, Names.Named<Action>>:
  Names.named(~Action, ~Action.show, [Disable{}, Expect{}])

def Scope.names() -> List<&2, Names.Named<Scope>>:
  Names.named(~Scope, ~Scope.show, [WholeFile{}, Begin{}, End{}, NextLine{}, SameLine{}])

def Severity.pinned(severity: Maybe<&2, Lint.Severity>) -> String:
  Maybe.default(&2, String, Maybe.map(&2, Lint.Severity, String, Lint.Severity.show, severity), "")

def Severity.same(a: Maybe<&2, Lint.Severity>, b: Maybe<&2, Lint.Severity>) -> Bool:
  String.eq(Severity.pinned(a), Severity.pinned(b))

# The words of a text, split at blanks: the word so far, last first, and the words before it, last first.
type Words is Data:
  Words{word: String, out: List<&2, String>}

def Words.step(blank: Bool, c: Char, w: Words) -> Words:
  match blank w:
    case True{} Words{SNil{}, out}:
      Words{"", out}
    case True{} Words{SCon{h, t}, out}:
      Words{"", String.reverse(SCon{h, t}) <> out}
    case False{} Words{word, out}:
      Words{SCon{c, word}, out}

def Words.go(s: String, w: Words) -> Words:
  match s:
    case SNil{}:
      w
    case SCon{+c, t}:
      Words.go(t, Words.step(Char.is_eq(c, ' ') || Char.is_eq(c, '\t'), c, w))

def Words.done(w: Words) -> List<&2, String>:
  match w:
    case Words{SNil{}, out}:
      List.reverse(&2, String, out)
    case Words{SCon{h, t}, out}:
      List.reverse(&2, String, String.reverse(SCon{h, t}) <> out)

def Words.of(s: String) -> List<&2, String>:
  Words.done(Words.go(s, Words{"", []}))

def Draft.kind(parts: List<&2, String>) -> Maybe<&2, Keyword>:
  match parts:
    case Con{a, Con{s, Nil{}}}:
      do Maybe<&2, Keyword>:
        action: Action <- Names.lookup(Action, a, Action.names())
        scope: Scope <- Names.lookup(Scope, s, Scope.names())
        return Keyword{action, scope}
    case _:
      None{}

# Whether a rule id is two or more non-empty parts, split by /.
def Draft.rule_ok(parts: List<&2, String>) -> Bool:
  match parts:
    case Con{a, Con{b, rest}}:
      Bool.not(List.any(~&2, ~String, ~String.is_empty, Con{a, Con{b, rest}}))
    case _:
      False{}

# `rule@severity`, split at its @s.
def Draft.target(parts: List<&2, String>) -> Maybe<&2, Target>:
  match parts:
    case Con{+rule, Nil{}}:
      Lists.when(Target, Draft.rule_ok(String.split(rule, '/')), Target{rule, None{}})
    case Con{+rule, Con{p, rest}}:
      Lists.when(
        Target,
        Draft.rule_ok(String.split(rule, '/')),
        Target{rule, Some{String.join(p <> rest, "@")}}
      )
    case Nil{}:
      None{}

# The word that starts a disable's second reason: why it is not an expect.
def Draft.label() -> String:
  "not-expected-because:"

def Draft.part(part: List<&2, String>, out: List<&2, String>) -> List<&2, String>:
  String.join(List.reverse(&2, String, part), " ") <> out

# The reason so far (last first) and those before it (last first), with `word` read: the label starts another.
def Draft.reasons.step(
  dash: Bool,
  word: String,
  read: List<&2, String> & List<&2, String>
) -> List<&2, String>
  & List<&2, String>:
  match dash read:
    case True{} Tuple{part, out}:
      ([], Draft.part(part, out))
    case False{} Tuple{part, out}:
      (word <> part, out)

# The reasons in `words`, split at each label, in order, after what is `read`.
def Draft.reasons(
  words: List<&2, String>,
  read: List<&2, String> & List<&2, String>
) -> List<&2, String>:
  match words read:
    case Nil{} Tuple{part, out}:
      List.reverse(&2, String, Draft.part(part, out))
    case Con{+w, rest} _:
      Draft.reasons(rest, Draft.reasons.step(String.eq(w, Draft.label()), w, read))

# What comes after the rule: nothing, or `--` and the reasons.
def Draft.reason(rest: List<&2, String>) -> Maybe<&2, List<&2, String>>:
  match rest:
    case Nil{}:
      Some{[]}
    case Con{dash, more}:
      Lists.when(List<&2, String>, String.eq(dash, "--"), Draft.reasons(more, ([], [])))

# The draft of a directive's words, after `bend-lint:`.
def Draft.of(words: List<&2, String>) -> Maybe<&2, Draft>:
  match words:
    case Con{kind, Con{named, rest}}:
      do Maybe<&2, Draft>:
        k: Keyword <- Draft.kind(String.split(kind, '-'))
        t: Target <- Draft.target(String.split(named, '@'))
        r: List<&2, String> <- Draft.reason(rest)
        return Draft{k, t, r}
    case _:
      None{}

def Problem.pinned(pinned: Maybe<&2, String>) -> Maybe<&2, String>:
  match pinned:
    case Some{+p}:
      Lists.when(
        String,
        Maybe.is_none(&2, Lint.Severity, Names.lookup(Lint.Severity, p, Lint.Severity.names())),
        p ++ " is not a severity."
      )
    case None{}:
      None{}

def Problem.severity(action: Action, pinned: Bool, rule: String) -> Maybe<&2, String>:
  match action pinned:
    case Disable{} True{}:
      Some{"A disable takes no severity."}
    case Expect{} False{}:
      Some{"An expect pins a severity: " ++ rule ++ "@..."}
    case _ _:
      None{}

def Problem.reason(scope: Scope, reasons: List<&2, String>) -> Maybe<&2, String>:
  match scope reasons:
    case End{} Nil{}:
      None{}
    case End{} _:
      Some{"An end takes no reason; the begin has it."}
    case _ Con{r, more}:
      Lists.when(String, String.is_empty(r), "A reason is required, after `--`.")
    case _ Nil{}:
      Some{"A reason is required, after `--`."}

def Problem.because(action: Action, scope: Scope, reasons: List<&2, String>) -> Maybe<&2, String>:
  match action scope reasons:
    case Disable{} End{} _:
      None{}
    case Disable{} _ Con{r, Con{b, more}}:
      Lists.when(String, String.is_empty(b), "Say why it is not an expect, after " ++ Draft.label())
    case Disable{} _ _:
      Some{
        "A disable says why it is not an expect, after its reason: " ++ Draft.label() ++ " <why>"
      }
    case _ _ _:
      None{}

def Problem.line(scope: Scope, trailing: Bool) -> Maybe<&2, String>:
  match scope trailing:
    case SameLine{} False{}:
      Some{"A line directive must follow code on its line."}
    case _ _:
      None{}

def Problem.first(problems: List<&2, Maybe<&2, String>>) -> Maybe<&2, String>:
  match problems:
    case Nil{}:
      None{}
    case Con{Some{why}, rest}:
      Some{why}
    case Con{None{}, rest}:
      Problem.first(rest)

def Rule.reserved(+namespace: String) -> Bool:
  String.eq(namespace, "bend") || String.eq(namespace, "bend-lint")

def Said.checked(why: Maybe<&2, String>, draft: Draft, comment: Comment, index: U32) -> Said:
  match why draft:
    case Some{w} _:
      Wrong{comment, w}
    case None{} Draft{Keyword{action, scope}, Target{rule, pinned}, reasons}:
      Said{
        Directive{
          action,
          scope,
          rule,
          Maybe.bind(
            &2,
            String,
            Lint.Severity,
            pinned,
            p => Names.lookup(Lint.Severity, p, Lint.Severity.names())
          ),
          comment,
          index
        }
      }

# What a comment that holds `draft` (or not) says, checked against the rules there are.
def Said.of(
  draft: Maybe<&2, Draft>,
  trailing: Bool,
  comment: Comment,
  known: List<&2, String>,
  index: U32
) -> Said:
  match draft:
    case None{}:
      Wrong{
        comment,
        "Write `# bend-lint: <disable|expect>-<file|begin|end|next|line> <rule>[@severity] -- <reason>`, and, for a disable, "
          ++ Draft.label()
          ++ " <why> after it."
      }
    case Some{Draft{Keyword{+action, +scope}, Target{+rule, +pinned}, +reasons}}:
      Said.checked(
        Problem.first(
          [
            Problem.pinned(pinned),
            Problem.severity(action, Maybe.is_some(&2, String, pinned), rule),
            Problem.reason(scope, reasons),
            Problem.because(action, scope, reasons),
            Problem.line(scope, trailing),
            Lists.when(
              String,
              Rule.reserved(Strings.before(rule, '/')),
              rule ++ " findings cannot be suppressed."
            ),
            Lists.when(
              String,
              Bool.not(List.contains(~String, ~String.eq, known, rule)),
              "There is no rule " ++ rule ++ "."
            )
          ]
        ),
        Draft{Keyword{action, scope}, Target{rule, pinned}, reasons},
        comment,
        index
      )

def Draft.read.if(marked: Bool, text: String) -> Maybe<&2, Maybe<&2, Draft>>:
  match marked:
    case True{}:
      Some{Draft.of(Words.of(String.drop(text, 10n)))}
    case False{}:
      None{}

# What a comment's text says, if it says bend-lint:: a directive's draft, if it is one.
def Draft.read(+body: String) -> Maybe<&2, Maybe<&2, Draft>>:
  Draft.read.if(String.starts_with(String.trim_start(body), "bend-lint:"), String.trim_start(body))

def Said.read.of(
  draft: Maybe<&2, Maybe<&2, Draft>>,
  +comment: Comment,
  known: List<&2, String>,
  index: U32
) -> Maybe<&2, Said>:
  match draft comment:
    case Some{d} Comment{beg, end, line, +trailing, body}:
      Some{Said.of(d, trailing, Comment{beg, end, line, trailing, body}, known, index)}
    case None{} _:
      None{}

def Said.read(+comment: Comment, known: List<&2, String>, index: U32) -> Maybe<&2, Said>:
  match comment:
    case Comment{beg, end, line, trailing, +body}:
      Said.read.of(Draft.read(body), Comment{beg, end, line, trailing, body}, known, index)

# What the comments say, in order, each numbered; `out` holds those so far, last first.
def Said.all(
  comments: List<&2, Comment>,
  +known: List<&2, String>,
  +index: U32,
  out: List<&2, Said>
) -> List<&2, Said>:
  match comments:
    case Nil{}:
      List.reverse(&2, Said, out)
    case Con{c, rest}:
      Said.all(rest, known, (index + 1: U32), Lists.push(Said, Said.read(c, known, index), out))

# Pairing
# =======

# Where a begin was closed: its index, and the line of its end.
type Closed is Data:
  Closed{index: U32, line: U32}

# The begins open so far (latest first), the begins closed, and what is wrong (last first).
type Pairing is Data:
  Pairing{open: List<&2, Directive>, closed: List<&2, Closed>, wrong: List<&2, Said>}

# The latest open begin of an action and a rule.
def Open.latest(
  open: List<&2, Directive>,
  found: Maybe<&2, Directive>,
  +action: String,
  +rule: String
) -> Maybe<&2, Directive>:
  match open found:
    case _ Some{d}:
      Some{d}
    case Nil{} None{}:
      None{}
    case Con{Directive{+a, s, +r, sev, c, i}, rest} None{}:
      Open.latest(
        rest,
        Lists.when(
          Directive,
          String.eq(Action.show(a), action) && String.eq(r, rule),
          Directive{a, s, r, sev, c, i}
        ),
        action,
        rule
      )

def Open.keep(drop: Bool, d: Directive, rest: List<&2, Directive>) -> List<&2, Directive>:
  match drop:
    case True{}:
      rest
    case False{}:
      d <> rest

def Open.without(open: List<&2, Directive>, +index: U32) -> List<&2, Directive>:
  match open:
    case Nil{}:
      []
    case Con{Directive{a, s, r, sev, c, +i}, rest}:
      Open.keep(U32.is_eq(i, index), Directive{a, s, r, sev, c, i}, Open.without(rest, index))

def Pairing.closing(
  same: Bool,
  +index: U32,
  line: U32,
  rule: String,
  comment: Comment,
  p: Pairing
) -> Pairing:
  match same p:
    case True{} Pairing{open, closed, wrong}:
      Pairing{Open.without(open, index), Closed{index, line} <> closed, wrong}
    case False{} Pairing{open, closed, wrong}:
      Pairing{open, closed, Wrong{comment, "This end closes no begin of " ++ rule ++ "."} <> wrong}

def Pairing.close(begin: Maybe<&2, Directive>, end: Directive, p: Pairing) -> Pairing:
  match begin end p:
    case Some{
      Directive{a, s, r, sev, c, i}
    } Directive{ea, es, er, esev, Comment{b, e, +line, t, body}, ei} Pairing{open, closed, wrong}:
      Pairing.closing(
        Severity.same(sev, esev),
        i,
        line,
        er,
        Comment{b, e, line, t, body},
        Pairing{open, closed, wrong}
      )
    case None{} Directive{ea, es, er, esev, ec, ei} Pairing{open, closed, wrong}:
      Pairing{open, closed, Wrong{ec, "This end closes no begin of " ++ er ++ "."} <> wrong}

def Pairing.step(said: Said, p: Pairing) -> Pairing:
  match said p:
    case Said{Directive{a, Begin{}, r, sev, c, i}} Pairing{open, closed, wrong}:
      Pairing{Directive{a, Begin{}, r, sev, c, i} <> open, closed, wrong}
    case Said{Directive{+a, End{}, +r, sev, c, i}} Pairing{+open, closed, wrong}:
      Pairing.close(
        Open.latest(open, None{}, Action.show(a), r),
        Directive{a, End{}, r, sev, c, i},
        Pairing{open, closed, wrong}
      )
    case _ _:
      p

def Pairing.go(saids: List<&2, Said>, p: Pairing) -> Pairing:
  match saids:
    case Nil{}:
      p
    case Con{s, rest}:
      Pairing.go(rest, Pairing.step(s, p))

def Pairing.unclosed(open: List<&2, Directive>, wrong: List<&2, Said>) -> List<&2, Said>:
  match open:
    case Nil{}:
      wrong
    case Con{Directive{a, s, r, sev, c, i}, rest}:
      Pairing.unclosed(rest, Wrong{c, "This begin of " ++ r ++ " is never closed."} <> wrong)

# Covering
# ========

# A directive and the lines it covers, both ends included (from 1 to 0 covers none).
type Covering is Data:
  Covering{directive: Directive, from: U32, to: U32}

# The first line after `after` that holds code; `i` is the line of the head of `lines`.
def Lines.next_code(
  lines: List<&2, Bool>,
  found: Maybe<&2, U32>,
  +i: U32,
  +after: U32
) -> Maybe<&2, U32>:
  match lines found:
    case _ Some{x}:
      Some{x}
    case Nil{} None{}:
      None{}
    case Con{code, rest} None{}:
      Lines.next_code(rest, Lists.when(U32, code && U32.is_gt(i, after), i), (i + 1: U32), after)

def Closed.find(closed: List<&2, Closed>, found: Maybe<&2, U32>, +index: U32) -> Maybe<&2, U32>:
  match closed found:
    case _ Some{line}:
      Some{line}
    case Nil{} None{}:
      None{}
    case Con{Closed{i, line}, rest} None{}:
      Closed.find(rest, Lists.when(U32, U32.is_eq(i, index), line), index)

def Covering.next(d: Directive, found: Maybe<&2, U32>) -> Covering:
  match found:
    case Some{+l}:
      Covering{d, l, l}
    case None{}:
      Covering{d, 1, 0}

# The lines a directive covers; `last` is the file's last line.
def Covering.of(
  said: Said,
  lines: List<&2, Bool>,
  closed: List<&2, Closed>,
  last: U32
) -> Maybe<&2, Covering>:
  match said:
    case Said{Directive{a, WholeFile{}, r, sev, c, i}}:
      Some{Covering{Directive{a, WholeFile{}, r, sev, c, i}, 0, last}}
    case Said{Directive{a, SameLine{}, r, sev, Comment{b, e, +l, t, body}, i}}:
      Some{Covering{Directive{a, SameLine{}, r, sev, Comment{b, e, l, t, body}, i}, l, l}}
    case Said{Directive{a, NextLine{}, r, sev, Comment{b, e, +l, t, body}, i}}:
      Some{
        Covering.next(
          Directive{a, NextLine{}, r, sev, Comment{b, e, l, t, body}, i},
          Lines.next_code(lines, None{}, 0, l)
        )
      }
    case Said{Directive{a, Begin{}, r, sev, Comment{b, e, +l, t, body}, +i}}:
      Some{
        Covering{
          Directive{a, Begin{}, r, sev, Comment{b, e, l, t, body}, i},
          l,
          Maybe.default(&2, U32, Closed.find(closed, None{}, i), last)
        }
      }
    case _:
      None{}

def Covering.all(
  saids: List<&2, Said>,
  +lines: List<&2, Bool>,
  +closed: List<&2, Closed>,
  +last: U32,
  out: List<&2, Covering>
) -> List<&2, Covering>:
  match saids:
    case Nil{}:
      List.reverse(&2, Covering, out)
    case Con{s, rest}:
      Covering.all(
        rest,
        lines,
        closed,
        last,
        Lists.push(Covering, Covering.of(s, lines, closed, last), out)
      )

def Covering.pins(
  action: Action,
  pinned: Maybe<&2, Lint.Severity>,
  severity: Lint.Severity
) -> Bool:
  match action:
    case Disable{}:
      True{}
    case Expect{}:
      Severity.same(pinned, Some{severity})

# Whether a covering covers a finding of `rule` and `severity` on line `row`.
def Covering.covers(rule: String, severity: Lint.Severity, +row: U32, covering: Covering) -> Bool:
  match covering:
    case Covering{Directive{action, scope, r, sev, c, i}, from, to}:
      String.eq(
        r,
        rule
      )
        && U32.is_le(from, row)
        && U32.is_le(row, to)
        && Covering.pins(action, sev, severity)

def Covering.hit(hit: Bool, c: Covering, out: List<&2, U32>) -> List<&2, U32>:
  match hit c:
    case True{} Covering{Directive{a, s, r, sev, comment, i}, from, to}:
      i <> out
    case False{} _:
      out

def Covering.hits(
  coverings: List<&2, Covering>,
  +rule: String,
  +severity: Lint.Severity,
  +row: U32,
  out: List<&2, U32>
) -> List<&2, U32>:
  match coverings:
    case Nil{}:
      out
    case Con{+c, rest}:
      Covering.hits(
        rest,
        rule,
        severity,
        row,
        Covering.hit(Covering.covers(rule, severity, row, c), c, out)
      )

# Applying
# ========

# The findings so far: those that stay, those a directive covers (both last first), and the directives that covered
# one.
type Applied is Data:
  Applied{kept: List<&2, Lint.Found>, suppressed: List<&2, Lint.Found>, used: List<&2, U32>}

# A file's findings after its directives: those that stay, then the findings about its directives, and those a
# directive covers.
type Suppressed is Data:
  Suppressed{kept: List<&2, Lint.Found>, suppressed: List<&2, Lint.Found>}

def Applied.add(hits: List<&2, U32>, found: Lint.Found, a: Applied) -> Applied:
  match hits a:
    case Nil{} Applied{kept, suppressed, used}:
      Applied{found <> kept, suppressed, used}
    case Con{h, t} Applied{kept, suppressed, used}:
      Applied{kept, found <> suppressed, Lists.onto(&2, U32, Con{h, t}, used)}

# The findings, each with where it starts (`at`, in order), sorted by the directives that cover their lines.
def Applied.go(
  founds: List<&2, Lint.Found>,
  at: List<&2, Places.Position>,
  +coverings: List<&2, Covering>,
  a: Applied
) -> Applied:
  match founds at:
    case Con{
      Lint.Found{+rule, Lint.Finding{+severity, span, message, fixes}},
      rest
    } Con{Places.Position{line, column}, more}:
      Applied.go(
        rest,
        more,
        coverings,
        Applied.add(
          Covering.hits(coverings, rule, severity, (line - 1: U32), []),
          Lint.Found{rule, Lint.Finding{severity, span, message, fixes}},
          a
        )
      )
    case _ _:
      a

def Unmet.add(
  used: Bool,
  action: Action,
  rule: String,
  pinned: Maybe<&2, Lint.Severity>,
  span: Lint.Span,
  out: List<&2, Lint.Found>
) -> List<&2, Lint.Found>:
  match used action:
    case True{} _:
      out
    case False{} Expect{}:
      Lint.Found{
        "bend-lint/unmet-expectation",
        Lint.Finding{
          Lint.Error{},
          span,
          "Expected a "
            ++ rule
            ++ "@"
            ++ Severity.pinned(pinned)
            ++ " finding on the lines this covers; none.",
          []
        }
      }
        <> out
    case False{} Disable{}:
      Lint.Found{
        "bend-lint/unused-disable",
        Lint.Finding{
          Lint.Warning{},
          span,
          "This disables " ++ rule ++ ", but nothing on the lines it covers needs it.",
          []
        }
      }
        <> out

# The findings about the directives that nothing used: an expect not met, a disable that covered nothing.
def Unmet.go(
  coverings: List<&2, Covering>,
  +used: List<&2, U32>,
  +path: String,
  out: List<&2, Lint.Found>
) -> List<&2, Lint.Found>:
  match coverings:
    case Nil{}:
      List.reverse(&2, Lint.Found, out)
    case Con{Covering{Directive{a, s, r, sev, Comment{b, e, l, t, body}, i}, from, to}, rest}:
      Unmet.go(
        rest,
        used,
        path,
        Unmet.add(List.contains(~U32, ~U32.is_eq, used, i), a, r, sev, Lint.Span{path, b, e}, out)
      )

def Wrong.found(
  saids: List<&2, Said>,
  +path: String,
  out: List<&2, Lint.Found>
) -> List<&2, Lint.Found>:
  match saids:
    case Nil{}:
      List.reverse(&2, Lint.Found, out)
    case Con{Wrong{Comment{b, e, l, t, body}, why}, rest}:
      Wrong.found(
        rest,
        path,
        Lint.Found{
          "bend-lint/directive",
          Lint.Finding{Lint.Error{}, Lint.Span{path, b, e}, why, []}
        }
          <> out
      )
    case Con{s, rest}:
      Wrong.found(rest, path, out)

# Directives
# ==========

# A linted file: its path and text, the ids of the rules there are, and those of the rules that ran on it. A rule
# turned off did not run, so its directives are never unused.
type Linted is Data:
  Linted{path: String, text: String, known: List<&2, String>, ran: List<&2, String>}

def Linted.path(linted: Linted) -> String:
  match linted:
    case Linted{path, text, known, ran}:
      path

def Linted.text(linted: Linted) -> String:
  match linted:
    case Linted{path, text, known, ran}:
      text

def Linted.known(linted: Linted) -> List<&2, String>:
  match linted:
    case Linted{path, text, known, ran}:
      known

def Linted.ran(linted: Linted) -> List<&2, String>:
  match linted:
    case Linted{path, text, known, ran}:
      ran

def Covering.keep(ran: Bool, c: Covering, out: List<&2, Covering>) -> List<&2, Covering>:
  match ran:
    case True{}:
      c <> out
    case False{}:
      out

def Covering.ran(
  coverings: List<&2, Covering>,
  +ran: List<&2, String>,
  out: List<&2, Covering>
) -> List<&2, Covering>:
  match coverings:
    case Nil{}:
      List.reverse(&2, Covering, out)
    case Con{Covering{Directive{a, s, +r, sev, c, i}, from, to}, rest}:
      Covering.ran(
        rest,
        ran,
        Covering.keep(
          List.contains(~String, ~String.eq, ran, r),
          Covering{Directive{a, s, r, sev, c, i}, from, to},
          out
        )
      )

def done(
  a: Applied,
  coverings: List<&2, Covering>,
  unpaired: List<&2, Said>,
  saids: List<&2, Said>,
  +linted: Linted
) -> Suppressed:
  match a:
    case Applied{kept, suppressed, used}:
      Suppressed{
        Lists.concat(
          &2,
          Lint.Found,
          [
            List.reverse(&2, Lint.Found, kept),
            Wrong.found(saids, Linted.path(linted), []),
            Wrong.found(List.reverse(&2, Said, unpaired), Linted.path(linted), []),
            Unmet.go(Covering.ran(coverings, Linted.ran(linted), []), used, Linted.path(linted), [])
          ]
        ),
        List.reverse(&2, Lint.Found, suppressed)
      }

def covered(
  +coverings: List<&2, Covering>,
  unpaired: List<&2, Said>,
  saids: List<&2, Said>,
  +linted: Linted,
  +founds: List<&2, Lint.Found>
) -> Suppressed:
  done(
    Applied.go(
      founds,
      Places.positions(Linted.text(linted), Lint.Found.offsets(founds, [])),
      coverings,
      Applied{[], [], []}
    ),
    coverings,
    unpaired,
    saids,
    linted
  )

def paired(
  p: Pairing,
  +saids: List<&2, Said>,
  +lines: List<&2, Bool>,
  linted: Linted,
  founds: List<&2, Lint.Found>
) -> Suppressed:
  match p:
    case Pairing{open, closed, wrong}:
      covered(
        Covering.all(
          saids,
          lines,
          closed,
          (U32.from_nat(Lists.length(&2, Bool, lines)) - 1: U32),
          []
        ),
        Pairing.unclosed(open, wrong),
        saids,
        linted,
        founds
      )

def said(
  +saids: List<&2, Said>,
  lines: List<&2, Bool>,
  linted: Linted,
  founds: List<&2, Lint.Found>
) -> Suppressed:
  paired(Pairing.go(saids, Pairing{[], [], []}), saids, lines, linted, founds)

def scanned(scanned: Scanned, +linted: Linted, founds: List<&2, Lint.Found>) -> Suppressed:
  match scanned:
    case Scanned{comments, lines}:
      said(Said.all(comments, Linted.known(linted), 0, []), lines, linted, founds)

def when(has: Bool, +linted: Linted, founds: List<&2, Lint.Found>) -> Suppressed:
  match has:
    case True{}:
      scanned(Scan.of(Linted.text(linted)), linted, founds)
    case False{}:
      Suppressed{founds, []}

# Whether `text` has a directive's mark, "bend-lint:". Only a 'b' starts a comparison, so it is one pass.
def marked(text: String, found: Bool) -> Bool:
  match text found:
    case _ True{}:
      True{}
    case SNil{} False{}:
      False{}
    case SCon{'b', +rest} False{}:
      marked(rest, String.starts_with(rest, "end-lint:"))
    case SCon{c, rest} False{}:
      marked(rest, False{})

def apply(+linted: Linted, founds: List<&2, Lint.Found>) -> Suppressed:
  when(marked(Linted.text(linted), False{}), linted, founds)
