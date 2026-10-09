# format/layout, in Bend: the twin of format.ts, which explains the layout.
# Both rules give the same text; rules/format.test.ts runs each.
# Run: bun src/lint.ts file.bend --rules rules/format.bend --fix
#
# A String is a JS string at run time: ++ is native, and a match on SCon
# reads one character and slices off the rest. So the lexer reads the text
# once, tokens carry what the layout asks of them, and docs carry widths.
#
# Each loop is go(input, state): a step that does not recurse makes the next
# state, so every loop recurses on a smaller part of its input. The lexer
# and the printer recurse on fuel instead: more steps than they can need.
import Base
import ../src/bend/lint.bend as Lint

# Types
# =====
type Lex is Data:
  Code{}
  Literal{}
  Comment{}
  Newline{}

# The spellings the layout tells apart; Word{} is any other, Inc{} ends in n+.
type Sym is Data:
  Word{}
  Comma{}
  Semi{}
  Colon{}
  Ques{}
  Bang{}
  Dot{}
  Tilde{}
  At{}
  Bslash{}
  Plus{}
  Minus{}
  Star{}
  Slash{}
  Pct{}
  Caret{}
  Amp{}
  Bar{}
  Lpar{}
  Rpar{}
  Lbrk{}
  Rbrk{}
  Lbrc{}
  Rbrc{}
  Lt{}
  Gt{}
  Assign{}
  Arrow{}
  Concat{}
  AndAnd{}
  OrOr{}
  Meet{}
  BitAnd{}
  BitOr{}
  BitXor{}
  Shl{}
  Shr{}
  Cons{}
  Le{}
  Ge{}
  EqEq{}
  Ne{}
  Inc{}
  KwReturn{}
  KwCase{}
  KwMatch{}
  KwFor{}
  KwExs{}
  KwIs{}
  KwDo{}
  KwDef{}
  KwType{}
  KwLaw{}
  KwImport{}

# Offsets and columns count code points. name: whether the text matches
# /^[\w.]+$/. tail: for a literal across lines, how many characters follow
# its last newline. from: the text from the token on.
type Token is Data:
  Token{
    text: String,
    beg: U32,
    end: U32,
    col: U32,
    lex: Lex,
    sym: Sym,
    name: Bool,
    tail: Maybe<&2, U32>,
    from: String
  }

# What the lexer read: the end of the text, one whitespace character, or a
# token; with the text after it and its last character.
type Scan is Data:
  Eof{}
  Blank{rest: String, last: Char, len: U32}
  Tok{
    text: String,
    len: U32,
    rest: String,
    last: Char,
    lex: Lex,
    sym: Sym,
    name: Bool,
    tail: Maybe<&2, U32>
  }

# Characters read by run: their text and count, the text after them, and
# the last one.
type Run is Data:
  Run{text: String, len: U32, rest: String, last: Char}

# What the next character of a literal is: inside it, escaped, or past it.
type Quote is Data:
  Inside{}
  Escaped{}
  Shut{}

type Class is Data:
  IsBlank{}
  IsHead{}
  IsDigit{}
  IsOther{}

type Tree is Data:
  Leaf{token: Token}
  Group{open: Token, close: Token, children: List<&2, Tree>, block: Bool}

# A group the tree has opened: the sym that closes it, children last first,
# and whether a child is a token that makes it a block.
type Open is Data:
  Open{token: Token, close: Sym, children: List<&2, Tree>, block: Bool}

type Built is Data:
  Built{stack: List<&2, Open>, root: List<&2, Tree>}

# A doc printed flat: its width up to the first break it cannot lose (a
# hard line, or a newline in text), and whether it has one.
type Flat is Data:
  Flat{width: U32, brk: Bool}

# Str: text without its trailing whitespace, that whitespace, the width, and
# how many characters follow the last newline, if any. Line: the text and
# width when flat. Grp, Nest and Cat keep their Flat; Cat its docs last
# first.
type Doc is Data:
  Str{body: String, blank: String, width: U32, tail: Maybe<&2, U32>}
  Line{flat: String, width: U32, hard: Bool, offset: U32}
  Grp{doc: Doc, flat: Flat}
  Nest{doc: Doc, amount: U32, flat: Flat}
  Cat{docs: List<&2, Doc>, flat: Flat}

type Measure is Data:
  Measure{width: U32, tail: Maybe<&2, U32>, keep: U32}

# How build reads a list of trees: a record, a group's children as a raw
# block, as comma-separated parts, or a group with no children.
type Mode is Data:
  Plain{}
  Block{open: Token, close: Token}
  Parts{open: Token, close: Token}
  Bare{open: Token, close: Token}

# A sequence being built: its docs last first, the docs of an operator
# chain, the previous tree, the indentation levels deepest first, and
# whether the rest of a run of newlines is skipped.
type Seq is Data:
  Seq{
    out: List<&2, Doc>,
    chain: Maybe<&2, List<&2, Doc>>,
    prev: Maybe<&2, Tree>,
    levels: List<&2, U32>,
    skip: Bool
  }

# A comma-separated part: whether it holds only newlines, and whether its
# last other tree ends in a comment.
type Part is Data:
  Part{doc: Doc, newlines: Bool, comment: Bool}

# A group's parts so far, last first; the current part's flags; whether the
# next tree ends the current part; whether a child starts with a comment.
type Split is Data:
  Split{parts: List<&2, Part>, newlines: Bool, comment: Bool, attach: Bool, comments: Bool}

type State is Data:
  State{seq: Seq, split: Split}

# What a child of a group does to its parts.
type Act is Data:
  Add{}
  AddAttach{}
  AddEnd{}
  End{}

type Job is Data:
  Job{doc: Doc, indent: U32, flat: Bool}

# The printer: jobs left, the text so far as chunks last first, the
# whitespace not written yet (dropped at a break or at the end), and the
# column.
type Print is Data:
  Print{jobs: List<&2, Job>, out: List<&2, String>, pending: String, col: U32}

type Fit is Data:
  Go{jobs: List<&2, Job>, left: U32}
  Stop{fits: Bool}

# Records so far, last first, and the current record, last first.
type Recs is Data:
  Recs{done: List<&2, List<&2, Tree>>, current: List<&2, Tree>}

# A declaration record cut after its first colon, if it has one.
type Cut is Data:
  Cut{before: List<&2, Tree>, after: List<&2, Tree>, found: Bool}

type Hash is Data:
  Hash{before: String, comment: Maybe<&2, String>}

# The rows so far, last first, and what the next record needs from them.
type Rows is Data:
  Rows{levels: List<&2, U32>, blank: Bool, unsafe: Bool, comment: Bool, rows: List<&2, String>}

# width: None{} for "never".
type Settings is Data:
  Settings{tab: U32, width: Maybe<&2, U32>, newline: String}

# Constants
# =========

# Fuel per code point of a record: more printer steps than any doc needs.
def fuel_per_point() -> U32:
  64

# Functions
# =========

# Text
# ----

# Whitespace, as Bend's parser reads it.
def is_blank(+c: Char) -> Bool:
  match c:
    case ' ':
      True{}
    case '\t':
      True{}
    case '\n':
      True{}
    case '\r':
      True{}
    case _:
      False{}

def is_head(+c: Char) -> Bool:
  Char.is_alpha(c) || Char.is_eq(c, '_')

def is_word(+c: Char) -> Bool:
  is_head(c) || Char.is_digit(c)

def head_is(~test: @+c: Char -> Bool, s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{+c, rest}:
      test(c)

def char(c: Char) -> String:
  SCon{c, SNil{}}

def drop_blank.go(s: String, blank: Bool) -> String:
  match s blank:
    case SNil{} _:
      SNil{}
    case SCon{c, rest} False{}:
      SCon{c, rest}
    case SCon{c, +rest} True{}:
      drop_blank.go(rest, head_is(~is_blank, rest))

def drop_blank(+s: String) -> String:
  drop_blank.go(s, head_is(~is_blank, s))

def trim_end(s: String) -> String:
  String.reverse(drop_blank(String.reverse(s)))

def pad(n: Nat, out: String) -> String:
  match n:
    case 0n:
      out
    case 1n+k:
      pad(k, SCon{' ', out})

# Base's String.take and String.eq are not tail-recursive, so long text
# would overflow the stack; take and same are.
def take.go(n: Nat, s: String, acc: String) -> String:
  match n s:
    case 1n+k SCon{c, rest}:
      take.go(k, rest, SCon{c, acc})
    case _ _:
      String.reverse(acc)

def take(s: String, n: Nat) -> String:
  take.go(n, s, "")

# ok: whether the characters so far were the same.
def same.go(a: String, b: String, ok: Bool) -> Bool:
  match a b ok:
    case SCon{x, xs} SCon{y, ys} True{}:
      same.go(xs, ys, Char.is_eq(x, y))
    case SNil{} SNil{} done:
      done
    case _ _ _:
      False{}

def same(a: String, b: String) -> Bool:
  same.go(a, b, True{})

# Lexer
# -----
#
# A branch that uses a string or a character its match took apart gets it
# rebuilt: a string as character + rest, a rope that the next read copies
# whole, and a character bit by bit. So a def that needs the whole value in
# a branch takes it twice, as keep, and matches the other copy.
def not_line_end(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{'\n', rest}:
      False{}
    case SCon{'\r', rest}:
      False{}
    case _:
      True{}

def digit_at(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{c, rest}:
      Char.is_digit(c)

def ident_at.of(dot: Bool, +c: Char, rest: String) -> Bool:
  match dot:
    case True{}:
      head_is(~is_head, rest)
    case False{}:
      is_word(c)

# A word character, or a dot before the start of a word.
def ident_at(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{+c, rest}:
      ident_at.of(Char.is_eq(c, '.'), c, rest)

# Reads characters while test holds, after text; test sees the text from
# each character on, so it can look ahead.
def scan(
  ~test: String -> Bool,
  s: String,
  keep: String,
  ok: Bool,
  text: String,
  n: U32,
  last: Char
) -> Run:
  match s ok:
    case SCon{+c, +rest} True{}:
      scan(~test, rest, rest, test(rest), text ++ char(c), (n + 1: U32), c)
    case _ _:
      Run{text, n, keep, last}

def tok(r: Run, sym: Sym, name: Bool) -> Scan:
  match r:
    case Run{text, len, rest, last}:
      Tok{text, len, rest, last, Code{}, sym, name, None{}}

def fixed(text: String, len: U32, rest: String, last: Char, sym: Sym) -> Scan:
  Tok{text, len, rest, last, Code{}, sym, False{}, None{}}

def keyword.is(+text: String, word: String, sym: Sym) -> Sym:
  Bool.pick(Sym, same(text, word), sym, Word{})

def keyword(text: String, +keep: String) -> Sym:
  match text:
    case SCon{'r', rest}:
      keyword.is(keep, "return", KwReturn{})
    case SCon{'c', rest}:
      keyword.is(keep, "case", KwCase{})
    case SCon{'m', rest}:
      keyword.is(keep, "match", KwMatch{})
    case SCon{'f', rest}:
      keyword.is(keep, "for", KwFor{})
    case SCon{'e', rest}:
      keyword.is(keep, "exs", KwExs{})
    case SCon{'i', rest}:
      Bool.pick(Sym, same(keep, "is"), KwIs{}, keyword.is(keep, "import", KwImport{}))
    case SCon{'d', rest}:
      Bool.pick(Sym, same(keep, "do"), KwDo{}, keyword.is(keep, "def", KwDef{}))
    case SCon{'t', rest}:
      keyword.is(keep, "type", KwType{})
    case SCon{'l', rest}:
      keyword.is(keep, "law", KwLaw{})
    case _:
      Word{}

def ident(r: Run) -> Scan:
  match r:
    case Run{+text, len, rest, last}:
      Tok{text, len, rest, last, Code{}, keyword(text, text), True{}, None{}}

def number.tok(r: Run, inc: Bool, name: Bool) -> Scan:
  tok(r, Bool.pick(Sym, inc, Inc{}, Word{}), name)

def exponent.digits(
  go: Bool,
  +rest: String,
  mark: String,
  +k: U32,
  keep: String,
  text: String,
  +n: U32,
  last: Char,
  signed: Bool
) -> Scan:
  match go:
    case True{}:
      number.tok(
        scan(~digit_at, rest, rest, True{}, text ++ mark, (n + k: U32), last),
        False{},
        Bool.not(signed)
      )
    case False{}:
      number.tok(Run{text, n, keep, last}, False{}, True{})

def exponent.sign(
  rest: String,
  +again: String,
  mark: String,
  +keep: String,
  text: String,
  +n: U32,
  last: Char
) -> Scan:
  match rest:
    case SCon{'+', +r}:
      exponent.digits(digit_at(r), r, mark ++ "+", 2, keep, text, n, last, True{})
    case SCon{'-', +r}:
      exponent.digits(digit_at(r), r, mark ++ "-", 2, keep, text, n, last, True{})
    case _:
      exponent.digits(digit_at(again), again, mark, 1, keep, text, n, last, False{})

def exponent.of(s: String, +keep: String, text: String, +n: U32, last: Char) -> Scan:
  match s:
    case SCon{'e', +rest}:
      exponent.sign(rest, rest, "e", keep, text, n, last)
    case SCon{'E', +rest}:
      exponent.sign(rest, rest, "E", keep, text, n, last)
    case _:
      number.tok(Run{text, n, keep, last}, False{}, True{})

# After a fraction: [eE][+-]?\d+, if it is there.
def exponent(r: Run) -> Scan:
  match r:
    case Run{text, n, +s, last}:
      exponent.of(s, s, text, n, last)

def fraction(go: Bool, +rest: String, keep: String, text: String, +n: U32, last: Char) -> Scan:
  match go:
    case True{}:
      exponent(scan(~digit_at, rest, rest, True{}, text ++ ".", (n + 1: U32), '.'))
    case False{}:
      number.tok(Run{text, n, keep, last}, False{}, True{})

# After "n": n+, or n alone.
def number.inc(s: String, +keep: String, text: String, +n: U32) -> Scan:
  match s:
    case SCon{'+', rest}:
      number.tok(Run{text ++ "n+", (n + 2: U32), rest, '+'}, True{}, False{})
    case _:
      number.tok(Run{text ++ "n", (n + 1: U32), keep, 'n'}, False{}, True{})

def number.of(s: String, +keep: String, text: String, +n: U32, last: Char) -> Scan:
  match s:
    case SCon{'n', +rest}:
      number.inc(rest, rest, text, n)
    case SCon{'.', +rest}:
      fraction(digit_at(rest), rest, keep, text, n, last)
    case _:
      number.tok(Run{text, n, keep, last}, False{}, True{})

# After a number's digits: n, n+, or a fraction and its exponent.
def number(r: Run) -> Scan:
  match r:
    case Run{text, n, +s, last}:
      number.of(s, s, text, n, last)

def tail_after(c: Char, tail: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match c tail:
    case '\n' _:
      Some{0}
    case _ Some{t}:
      Some{(t + 1: U32)}
    case _ None{}:
      None{}

def quote_after(+c: Char, +quote: Char) -> Quote:
  Bool.pick(
    Quote,
    Char.is_eq(c, '\\'),
    Escaped{},
    Bool.pick(Quote, Char.is_eq(c, quote), Shut{}, Inside{})
  )

def literal(
  s: String,
  keep: String,
  +quote: Char,
  at: Quote,
  text: String,
  n: U32,
  last: Char,
  tail: Maybe<&2, U32>
) -> Scan:
  match s at:
    case SCon{+c, +rest} Inside{}:
      literal(
        rest,
        rest,
        quote,
        quote_after(c, quote),
        text ++ char(c),
        (n + 1: U32),
        c,
        tail_after(c, tail)
      )
    case SCon{+c, +rest} Escaped{}:
      literal(rest, rest, quote, Inside{}, text ++ char(c), (n + 1: U32), c, tail_after(c, tail))
    case _ _:
      Tok{text, n, keep, last, Literal{}, Word{}, False{}, tail}

def class_of(+c: Char) -> Class:
  Bool.pick(
    Class,
    is_blank(c),
    IsBlank{},
    Bool.pick(Class, is_head(c), IsHead{}, Bool.pick(Class, Char.is_digit(c), IsDigit{}, IsOther{}))
  )

def single(c: Char) -> Sym:
  match c:
    case ',':
      Comma{}
    case ';':
      Semi{}
    case ':':
      Colon{}
    case '?':
      Ques{}
    case '~':
      Tilde{}
    case '@':
      At{}
    case '\\':
      Bslash{}
    case '*':
      Star{}
    case '/':
      Slash{}
    case '%':
      Pct{}
    case '^':
      Caret{}
    case '(':
      Lpar{}
    case ')':
      Rpar{}
    case '[':
      Lbrk{}
    case ']':
      Rbrk{}
    case '{':
      Lbrc{}
    case '}':
      Rbrc{}
    case _:
      Word{}

def lex.other(class: Class, +c: Char, +rest: String) -> Scan:
  match class:
    case IsBlank{}:
      Blank{rest, c, 1}
    case IsHead{}:
      ident(scan(~ident_at, rest, rest, ident_at(rest), char(c), 1, c))
    case IsDigit{}:
      number(scan(~digit_at, rest, rest, digit_at(rest), char(c), 1, c))
    case IsOther{}:
      fixed(char(c), 1, rest, c, single(c))

def lex.char(s: String) -> Scan:
  match s:
    case SNil{}:
      Eof{}
    case SCon{+c, rest}:
      lex.other(class_of(c), c, rest)

def lex.dash(word: Bool, keep: String, r: String) -> Scan:
  match word:
    case True{}:
      fixed("<", 1, keep, '<', Lt{})
    case False{}:
      fixed("<-", 2, r, '-', Word{})

def lex.lt(rest: String, +keep: String, +prev: Char) -> Scan:
  match rest:
    case SCon{'&', SCon{'>', r}}:
      fixed("<&>", 3, r, '>', Meet{})
    case SCon{'-', r}:
      lex.dash(is_word(prev) || Char.is_eq(prev, '.'), keep, r)
    case SCon{'=', r}:
      fixed("<=", 2, r, '=', Le{})
    case SCon{'<', r}:
      fixed("<<", 2, r, '<', Shl{})
    case SCon{'>', r}:
      fixed("<>", 2, r, '>', Cons{})
    case _:
      fixed("<", 1, keep, '<', Lt{})

def lex.shr(blank: Bool, keep: String, r: String) -> Scan:
  match blank:
    case True{}:
      fixed(">>", 2, r, '>', Shr{})
    case False{}:
      fixed(">", 1, keep, '>', Gt{})

def lex.gt(rest: String, +keep: String, +prev: Char) -> Scan:
  match rest:
    case SCon{'>', r}:
      lex.shr(is_blank(prev), keep, r)
    case SCon{'=', r}:
      fixed(">=", 2, r, '=', Ge{})
    case _:
      fixed(">", 1, keep, '>', Gt{})

def lex.dot(rest: String, +keep: String) -> Scan:
  match rest:
    case SCon{'&', SCon{'.', r}}:
      fixed(".&.", 3, r, '.', BitAnd{})
    case SCon{'|', SCon{'.', r}}:
      fixed(".|.", 3, r, '.', BitOr{})
    case SCon{'^', SCon{'.', r}}:
      fixed(".^.", 3, r, '.', BitXor{})
    case _:
      Tok{".", 1, keep, '.', Code{}, Dot{}, True{}, None{}}

def lex.minus(rest: String, +keep: String) -> Scan:
  match rest:
    case SCon{'>', r}:
      fixed("->", 2, r, '>', Arrow{})
    case _:
      fixed("-", 1, keep, '-', Minus{})

def lex.eq(rest: String, +keep: String) -> Scan:
  match rest:
    case SCon{'=', r}:
      fixed("==", 2, r, '=', EqEq{})
    case SCon{'>', r}:
      fixed("=>", 2, r, '>', Word{})
    case _:
      fixed("=", 1, keep, '=', Assign{})

def lex.bang(rest: String, +keep: String) -> Scan:
  match rest:
    case SCon{'=', r}:
      fixed("!=", 2, r, '=', Ne{})
    case _:
      fixed("!", 1, keep, '!', Bang{})

def lex.amp(rest: String, +keep: String) -> Scan:
  match rest:
    case SCon{'&', r}:
      fixed("&&", 2, r, '&', AndAnd{})
    case SCon{'0', r}:
      fixed("&0", 2, r, '0', Word{})
    case SCon{'1', r}:
      fixed("&1", 2, r, '1', Word{})
    case SCon{'2', r}:
      fixed("&2", 2, r, '2', Word{})
    case _:
      fixed("&", 1, keep, '&', Amp{})

def lex.bar(rest: String, +keep: String) -> Scan:
  match rest:
    case SCon{'|', r}:
      fixed("||", 2, r, '|', OrOr{})
    case _:
      fixed("|", 1, keep, '|', Bar{})

def lex.plus(rest: String, +keep: String) -> Scan:
  match rest:
    case SCon{'+', r}:
      fixed("++", 2, r, '+', Concat{})
    case _:
      fixed("+", 1, keep, '+', Plus{})

def comment(r: Run) -> Scan:
  match r:
    case Run{text, len, rest, last}:
      Tok{text, len, rest, last, Comment{}, Word{}, False{}, None{}}

# The token at the start of s; prev is the character before it.
# A run of whitespace on one line.
def blanks(s: String, keep: String, n: U32, last: Char) -> Scan:
  match s:
    case SCon{' ', +rest}:
      blanks(rest, rest, (n + 1: U32), ' ')
    case SCon{'\t', +rest}:
      blanks(rest, rest, (n + 1: U32), '\t')
    case SCon{'\r', +rest}:
      blanks(rest, rest, (n + 1: U32), '\r')
    case _:
      Blank{keep, last, n}

def lex.token(s: String, +keep: String, +prev: Char) -> Scan:
  match s:
    case SNil{}:
      Eof{}
    case SCon{' ', +rest}:
      blanks(rest, rest, 1, ' ')
    case SCon{'\n', rest}:
      Tok{"\n", 1, rest, '\n', Newline{}, Word{}, False{}, None{}}
    case SCon{'#', +rest}:
      comment(scan(~not_line_end, rest, rest, not_line_end(rest), "#", 1, '#'))
    case SCon{'"', +rest}:
      literal(rest, rest, '"', Inside{}, "\"", 1, '"', None{})
    case SCon{'\'', +rest}:
      literal(rest, rest, '\'', Inside{}, "'", 1, '\'', None{})
    case SCon{'<', +rest}:
      lex.lt(rest, rest, prev)
    case SCon{'>', +rest}:
      lex.gt(rest, rest, prev)
    case SCon{'.', +rest}:
      lex.dot(rest, rest)
    case SCon{'-', +rest}:
      lex.minus(rest, rest)
    case SCon{'=', +rest}:
      lex.eq(rest, rest)
    case SCon{'!', +rest}:
      lex.bang(rest, rest)
    case SCon{'&', +rest}:
      lex.amp(rest, rest)
    case SCon{'|', +rest}:
      lex.bar(rest, rest)
    case SCon{'+', +rest}:
      lex.plus(rest, rest)
    case _:
      lex.char(keep)

def next_col(lex: Lex, tail: Maybe<&2, U32>, +col: U32, +len: U32) -> U32:
  match lex tail:
    case Newline{} _:
      0
    case _ Some{t}:
      t
    case _ None{}:
      (col + len: U32)

# Each step reads at least one character, so the text's length is fuel.
def lex.go(
  fuel: Nat,
  sc: Scan,
  from: String,
  +at: U32,
  +col: U32,
  acc: List<&2, Token>
) -> List<&2, Token>:
  match fuel sc:
    case 1n+k Tok{text, +len, +rest, last, +lex, sym, name, +tail}:
      lex.go(
        k,
        lex.token(rest, rest, last),
        rest,
        (at + len: U32),
        next_col(lex, tail, col, len),
        Con{Token{text, at, (at + len: U32), col, lex, sym, name, tail, from}, acc}
      )
    case 1n+k Blank{+rest, last, +len}:
      lex.go(k, lex.token(rest, rest, last), rest, (at + len: U32), (col + len: U32), acc)
    case _ _:
      List.reverse(&2, Token, acc)

def tokens(+s: String) -> List<&2, Token>:
  lex.go(1n+String.length(s), lex.token(s, s, '\0'), s, 0, 0, [])

# Tokens
# ------
def Token.text(t: Token) -> String:
  match t:
    case Token{text, beg, end, col, lex, sym, name, tail, from}:
      text

def Token.beg(t: Token) -> U32:
  match t:
    case Token{text, beg, end, col, lex, sym, name, tail, from}:
      beg

def Token.end(t: Token) -> U32:
  match t:
    case Token{text, beg, end, col, lex, sym, name, tail, from}:
      end

def Token.col(t: Token) -> U32:
  match t:
    case Token{text, beg, end, col, lex, sym, name, tail, from}:
      col

def Token.sym(t: Token) -> Sym:
  match t:
    case Token{text, beg, end, col, lex, sym, name, tail, from}:
      sym

def Token.name(t: Token) -> Bool:
  match t:
    case Token{text, beg, end, col, lex, sym, name, tail, from}:
      name

def Token.from(t: Token) -> String:
  match t:
    case Token{text, beg, end, col, lex, sym, name, tail, from}:
      from

def is_comment(t: Token) -> Bool:
  match t:
    case Token{+text, beg, end, col, Comment{}, sym, name, tail, from}:
      True{}
    case _:
      False{}

def is_operator(s: Sym) -> Bool:
  match s:
    case Plus{}:
      True{}
    case Minus{}:
      True{}
    case Star{}:
      True{}
    case Slash{}:
      True{}
    case Pct{}:
      True{}
    case Caret{}:
      True{}
    case Concat{}:
      True{}
    case AndAnd{}:
      True{}
    case OrOr{}:
      True{}
    case Meet{}:
      True{}
    case BitAnd{}:
      True{}
    case BitOr{}:
      True{}
    case BitXor{}:
      True{}
    case Shl{}:
      True{}
    case Shr{}:
      True{}
    case Cons{}:
      True{}
    case Lt{}:
      True{}
    case Gt{}:
      True{}
    case Le{}:
      True{}
    case Ge{}:
      True{}
    case EqEq{}:
      True{}
    case Ne{}:
      True{}
    case Amp{}:
      True{}
    case Bar{}:
      True{}
    case _:
      False{}

# A sign or quantity glued to what follows it.
def is_prefix(s: Sym) -> Bool:
  match s:
    case Plus{}:
      True{}
    case Minus{}:
      True{}
    case Pct{}:
      True{}
    case Amp{}:
      True{}
    case _:
      False{}

def is_tight(s: Sym) -> Bool:
  match s:
    case Comma{}:
      True{}
    case Semi{}:
      True{}
    case Colon{}:
      True{}
    case Ques{}:
      True{}
    case Bang{}:
      True{}
    case Dot{}:
      True{}
    case _:
      False{}

def is_punct(s: Sym) -> Bool:
  match s:
    case Comma{}:
      True{}
    case Semi{}:
      True{}
    case Colon{}:
      True{}
    case _:
      False{}

def is_sigil(s: Sym) -> Bool:
  match s:
    case Tilde{}:
      True{}
    case At{}:
      True{}
    case Ques{}:
      True{}
    case Bang{}:
      True{}
    case Bslash{}:
      True{}
    case _:
      False{}

def is_opener(s: Sym) -> Bool:
  match s:
    case Lpar{}:
      True{}
    case Lbrk{}:
      True{}
    case Lbrc{}:
      True{}
    case Lt{}:
      True{}
    case _:
      False{}

def is_closer(s: Sym) -> Bool:
  match s:
    case Rpar{}:
      True{}
    case Rbrk{}:
      True{}
    case Rbrc{}:
      True{}
    case _:
      False{}

def is_keyword(s: Sym) -> Bool:
  match s:
    case KwReturn{}:
      True{}
    case KwCase{}:
      True{}
    case KwMatch{}:
      True{}
    case KwFor{}:
      True{}
    case KwExs{}:
      True{}
    case KwIs{}:
      True{}
    case _:
      False{}

def is_block_word(s: Sym) -> Bool:
  match s:
    case KwMatch{}:
      True{}
    case KwCase{}:
      True{}
    case KwDo{}:
      True{}
    case Assign{}:
      True{}
    case Semi{}:
      True{}
    case Pct{}:
      True{}
    case Bslash{}:
      True{}
    case _:
      False{}

# A record that ends in one of these goes on at the next line.
def is_continued(s: Sym) -> Bool:
  match s:
    case Arrow{}:
      True{}
    case Assign{}:
      True{}
    case Concat{}:
      True{}
    case AndAnd{}:
      True{}
    case OrOr{}:
      True{}
    case _:
      False{}

def is_declaration(s: Sym) -> Bool:
  match s:
    case KwDef{}:
      True{}
    case KwType{}:
      True{}
    case KwLaw{}:
      True{}
    case At{}:
      True{}
    case _:
      False{}

def is_import(s: Sym) -> Bool:
  match s:
    case KwImport{}:
      True{}
    case _:
      False{}

def is_sym(s: Sym, t: Sym) -> Bool:
  match s t:
    case Comma{} Comma{}:
      True{}
    case Colon{} Colon{}:
      True{}
    case Lbrc{} Lbrc{}:
      True{}
    case Gt{} Gt{}:
      True{}
    case Rpar{} Rpar{}:
      True{}
    case Rbrk{} Rbrk{}:
      True{}
    case Rbrc{} Rbrc{}:
      True{}
    case Bang{} Bang{}:
      True{}
    case At{} At{}:
      True{}
    case _ _:
      False{}

# Trees
# -----
def first(n: Tree) -> Token:
  match n:
    case Leaf{t}:
      t
    case Group{open, close, children, block}:
      open

def last(n: Tree) -> Token:
  match n:
    case Leaf{t}:
      t
    case Group{open, close, children, block}:
      close

def is_newline(n: Tree) -> Bool:
  match n:
    case Leaf{Token{text, beg, end, col, Newline{}, sym, name, tail, from}}:
      True{}
    case _:
      False{}

def is_leaf(n: Tree) -> Bool:
  match n:
    case Leaf{t}:
      True{}
    case _:
      False{}

# Whether n is a token spelled as s.
def leaf_is(n: Tree, s: Sym) -> Bool:
  match n:
    case Leaf{t}:
      is_sym(Token.sym(t), s)
    case _:
      False{}

def head(xs: List<&2, Tree>) -> Maybe<&2, Tree>:
  match xs:
    case Nil{}:
      None{}
    case Con{x, rest}:
      Some{x}

def last_of(xs: List<&2, Tree>, at: Maybe<&2, Tree>) -> Maybe<&2, Tree>:
  match xs:
    case Nil{}:
      at
    case Con{x, rest}:
      last_of(rest, Some{x})

# The first tree after a run of newlines.
def upcoming(xs: List<&2, Tree>) -> Maybe<&2, Tree>:
  match xs:
    case Nil{}:
      None{}
    case Con{Leaf{Token{text, beg, end, col, Newline{}, sym, name, tail, from}}, rest}:
      upcoming(rest)
    case Con{x, rest}:
      Some{x}

# What closes the group s opens, or Word{}.
def closer(s: Sym) -> Sym:
  match s:
    case Lpar{}:
      Rpar{}
    case Lbrk{}:
      Rbrk{}
    case Lbrc{}:
      Rbrc{}
    case Lt{}:
      Gt{}
    case _:
      Word{}

def angled(prev: Maybe<&2, Token>, +t: Token) -> Bool:
  match prev:
    case Some{+p}:
      U32.is_eq(Token.end(p), Token.beg(t)) && Token.name(p)
    case None{}:
      False{}

# Whether t opens a group: a glued < opens type arguments.
def opens.of(s: Sym, +t: Token, prev: Maybe<&2, Token>) -> Bool:
  match s:
    case Lpar{}:
      True{}
    case Lbrk{}:
      True{}
    case Lbrc{}:
      True{}
    case Lt{}:
      angled(prev, t)
    case _:
      False{}

def opens(+t: Token, prev: Maybe<&2, Token>) -> Bool:
  opens.of(Token.sym(t), t, prev)

def is_block_leaf(n: Tree) -> Bool:
  match n:
    case Leaf{t}:
      is_block_word(Token.sym(t))
    case _:
      False{}

def add(+n: Tree, stack: List<&2, Open>, root: List<&2, Tree>) -> Built:
  match stack:
    case Nil{}:
      Built{Nil{}, Con{n, root}}
    case Con{Open{t, close, children, block}, rest}:
      Built{Con{Open{t, close, Con{n, children}, block || is_block_leaf(n)}, rest}, root}

def waits(stack: List<&2, Open>, s: Sym) -> Bool:
  match stack:
    case Nil{}:
      False{}
    case Con{Open{t, close, children, block}, rest}:
      is_sym(close, s)

def pop(t: Token, stack: List<&2, Open>, root: List<&2, Tree>) -> Built:
  match stack:
    case Nil{}:
      Built{Nil{}, root}
    case Con{Open{open, close, children, block}, rest}:
      add(Group{open, t, List.reverse(&2, Tree, children), block}, rest, root)

def tree.close(closes: Bool, +t: Token, stack: List<&2, Open>, root: List<&2, Tree>) -> Built:
  match closes:
    case True{}:
      pop(t, stack, root)
    case False{}:
      add(Leaf{t}, stack, root)

def tree.step(opens: Bool, +t: Token, +stack: List<&2, Open>, root: List<&2, Tree>) -> Built:
  match opens:
    case True{}:
      Built{Con{Open{t, closer(Token.sym(t)), [], False{}}, stack}, root}
    case False{}:
      tree.close(waits(stack, Token.sym(t)), t, stack, root)

def tree.go(ts: List<&2, Token>, prev: Maybe<&2, Token>, b: Built) -> Maybe<&2, List<&2, Tree>>:
  match ts b:
    case Nil{} Built{Nil{}, root}:
      Some{List.reverse(&2, Tree, root)}
    case Nil{} Built{Con{o, os}, root}:
      None{}
    case Con{+t, rest} Built{stack, root}:
      tree.go(rest, Some{t}, tree.step(opens(t, prev), t, stack, root))

# Docs
# ----
def measure(s: String, +n: U32, tail: Maybe<&2, U32>, keep: U32) -> Measure:
  match s:
    case SNil{}:
      Measure{n, tail, keep}
    case SCon{+c, rest}:
      measure(
        rest,
        (n + 1: U32),
        tail_after(c, tail),
        Bool.pick(U32, is_blank(c), keep, (n + 1: U32))
      )

def str.split(whole: Bool, +s: String, width: U32, tail: Maybe<&2, U32>, +keep: U32) -> Doc:
  match whole:
    case True{}:
      Str{s, "", width, tail}
    case False{}:
      Str{take(s, U32.to_nat(keep)), String.drop(s, U32.to_nat(keep)), width, tail}

def str.of(+s: String, m: Measure) -> Doc:
  match m:
    case Measure{+width, tail, +keep}:
      str.split(U32.is_eq(width, keep), s, width, tail, keep)

# A doc for any text.
def str(+s: String) -> Doc:
  str.of(s, measure(s, 0, None{}, 0))

# A doc for text of this width, with no newline and no trailing whitespace.
def text(s: String, width: U32) -> Doc:
  Str{s, "", width, None{}}

def space(s: String, width: U32) -> Doc:
  Str{"", s, width, None{}}

def nothing() -> Doc:
  Str{"", "", 0, None{}}

def soft(flat: String, width: U32) -> Doc:
  Line{flat, width, False{}, 0}

def hard(offset: U32) -> Doc:
  Line{"", 0, True{}, offset}

def flat_of(d: Doc) -> Flat:
  match d:
    case Str{body, blank, width, Some{t}}:
      Flat{0, True{}}
    case Str{body, blank, width, None{}}:
      Flat{width, False{}}
    case Line{text, width, True{}, offset}:
      Flat{0, True{}}
    case Line{text, width, False{}, offset}:
      Flat{width, False{}}
    case Grp{doc, f}:
      f
    case Nest{doc, amount, f}:
      f
    case Cat{docs, f}:
      f

# The Flat of a doc a, then of what follows it.
def flat_then(a: Flat, rest: Flat) -> Flat:
  match a rest:
    case Flat{w, True{}} r:
      Flat{w, True{}}
    case Flat{w, False{}} Flat{v, b}:
      Flat{(w + v: U32), b}

def flat_rev(docs: List<&2, Doc>, acc: Flat) -> Flat:
  match docs:
    case Nil{}:
      acc
    case Con{d, rest}:
      flat_rev(rest, flat_then(flat_of(d), acc))

def grp(+d: Doc) -> Doc:
  Grp{d, flat_of(d)}

def nest(+d: Doc, amount: U32) -> Doc:
  Nest{d, amount, flat_of(d)}

# A Cat of docs last first.
def cat_rev(+docs: List<&2, Doc>) -> Doc:
  Cat{docs, flat_rev(docs, Flat{0, False{}})}

# A Cat of a few docs, in order.
def cat(docs: List<&2, Doc>) -> Doc:
  cat_rev(List.reverse(&2, Doc, docs))

def code(t: Token) -> Doc:
  match t:
    case Token{text, +beg, end, col, lex, sym, name, tail, from}:
      Str{text, "", (end - beg: U32), None{}}

def glued_prefix(+a: Token, b: Maybe<&2, Tree>) -> Bool:
  match b:
    case Some{n}:
      is_prefix(Token.sym(a)) && U32.is_eq(Token.end(a), Token.beg(first(n)))
    case None{}:
      False{}

# Whether a group after x is its argument list or type arguments.
def callee(+x: Token) -> Bool:
  (
    Token.name(x) || is_sym(Token.sym(x), Bang{}) || is_closer(Token.sym(x))
  )
    && Bool.not(is_keyword(Token.sym(x)))

def is_inc(s: Sym) -> Bool:
  match s:
    case Inc{}:
      True{}
    case _:
      False{}

def separator.of(+x: Token, +y: Token, +group: Bool, +b: Tree) -> Doc:
  Bool.pick(
    Doc,
    is_comment(y),
    space("  ", 2),
    Bool.pick(
      Doc,
      is_tight(Token.sym(y)),
      nothing(),
      Bool.pick(
        Doc,
        is_punct(Token.sym(x)),
        space(" ", 1),
        Bool.pick(
          Doc,
          is_sigil(Token.sym(x)),
          nothing(),
          Bool.pick(
            Doc,
            glued_prefix(x, Some{b}),
            nothing(),
            Bool.pick(
              Doc,
              is_inc(Token.sym(x)),
              nothing(),
              Bool.pick(
                Doc,
                group && is_sym(Token.sym(y), Lbrc{}) && U32.is_ne(Token.end(x), Token.beg(y)),
                space(" ", 1),
                Bool.pick(
                  Doc,
                  group && is_opener(Token.sym(y)) && callee(x),
                  nothing(),
                  space(" ", 1)
                )
              )
            )
          )
        )
      )
    )
  )

def separator(a: Tree, +b: Tree) -> Doc:
  separator.of(last(a), first(b), Bool.not(is_leaf(b)), b)

def comment_text.after(rest: String, +keep: String) -> String:
  match rest:
    case SNil{}:
      "#"
    case SCon{+c, more}:
      Bool.pick(
        String,
        is_blank(c) || Char.is_eq(c, '#') || Char.is_eq(c, '!') || Char.is_eq(c, '|'),
        "#" ++ keep,
        "# " ++ keep
      )

def comment_text(text: String, keep: String) -> String:
  match text:
    case SCon{'#', +rest}:
      comment_text.after(rest, rest)
    case _:
      keep

def leaf_doc(+t: Token) -> Doc:
  match t:
    case Token{text, beg, end, col, Newline{}, sym, name, tail, from}:
      nothing()
    case Token{+text, beg, end, col, Comment{}, sym, name, tail, from}:
      str(comment_text(text, text))
    case Token{text, beg, end, col, Literal{}, sym, name, tail, from}:
      str(text)
    case Token{text, beg, end, col, Code{}, sym, name, tail, from}:
      code(t)

# Levels
# ------
def should_pop(levels: List<&2, U32>, +col: U32) -> Bool:
  match levels:
    case Con{top, Con{x, xs}}:
      U32.is_lt(col, top)
    case _:
      False{}

def pop_levels(levels: List<&2, U32>, +col: U32, go: Bool) -> List<&2, U32>:
  match levels go:
    case Con{top, +more} True{}:
      pop_levels(more, col, should_pop(more, col))
    case Con{top, more} False{}:
      Con{top, more}
    case Nil{} _:
      Nil{}

def deepen(levels: List<&2, U32>, +col: U32) -> List<&2, U32>:
  match levels:
    case Nil{}:
      [col]
    case Con{+top, +more}:
      Bool.pick(List<&2, U32>, U32.is_gt(col, top), Con{col, Con{top, more}}, Con{top, more})

# Closes the levels deeper than col, then opens col if it is deeper.
def indented(+levels: List<&2, U32>, +col: U32) -> List<&2, U32>:
  deepen(pop_levels(levels, col, should_pop(levels, col)), col)

def depth.go(levels: List<&2, U32>, n: U32) -> U32:
  match levels:
    case Nil{}:
      n
    case Con{top, more}:
      depth.go(more, (n + 1: U32))

# How many levels are open above the base.
def depth(levels: List<&2, U32>) -> U32:
  (depth.go(levels, 0) - 1: U32)

# Sequences
# ---------
def fresh(+base: U32) -> Seq:
  Seq{[], None{}, None{}, [base], False{}}

def Seq.put(s: Seq, d: Doc) -> Seq:
  match s:
    case Seq{out, None{}, prev, levels, skip}:
      Seq{Con{d, out}, None{}, prev, levels, skip}
    case Seq{out, Some{chain}, prev, levels, skip}:
      Seq{out, Some{Con{d, chain}}, prev, levels, skip}

def Seq.chain(s: Seq) -> Seq:
  match s:
    case Seq{out, None{}, prev, levels, skip}:
      Seq{out, Some{[soft(" ", 1)]}, prev, levels, skip}
    case Seq{out, Some{chain}, prev, levels, skip}:
      Seq{out, Some{Con{soft(" ", 1), chain}}, prev, levels, skip}

def Seq.doc(s: Seq, +tab: U32) -> Doc:
  match s:
    case Seq{out, None{}, prev, levels, skip}:
      grp(cat_rev(out))
    case Seq{out, Some{chain}, prev, levels, skip}:
      grp(cat_rev(Con{nest(cat_rev(chain), tab), out}))

def prev_comment(prev: Maybe<&2, Tree>) -> Bool:
  match prev:
    case Some{p}:
      is_comment(last(p))
    case None{}:
      False{}

# A run of newlines breaks the line at the next tree's level.
def Seq.level(
  +levels: List<&2, U32>,
  +tab: U32,
  out: List<&2, Doc>,
  chain: Maybe<&2, List<&2, Doc>>
) -> Seq:
  Seq.put(Seq{out, chain, None{}, levels, True{}}, hard((depth(levels) * tab: U32)))

def Seq.end(comment: Bool, s: Seq) -> Seq:
  match comment:
    case True{}:
      Seq.put(s, hard(0))
    case False{}:
      s

def Seq.break(up: Maybe<&2, Tree>, +tab: U32, s: Seq) -> Seq:
  match up s:
    case Some{u} Seq{out, chain, prev, levels, skip}:
      Seq.level(indented(levels, Token.col(first(u))), tab, out, chain)
    case None{} Seq{out, chain, +prev, levels, skip}:
      Seq.end(prev_comment(prev), Seq{out, chain, None{}, levels, True{}})

def Seq.newline.if(trigger: Bool, +rest: List<&2, Tree>, +tab: U32, s: Seq) -> Seq:
  match trigger:
    case True{}:
      Seq.break(upcoming(rest), tab, s)
    case False{}:
      s

def Seq.newline(+rest: List<&2, Tree>, +tab: U32, +raw: Bool, s: Seq) -> Seq:
  match s:
    case Seq{out, chain, prev, levels, True{}}:
      Seq{out, chain, prev, levels, True{}}
    case Seq{out, chain, +prev, levels, False{}}:
      Seq.newline.if(raw || prev_comment(prev), rest, tab, Seq{out, chain, prev, levels, False{}})

def Seq.joint(chain: Bool, +p: Tree, +n: Tree, s: Seq) -> Seq:
  match chain:
    case True{}:
      Seq.chain(s)
    case False{}:
      Seq.put(s, separator(p, n))

def Seq.tree(+n: Tree, d: Doc, next: Maybe<&2, Tree>, +raw: Bool, s: Seq) -> Seq:
  match s:
    case Seq{out, chain, None{}, levels, skip}:
      Seq.put(Seq{out, chain, Some{n}, levels, False{}}, d)
    case Seq{out, chain, Some{p}, levels, skip}:
      Seq.put(
        Seq.joint(
          Bool.not(
            raw
          )
            && is_leaf(n)
            && is_operator(Token.sym(first(n)))
            && Bool.not(glued_prefix(first(n), next)),
          p,
          n,
          Seq{out, chain, Some{n}, levels, False{}}
        ),
        d
      )

def Seq.step(
  newline: Bool,
  +n: Tree,
  d: Doc,
  +rest: List<&2, Tree>,
  +tab: U32,
  +raw: Bool,
  s: Seq
) -> Seq:
  match newline:
    case True{}:
      Seq.newline(rest, tab, raw, s)
    case False{}:
      Seq.tree(n, d, head(rest), raw, s)

def Seq.visit(+n: Tree, d: Doc, +rest: List<&2, Tree>, +tab: U32, +raw: Bool, s: Seq) -> Seq:
  Seq.step(is_newline(n), n, d, rest, tab, raw, s)

# Parts
# -----
def Split.fresh() -> Split:
  Split{[], True{}, False{}, False{}, False{}}

def Split.track(+n: Tree, attach: Bool, sp: Split) -> Split:
  match sp:
    case Split{parts, newlines, comment, a, comments}:
      Split{
        parts,
        newlines && is_newline(n),
        Bool.pick(Bool, is_newline(n), comment, is_comment(last(n))),
        attach,
        comments
      }

def Split.end(+tab: U32, +base: U32, st: State) -> State:
  match st:
    case State{seq, Split{parts, newlines, comment, attach, comments}}:
      State{
        fresh(base),
        Split{
          Con{Part{Seq.doc(seq, tab), newlines, comment}, parts},
          True{},
          False{},
          False{},
          comments
        }
      }

def Split.comments(+n: Tree, sp: Split) -> Split:
  match sp:
    case Split{parts, newlines, comment, attach, comments}:
      Split{parts, newlines, comment, attach, comments || is_comment(first(n))}

def head_comment(xs: List<&2, Tree>) -> Bool:
  match xs:
    case Con{x, rest}:
      is_comment(first(x))
    case Nil{}:
      False{}

def Split.act(+n: Tree, +rest: List<&2, Tree>, sp: Split) -> Act:
  match sp:
    case Split{parts, newlines, comment, True{}, comments}:
      AddEnd{}
    case Split{parts, newlines, comment, False{}, comments}:
      Bool.pick(
        Act,
        leaf_is(n, Comma{}),
        Bool.pick(Act, head_comment(rest), AddAttach{}, End{}),
        Add{}
      )

def Split.apply(
  act: Act,
  +n: Tree,
  d: Doc,
  +rest: List<&2, Tree>,
  +tab: U32,
  +base: U32,
  st: State
) -> State:
  match act st:
    case Add{} State{seq, sp}:
      State{Seq.visit(n, d, rest, tab, False{}, seq), Split.track(n, False{}, sp)}
    case AddAttach{} State{seq, sp}:
      State{Seq.visit(n, d, rest, tab, False{}, seq), Split.track(n, True{}, sp)}
    case AddEnd{} State{seq, sp}:
      Split.end(
        tab,
        base,
        State{Seq.visit(n, d, rest, tab, False{}, seq), Split.track(n, False{}, sp)}
      )
    case End{} State{seq, sp}:
      Split.end(tab, base, State{seq, sp})

def Split.visit(+n: Tree, d: Doc, +rest: List<&2, Tree>, +tab: U32, +base: U32, st: State) -> State:
  match st:
    case State{seq, +sp}:
      Split.apply(Split.act(n, rest, sp), n, d, rest, tab, base, State{seq, Split.comments(n, sp)})

def should_drop(parts: List<&2, Part>) -> Bool:
  match parts:
    case Con{Part{d, True{}, c}, Con{p, ps}}:
      True{}
    case _:
      False{}

# Drops the trailing parts that hold only newlines, keeping one part.
def drop_parts(parts: List<&2, Part>, go: Bool) -> List<&2, Part>:
  match parts go:
    case Con{p, +rest} True{}:
      drop_parts(rest, should_drop(rest))
    case ps False{}:
      ps
    case Nil{} _:
      Nil{}

def content.sep(comment: Bool, acc: List<&2, Doc>) -> List<&2, Doc>:
  match comment:
    case True{}:
      Con{hard(0), acc}
    case False{}:
      Con{soft(" ", 1), Con{text(",", 1), acc}}

def content.go(parts: List<&2, Part>, comment: Bool, acc: List<&2, Doc>) -> List<&2, Doc>:
  match parts:
    case Nil{}:
      acc
    case Con{Part{d, newlines, next}, rest}:
      content.go(rest, next, Con{d, content.sep(comment, acc)})

# The parts' docs with their separators, last first.
def content(parts: List<&2, Part>) -> List<&2, Doc>:
  match parts:
    case Nil{}:
      []
    case Con{Part{d, newlines, comment}, rest}:
      content.go(rest, comment, [d])

def opening(comments: Bool) -> Doc:
  match comments:
    case True{}:
      hard(0)
    case False{}:
      soft("", 0)

# A generic's closing > stays glued to the term before it.
def closing(+close: Token, comments: Bool) -> Doc:
  Bool.pick(Doc, is_sym(Token.sym(close), Gt{}), nothing(), opening(comments))

def Split.doc(+open: Token, +close: Token, +tab: U32, st: State) -> Doc:
  match st:
    case State{seq, Split{+parts, newlines, comment, attach, +comments}}:
      grp(
        cat(
          [
            code(open),
            nest(
              cat(
                [
                  opening(comments),
                  cat_rev(content(List.reverse(&2, Part, drop_parts(parts, should_drop(parts)))))
                ]
              ),
              tab
            ),
            closing(close, comments),
            code(close)
          ]
        )
      )

# Build
# -----
def mode_of(+open: Token, +close: Token, children: List<&2, Tree>, block: Bool) -> Mode:
  match children block:
    case Nil{} _:
      Bare{open, close}
    case _ True{}:
      Block{open, close}
    case _ False{}:
      Parts{open, close}

def start(+base: U32) -> State:
  State{fresh(base), Split.fresh()}

def visit(
  +mode: Mode,
  +n: Tree,
  d: Doc,
  +rest: List<&2, Tree>,
  +tab: U32,
  +base: U32,
  st: State
) -> State:
  match mode st:
    case Plain{} State{seq, sp}:
      State{Seq.visit(n, d, rest, tab, False{}, seq), sp}
    case Block{open, close} State{seq, sp}:
      State{Seq.visit(n, d, rest, tab, True{}, seq), sp}
    case Parts{open, close} st2:
      Split.visit(n, d, rest, tab, base, st2)
    case Bare{open, close} st2:
      st2

def finish(mode: Mode, st: State, +tab: U32, +base: U32) -> Doc:
  match mode st:
    case Plain{} State{seq, sp}:
      Seq.doc(seq, tab)
    case Block{open, close} State{seq, sp}:
      cat([code(open), Seq.doc(seq, tab), code(close)])
    case Parts{open, close} st2:
      Split.doc(open, close, tab, Split.end(tab, base, st2))
    case Bare{open, close} st2:
      cat([code(open), code(close)])

# The doc of a list of trees, read as mode says. A group's children are
# built first, by the same def, as a smaller part of the list.
def build(nodes: List<&2, Tree>, +tab: U32, +base: U32, +mode: Mode, st: State) -> Doc:
  match nodes:
    case Nil{}:
      finish(mode, st, tab, base)
    case Con{Leaf{+t}, +rest}:
      build(rest, tab, base, mode, visit(mode, Leaf{t}, leaf_doc(t), rest, tab, base, st))
    case Con{Group{+open, +close, +children, +block}, +rest}:
      build(
        rest,
        tab,
        base,
        mode,
        visit(
          mode,
          Group{open, close, children, block},
          build(children, tab, base, mode_of(open, close, children, block), start(base)),
          rest,
          tab,
          base,
          st
        )
      )

def sequence(nodes: List<&2, Tree>, +tab: U32, +base: U32) -> Doc:
  build(nodes, tab, base, Plain{}, start(base))

# Printer
# -------
# Jobs for a Cat's docs, last first, so its first doc ends on top.
def push(docs: List<&2, Doc>, +indent: U32, +flat: Bool, jobs: List<&2, Job>) -> List<&2, Job>:
  match docs:
    case Nil{}:
      jobs
    case Con{d, rest}:
      push(rest, indent, flat, Con{Job{d, indent, flat}, jobs})

def fits.flat.of(over: Bool, brk: Bool, jobs: List<&2, Job>, left: U32) -> Fit:
  match over brk:
    case True{} _:
      Stop{False{}}
    case False{} True{}:
      Stop{True{}}
    case False{} False{}:
      Go{jobs, left}

# A doc printed flat, whole: past the width, or up to a break within it.
def fits.flat(f: Flat, jobs: List<&2, Job>, +left: U32) -> Fit:
  match f:
    case Flat{+w, brk}:
      fits.flat.of(U32.is_gt(w, left), brk, jobs, (left - w: U32))

def fits.width(stop: Bool, +n: U32, jobs: List<&2, Job>, +left: U32) -> Fit:
  match stop:
    case True{}:
      Stop{True{}}
    case False{}:
      Bool.pick(Fit, U32.is_gt(n, left), Stop{False{}}, Go{jobs, (left - n: U32)})

def is_some(m: Maybe<&2, U32>) -> Bool:
  match m:
    case Some{x}:
      True{}
    case None{}:
      False{}

def fits.step(jobs: List<&2, Job>, +left: U32) -> Fit:
  match jobs:
    case Nil{}:
      Stop{True{}}
    case Con{Job{Str{body, blank, width, tail}, indent, flat}, rest}:
      fits.width(is_some(tail), width, rest, left)
    case Con{Job{Line{text, width, hard, offset}, indent, flat}, rest}:
      fits.width(hard || Bool.not(flat), width, rest, left)
    case Con{Job{Grp{doc, f}, indent, flat}, rest}:
      fits.flat(f, rest, left)
    case Con{Job{Nest{doc, amount, f}, indent, flat}, rest}:
      fits.flat(f, rest, left)
    case Con{Job{Cat{docs, f}, indent, True{}}, rest}:
      fits.flat(f, rest, left)
    case Con{Job{Cat{docs, f}, indent, False{}}, rest}:
      Go{push(docs, indent, False{}, rest), left}

def fits.go(fuel: Nat, f: Fit) -> Bool:
  match fuel f:
    case _ Stop{b}:
      b
    case 0n Go{jobs, left}:
      True{}
    case 1n+k Go{jobs, left}:
      fits.go(k, fits.step(jobs, left))

def fits.from(over: Bool, fuel: Nat, left: U32, jobs: List<&2, Job>) -> Bool:
  match over:
    case True{}:
      False{}
    case False{}:
      fits.go(fuel, Go{jobs, left})

# Whether the jobs fit before their first break, from col.
def fits(+fuel: Nat, +width: U32, +col: U32, jobs: List<&2, Job>) -> Bool:
  fits.from(U32.is_gt(col, width), fuel, (width - col: U32), jobs)

def col_of(tail: Maybe<&2, U32>, +col: U32, +width: U32) -> U32:
  match tail:
    case Some{t}:
      t
    case None{}:
      (col + width: U32)

# Text goes out after the pending whitespace; its own trailing whitespace
# becomes pending.
def print.str(
  body: String,
  keep: String,
  +blank: String,
  jobs: List<&2, Job>,
  out: List<&2, String>,
  pending: String,
  col: U32
) -> Print:
  match body:
    case SNil{}:
      Print{jobs, out, pending ++ blank, col}
    case _:
      Print{jobs, Con{keep, Con{pending, out}}, blank, col}

def print.line(
  flat: Bool,
  text: String,
  +at: U32,
  jobs: List<&2, Job>,
  out: List<&2, String>,
  pending: String,
  +col: U32,
  +width: U32,
  newline: String
) -> Print:
  match flat:
    case True{}:
      Print{jobs, out, pending ++ text, (col + width: U32)}
    case False{}:
      Print{jobs, out, newline ++ pad(U32.to_nat(at), ""), at}

def print.flat(
  flat: Bool,
  +fuel: Nat,
  +width: Maybe<&2, U32>,
  +col: U32,
  jobs: List<&2, Job>
) -> Bool:
  match flat width:
    case True{} _:
      True{}
    case False{} None{}:
      True{}
    case False{} Some{w}:
      fits(fuel, w, col, jobs)

def unbounded(width: Maybe<&2, U32>) -> Bool:
  match width:
    case None{}:
      True{}
    case Some{w}:
      False{}

def print.step(
  jobs: List<&2, Job>,
  out: List<&2, String>,
  pending: String,
  +col: U32,
  +width: Maybe<&2, U32>,
  +newline: String,
  +fuel: Nat
) -> Print:
  match jobs:
    case Nil{}:
      Print{Nil{}, out, pending, col}
    case Con{Job{Str{+body, blank, w, tail}, indent, flat}, rest}:
      print.str(body, body, blank, rest, out, pending, col_of(tail, col, w))
    case Con{Job{Line{text, w, hard, offset}, +indent, +flat}, rest}:
      print.line(
        Bool.not(hard) && (flat || unbounded(width)),
        text,
        (indent + offset: U32),
        rest,
        out,
        pending,
        col,
        w,
        newline
      )
    case Con{Job{Nest{doc, amount, f}, indent, flat}, rest}:
      Print{Con{Job{doc, (indent + amount: U32), flat}, rest}, out, pending, col}
    case Con{Job{Grp{+doc, f}, +indent, +flat}, +rest}:
      Print{
        Con{
          Job{doc, indent, print.flat(flat, fuel, width, col, Con{Job{doc, indent, True{}}, rest})},
          rest
        },
        out,
        pending,
        col
      }
    case Con{Job{Cat{docs, f}, indent, flat}, rest}:
      Print{push(docs, indent, flat, rest), out, pending, col}

# Chunks last first, joined from the right: each ++ copies one chunk at
# most, and a token adds its chunks in one step.
def chunks(xs: List<&2, String>, acc: String) -> String:
  match xs:
    case Nil{}:
      acc
    case Con{x, rest}:
      chunks(rest, x ++ acc)

# The text so far; pending whitespace is never written at the end.
def print.go(fuel: Nat, p: Print, +width: Maybe<&2, U32>, +newline: String, +budget: Nat) -> String:
  match fuel p:
    case _ Print{Nil{}, out, pending, col}:
      chunks(out, "")
    case 0n Print{jobs, out, pending, col}:
      chunks(out, "")
    case 1n+k Print{jobs, out, pending, col}:
      print.go(
        k,
        print.step(jobs, out, pending, col, width, newline, budget),
        width,
        newline,
        budget
      )

# The doc at indent; fuel bounds the steps of the printer and of each fit.
def print(doc: Doc, +width: Maybe<&2, U32>, +indent: U32, +newline: String, +fuel: Nat) -> String:
  print.go(
    fuel,
    Print{[Job{doc, indent, False{}}], [], pad(U32.to_nat(indent), ""), indent},
    width,
    newline,
    fuel
  )

# Records
# -------
def joins.of(+p: Tree, +next: Tree, following: Maybe<&2, Tree>) -> Bool:
  Bool.not(
    is_comment(last(p))
  )
    && Bool.not(is_comment(first(next)))
    && (
      (
        Bool.not(
          glued_prefix(first(next), following)
        )
          && is_leaf(next)
          && is_operator(Token.sym(first(next)))
      )
        || is_continued(Token.sym(last(p)))
    )

# Whether a newline between previous and rest continues the record.
def joins(previous: Maybe<&2, Tree>, rest: List<&2, Tree>) -> Bool:
  match previous rest:
    case Some{p} Con{next, more}:
      joins.of(p, next, head(more))
    case _ _:
      False{}

def records.newline(join: Bool, done: List<&2, List<&2, Tree>>, current: List<&2, Tree>) -> Recs:
  match join:
    case True{}:
      Recs{done, current}
    case False{}:
      Recs{Con{List.reverse(&2, Tree, current), done}, Nil{}}

def records.step(
  newline: Bool,
  n: Tree,
  +rest: List<&2, Tree>,
  done: List<&2, List<&2, Tree>>,
  +current: List<&2, Tree>
) -> Recs:
  match newline:
    case False{}:
      Recs{done, Con{n, current}}
    case True{}:
      records.newline(joins(head(current), rest), done, current)

def records(nodes: List<&2, Tree>, r: Recs) -> List<&2, List<&2, Tree>>:
  match nodes r:
    case Nil{} Recs{done, current}:
      List.reverse(&2, List<&2, Tree>, Con{List.reverse(&2, Tree, current), done})
    case Con{+n, +rest} Recs{done, current}:
      records(rest, records.step(is_newline(n), n, rest, done, current))

def cut.step(+n: Tree, c: Cut) -> Cut:
  match c:
    case Cut{before, after, True{}}:
      Cut{before, Con{n, after}, True{}}
    case Cut{before, after, False{}}:
      Cut{Con{n, before}, after, leaf_is(n, Colon{})}

def cut.go(xs: List<&2, Tree>, c: Cut) -> Cut:
  match xs c:
    case Nil{} Cut{before, after, found}:
      Cut{List.reverse(&2, Tree, before), List.reverse(&2, Tree, after), found}
    case Con{+n, rest} c2:
      cut.go(rest, cut.step(n, c2))

# Whether the cut has a body after its colon that is not a comment.
def cut.inline(c: Cut) -> Bool:
  match c:
    case Cut{before, Con{x, xs}, True{}}:
      Bool.not(is_comment(first(x)))
    case _:
      False{}

def not_hash(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{'#', rest}:
      False{}
    case _:
      True{}

def split_hash.of(r: Run) -> Hash:
  match r:
    case Run{before, n, SNil{}, last}:
      Hash{before, None{}}
    case Run{before, n, rest, last}:
      Hash{before, Some{rest}}

def split_hash(+s: String) -> Hash:
  split_hash.of(scan(~not_hash, s, s, not_hash(s), "", 0, '\0'))

def import_space.of(+rest: String, s: String) -> String:
  Bool.pick(String, head_is(~is_blank, rest), "import " ++ drop_blank(rest), s)

# "import" and its whitespace as "import ".
def import_space(+s: String) -> String:
  import_space.of(String.drop(s, 6n), s)

def alias_at.as(s: String) -> Bool:
  match s:
    case SCon{'a', SCon{'s', rest}}:
      head_is(~is_blank, rest)
    case _:
      False{}

# Whether whitespace, "as" and whitespace start at s.
def alias_at(+s: String) -> Bool:
  head_is(~is_blank, s) && alias_at.as(drop_blank(s))

def alias.go(s: String, hit: Bool, acc: String) -> String:
  match s hit:
    case SNil{} _:
      String.reverse(acc)
    case SCon{c, rest} True{}:
      String.reverse(acc) ++ " as " ++ drop_blank(String.drop(drop_blank(SCon{c, rest}), 2n))
    case SCon{c, +rest} False{}:
      alias.go(rest, alias_at(rest), SCon{c, acc})

# The first whitespace, "as" and whitespace as " as ".
def alias(+s: String) -> String:
  alias.go(s, alias_at(s), "")

def import_doc.of(h: Hash) -> Doc:
  match h:
    case Hash{before, None{}}:
      str(alias(import_space(trim_end(before))))
    case Hash{before, Some{+comment}}:
      cat(
        [
          str(alias(import_space(trim_end(before)))),
          space("  ", 2),
          str(comment_text(comment, comment))
        ]
      )

# Where the record that head starts ends.
def record_end(head: Token, record: List<&2, Tree>) -> U32:
  Token.end(last(Maybe.default(&2, Tree, last_of(record, None{}), Leaf{head})))

def import_doc(+head: Token, record: List<&2, Tree>) -> Doc:
  import_doc.of(
    split_hash(
      trim_end(
        take(Token.from(head), U32.to_nat((record_end(head, record) - Token.beg(head): U32)))
      )
    )
  )

def decl_doc.of(inline: Bool, c: Cut, record: List<&2, Tree>, +tab: U32, +col: U32) -> Doc:
  match inline c:
    case True{} Cut{before, after, found}:
      cat([sequence(before, tab, col), nest(cat([hard(0), sequence(after, tab, col)]), tab)])
    case False{} c2:
      sequence(record, tab, col)

def decl_doc.cut(+c: Cut, record: List<&2, Tree>, +declaration: Bool, +tab: U32, +col: U32) -> Doc:
  decl_doc.of(U32.is_zero(col) && declaration && cut.inline(c), c, record, tab, col)

def decl_doc(+record: List<&2, Tree>, +declaration: Bool, +tab: U32, +col: U32) -> Doc:
  decl_doc.cut(cut.go(record, Cut{[], [], False{}}), record, declaration, tab, col)

def record_doc(
  is_import: Bool,
  +head: Token,
  +record: List<&2, Tree>,
  +declaration: Bool,
  +tab: U32,
  +col: U32
) -> Doc:
  match is_import:
    case True{}:
      import_doc(head, record)
    case False{}:
      decl_doc(record, declaration, tab, col)

def joined(xs: List<&2, Tree>, acc: String) -> String:
  match xs:
    case Nil{}:
      acc
    case Con{x, rest}:
      joined(rest, acc ++ Token.text(first(x)))

# Whether the record's tokens spell @unsafe.
def is_unsafe(at: Bool, +record: List<&2, Tree>) -> Bool:
  match at:
    case True{}:
      same(joined(record, ""), "@unsafe")
    case False{}:
      False{}

def gapped(gap: Bool, rows: List<&2, String>) -> List<&2, String>:
  match gap rows:
    case True{} Con{+row, +rest}:
      Bool.pick(List<&2, String>, String.is_empty(row), Con{row, rest}, Con{"", Con{row, rest}})
    case _ rows2:
      rows2

def rows.line(+head: Token, +record: List<&2, Tree>, +set: Settings, r: Rows) -> Rows:
  match set r:
    case Settings{+tab, +width, +newline} Rows{levels, +blank, unsafe, prior, rows}:
      +col = Token.col(head)
      +levels2 = indented(levels, col)
      +declaration = is_declaration(Token.sym(head))
      +comment = is_comment(head)
      +gap = Bool.pick(
        Bool,
        U32.is_zero(col),
        (declaration && Bool.not(prior) && Bool.not(unsafe)) || (comment && blank),
        blank
      )
      +doc = record_doc(is_import(Token.sym(head)), head, record, declaration, tab, col)
      +fuel = U32.to_nat(
        (fuel_per_point() * ((record_end(head, record) - Token.beg(head): U32) + 1): U32)
      )
      Rows{
        levels2,
        False{},
        is_unsafe(is_sym(Token.sym(head), At{}), record),
        comment,
        Con{print(doc, width, (depth(levels2) * tab: U32), newline, fuel), gapped(gap, rows)}
      }

def rows.step(record: List<&2, Tree>, +set: Settings, r: Rows) -> Rows:
  match record r:
    case Nil{} Rows{levels, blank, unsafe, comment, rows}:
      Rows{levels, True{}, unsafe, comment, rows}
    case Con{+x, xs} r2:
      rows.line(first(x), Con{x, xs}, set, r2)

def rows.go(records: List<&2, List<&2, Tree>>, +set: Settings, r: Rows) -> Rows:
  match records:
    case Nil{}:
      r
    case Con{record, rest}:
      rows.go(rest, set, rows.step(record, set, r))

def head_empty(rows: List<&2, String>) -> Bool:
  match rows:
    case Con{row, rest}:
      String.is_empty(row)
    case Nil{}:
      False{}

def drop_empty(rows: List<&2, String>, go: Bool) -> List<&2, String>:
  match rows go:
    case Con{row, +rest} True{}:
      drop_empty(rest, head_empty(rest))
    case rest _:
      rest

def join(rows: List<&2, String>, +newline: String, acc: String) -> String:
  match rows:
    case Nil{}:
      acc
    case Con{row, rest}:
      join(rest, newline, row ++ newline ++ acc)

# The rows, last first, joined, without the empty rows at the end, with a
# newline. Each row has no trailing whitespace already.
def text_of.trimmed(rows: List<&2, String>, +newline: String) -> String:
  match rows:
    case Nil{}:
      newline
    case Con{row, rest}:
      join(rest, newline, row ++ newline)

def text_of(+rows: List<&2, String>, +newline: String) -> String:
  text_of.trimmed(drop_empty(rows, head_empty(rows)), newline)

def format.text(r: Rows, +newline: String) -> String:
  match r:
    case Rows{levels, blank, unsafe, comment, rows}:
      text_of(rows, newline)

def format.of(nodes: Maybe<&2, List<&2, Tree>>, +set: Settings) -> Maybe<&2, String>:
  match nodes set:
    case None{} s:
      None{}
    case Some{ns} Settings{tab, width, +newline}:
      Some{
        format.text(
          rows.go(
            records(ns, Recs{[], []}),
            Settings{tab, width, newline},
            Rows{[0], False{}, False{}, False{}, []}
          ),
          newline
        )
      }

# The formatted text, or None{} if its delimiters do not balance.
def format(source: String, +set: Settings) -> Maybe<&2, String>:
  format.of(tree.go(tokens(source), None{}, Built{[], []}), set)

# Rule
# ----
def first_newline(s: String) -> String:
  match s:
    case SNil{}:
      "\n"
    case SCon{'\r', SCon{'\n', rest}}:
      "\r\n"
    case SCon{'\n', rest}:
      "\n"
    case SCon{_, rest}:
      first_newline(rest)

def newline_of(+eol: String, source: String) -> String:
  Bool.pick(
    String,
    String.eq(eol, "crlf"),
    "\r\n",
    Bool.pick(String, String.eq(eol, "preserve"), first_newline(source), "\n")
  )

def width_of(m: Maybe<&2, Lint.Value>) -> Maybe<&2, U32>:
  match m:
    case Some{Lint.Num{n}}:
      Some{n}
    case _:
      None{}

def settings(+options: List<&2, Lint.Option>, source: String) -> Settings:
  Settings{
    Lint.option_number(options, "tabWidth"),
    width_of(Lint.find(options, "wrapAtWidth")),
    newline_of(Lint.option_text(options, "endOfLine"), source)
  }

def guarded(ok: Bool, out: String, +span: Lint.Span) -> List<&2, Lint.Diag>:
  match ok:
    case True{}:
      [
        Lint.Diag{
          Lint.Warning{},
          "Apply canonical formatting.",
          Some{span},
          [Lint.Fix{"Format file", Lint.Safe{}, [Lint.Edit{span, out}]}],
          None{}
        }
      ]
    case False{}:
      [
        Lint.diag(
          Lint.Warning{},
          "Cannot safely format this syntax: the result parses differently. No fix was offered.",
          span
        )
      ]

def changed(same: Bool, +out: String, +span: Lint.Span) -> IO(List<&2, Lint.Diag>):
  match same:
    case True{}:
      IO.pure(List<&2, Lint.Diag>, [])
    case False{}:
      IO.bind(
        Bool,
        List<&2, Lint.Diag>,
        Lint.same_declarations(out),
        ok => IO.pure(List<&2, Lint.Diag>, guarded(ok, out, span))
      )

def verdict(m: Maybe<&2, String>, +text: String, +span: Lint.Span) -> IO(List<&2, Lint.Diag>):
  match m:
    case None{}:
      IO.pure(
        List<&2, Lint.Diag>,
        [
          Lint.diag(
            Lint.Warning{},
            "Cannot format this file: unbalanced delimiters. No fix was offered.",
            span
          )
        ]
      )
    case Some{+out}:
      changed(same(out, text), out, span)

def id() -> String:
  "format/layout"

def facts() -> Lint.Want:
  Lint.NoFacts{}

def options() -> List<&2, Lint.Declared>:
  [
    Lint.Declared{"tabWidth", Lint.Num{2}, Lint.NumberOption{1, 4294967295}},
    Lint.Declared{
      "wrapAtWidth",
      Lint.Num{100},
      Lint.AnyOption{[Lint.NumberOption{1, 4294967295}, Lint.TextOption{["never"]}]}
    },
    Lint.Declared{"endOfLine", Lint.Text{"lf"}, Lint.TextOption{["lf", "crlf", "preserve"]}}
  ]

def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
  match input:
    case Lint.Input{root, sources, options, prior}:
      match root:
        case Lint.Source{+path, +text, is_root}:
          verdict(
            format(text, settings(options, text)),
            text,
            Lint.Span{path, 0, U32.from_nat(String.length(text))}
          )

def main() -> IO(Unit):
  Lint.serve(run)
