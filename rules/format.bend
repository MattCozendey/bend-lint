# format/layout, in Bend: the twin of format.ts, which explains the layout.
# Both rules give the same text; rules/format.test.ts runs each.
# Run: bun src/lint.ts file.bend --rules rules/format.bend --fix
#
# Each loop is go(input, state): a step that does not recurse makes the next
# state, so every loop recurses on a smaller part of its input. The printer
# recurses on fuel instead: more steps than its doc can need.
import Base
import ../src/bend/lint.bend as Lint

# Types
# =====
type Lex is Data:
  Code{}
  Literal{}
  Comment{}
  Newline{}

# Offsets and columns count code points.
type Token is Data:
  Token{text: String, beg: U32, end: U32, col: U32, lex: Lex}

type Lexed is Data:
  Lexed{skip: Nat, tokens: List<&2, Token>}

# What the next character of a literal is: inside it, escaped, or past it.
type Quote is Data:
  Inside{}
  Escaped{}
  Shut{}

type Tree is Data:
  Leaf{token: Token}
  Group{open: Token, close: Token, children: List<&2, Tree>}

# A group the tree has opened: the close it waits for, children last first.
type Open is Data:
  Open{token: Token, close: String, children: List<&2, Tree>}

type Built is Data:
  Built{stack: List<&2, Open>, root: List<&2, Tree>}

type Doc is Data:
  Str{text: String}
  Line{flat: String, hard: Bool, offset: U32}
  Grp{doc: Doc}
  Nest{doc: Doc, amount: U32}
  Cat{docs: List<&2, Doc>}

# How build reads a list of trees: a record, a group's children as a raw
# block, as comma-separated parts, or a group with no children.
type Mode is Data:
  Plain{}
  Block{open: String, close: String}
  Parts{open: String, close: String}
  Bare{open: String, close: String}

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

# The printer: jobs left, the text so far reversed, and its column.
type Print is Data:
  Print{jobs: List<&2, Job>, out: String, col: U32}

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
def operators() -> List<&2, String>:
  [
    "+",
    "-",
    "*",
    "/",
    "%",
    "^",
    "++",
    "&&",
    "||",
    "<&>",
    ".&.",
    ".|.",
    ".^.",
    "<<",
    ">>",
    "<>",
    "<",
    ">",
    "<=",
    ">=",
    "==",
    "!=",
    "&",
    "|"
  ]

# The symbols of more than one character, in the order they are tried.
def symbols() -> List<&2, String>:
  [
    "<&>",
    ".&.",
    ".|.",
    ".^.",
    "->",
    "=>",
    "<-",
    "==",
    "!=",
    "<=",
    ">=",
    "<<",
    "&&",
    "||",
    "++",
    "<>",
    "&0",
    "&1",
    "&2"
  ]

# Fuel per code point of a record: more printer steps than any doc needs.
def fuel_per_point() -> U32:
  64

# Functions
# =========

# Text
# ----
def has(xs: List<&2, String>, +s: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, rest}:
      String.eq(x, s) || has(rest, s)

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

def points.go(s: String, n: U32) -> U32:
  match s:
    case SNil{}:
      n
    case SCon{c, rest}:
      points.go(rest, (n + 1: U32))

def points(s: String) -> U32:
  points.go(s, 0)

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

# Whether a and b both end here, or start with the same character.
def heads(a: String, b: String) -> Bool:
  match a b:
    case SNil{} SNil{}:
      True{}
    case SCon{x, xs} SCon{y, ys}:
      Char.is_eq(x, y)
    case _ _:
      False{}

def same.go(a: String, b: String, ok: Bool) -> Bool:
  match a b ok:
    case SCon{x, +xs} SCon{y, +ys} True{}:
      same.go(xs, ys, heads(xs, ys))
    case _ _ done:
      done

def same(+a: String, +b: String) -> Bool:
  same.go(a, b, heads(a, b))

# s reversed in front of out.
def onto(s: String, out: String) -> String:
  match s:
    case SNil{}:
      out
    case SCon{c, rest}:
      onto(rest, SCon{c, out})

def pad(n: Nat, out: String) -> String:
  match n:
    case 0n:
      out
    case 1n+k:
      pad(k, SCon{' ', out})

def name_at(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{'.', rest}:
      True{}
    case SCon{+c, rest}:
      is_word(c)

def has_newline(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{'\n', rest}:
      True{}
    case SCon{c, rest}:
      has_newline(rest)

# How many characters pass test, from the one where ok is test's answer;
# test reads the text from each character on, so it can look ahead.
def span(~test: String -> Bool, s: String, ok: Bool, n: U32) -> U32:
  match s ok:
    case SCon{c, +rest} True{}:
      span(~test, rest, test(rest), (n + 1: U32))
    case _ _:
      n

# Whether s matches /^[\w.]+$/.
def is_name(+s: String) -> Bool:
  Bool.not(String.is_empty(s)) && U32.is_eq(span(~name_at, s, name_at(s), 0), points(s))

# Tokens
# ------
def not_line_end(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{'\n', rest}:
      False{}
    case SCon{'\r', rest}:
      False{}
    case SCon{c, rest}:
      True{}

def digit_at(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{c, rest}:
      Char.is_digit(c)

def digits(+s: String) -> U32:
  span(~digit_at, s, digit_at(s), 0)

# A word character, or a dot before the start of a word.
def ident_at(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{'.', rest}:
      head_is(~is_head, rest)
    case SCon{+c, rest}:
      is_word(c)

def exponent_len.digits(+lead: U32, +n: U32) -> U32:
  Bool.pick(U32, U32.is_zero(n), 0, (lead + n: U32))

def exponent_len.sign(+s: String) -> U32:
  match s:
    case SCon{'+', +rest}:
      exponent_len.digits(2, digits(rest))
    case SCon{'-', +rest}:
      exponent_len.digits(2, digits(rest))
    case _:
      exponent_len.digits(1, digits(s))

def exponent_len(s: String) -> U32:
  match s:
    case SCon{'e', rest}:
      exponent_len.sign(rest)
    case SCon{'E', rest}:
      exponent_len.sign(rest)
    case _:
      0

def fraction_len(+n: U32, +rest: String) -> U32:
  Bool.pick(U32, U32.is_zero(n), 0, (1 + n + exponent_len(String.drop(rest, U32.to_nat(n))): U32))

# After a number's digits: n, n+, or a fraction and its exponent.
def suffix_len(s: String) -> U32:
  match s:
    case SCon{'n', SCon{'+', rest}}:
      2
    case SCon{'n', rest}:
      1
    case SCon{'.', +rest}:
      fraction_len(digits(rest), rest)
    case _:
      0

def number_len.of(+n: U32, s: String) -> U32:
  (n + suffix_len(String.drop(s, U32.to_nat(n))): U32)

def number_len(+s: String) -> U32:
  number_len.of(digits(s), s)

def symbol_len(+s: String, syms: List<&2, String>) -> U32:
  match syms:
    case Nil{}:
      1
    case Con{+sym, rest}:
      Bool.pick(U32, String.starts_with(s, sym), points(sym), symbol_len(s, rest))

def word_len.of(+c: Char, +s: String) -> U32:
  Bool.pick(
    U32,
    is_head(c),
    span(~ident_at, s, True{}, 0),
    Bool.pick(U32, Char.is_digit(c), number_len(s), symbol_len(s, symbols()))
  )

def word_len(s: String) -> U32:
  match s:
    case SNil{}:
      0
    case SCon{+c, rest}:
      word_len.of(c, SCon{c, rest})

# The length of a code token; prev is the character before it.
def atom_len(+s: String, +prev: Char) -> U32:
  Bool.pick(
    U32,
    String.starts_with(s, "<-") && (is_word(prev) || Char.is_eq(prev, '.')),
    1,
    Bool.pick(U32, String.starts_with(s, ">>") && is_blank(prev), 2, word_len(s))
  )

def quote_after(+c: Char, +quote: Char) -> Quote:
  Bool.pick(
    Quote,
    Char.is_eq(c, '\\'),
    Escaped{},
    Bool.pick(Quote, Char.is_eq(c, quote), Shut{}, Inside{})
  )

# How many characters of a literal follow its opening quote.
def literal_len(s: String, +quote: Char, at: Quote, n: U32) -> U32:
  match s at:
    case SCon{+c, rest} Inside{}:
      literal_len(rest, quote, quote_after(c, quote), (n + 1: U32))
    case SCon{c, rest} Escaped{}:
      literal_len(rest, quote, Inside{}, (n + 1: U32))
    case _ _:
      n

def lex.emit(
  lex: Lex,
  +len: U32,
  +s: String,
  +at: U32,
  start: U32,
  tokens: List<&2, Token>
) -> Lexed:
  Lexed{
    Nat.sub(U32.to_nat(len), 1n),
    Con{Token{take(s, U32.to_nat(len)), at, (at + len: U32), (at - start: U32), lex}, tokens}
  }

def lex.code(
  blank: Bool,
  +s: String,
  +at: U32,
  start: U32,
  +prev: Char,
  tokens: List<&2, Token>
) -> Lexed:
  match blank:
    case True{}:
      Lexed{0n, tokens}
    case False{}:
      lex.emit(Code{}, atom_len(s, prev), s, at, start, tokens)

def lex.token(s: String, +at: U32, +start: U32, +prev: Char, tokens: List<&2, Token>) -> Lexed:
  match s:
    case SNil{}:
      Lexed{0n, tokens}
    case SCon{'\n', rest}:
      lex.emit(Newline{}, 1, "\n", at, start, tokens)
    case SCon{'#', +rest}:
      lex.emit(
        Comment{},
        span(~not_line_end, SCon{'#', rest}, True{}, 0),
        SCon{'#', rest},
        at,
        start,
        tokens
      )
    case SCon{'"', +rest}:
      lex.emit(
        Literal{},
        (1 + literal_len(rest, '"', Inside{}, 0): U32),
        SCon{'"', rest},
        at,
        start,
        tokens
      )
    case SCon{'\'', +rest}:
      lex.emit(
        Literal{},
        (1 + literal_len(rest, '\'', Inside{}, 0): U32),
        SCon{'\'', rest},
        at,
        start,
        tokens
      )
    case SCon{+c, rest}:
      lex.code(is_blank(c), SCon{c, rest}, at, start, prev, tokens)

def lex.step(
  skip: Nat,
  s: String,
  +at: U32,
  +start: U32,
  +prev: Char,
  tokens: List<&2, Token>
) -> Lexed:
  match skip:
    case 1n+k:
      Lexed{k, tokens}
    case 0n:
      lex.token(s, at, start, prev, tokens)

def line_start(c: Char, +at: U32, start: U32) -> U32:
  match c:
    case '\n':
      (at + 1: U32)
    case _:
      start

# The tokens from at on. prev: the character before at; start: where its
# line starts; skip: how many characters of the last token are left.
def lex.go(s: String, +at: U32, +start: U32, +prev: Char, st: Lexed) -> List<&2, Token>:
  match s st:
    case SNil{} Lexed{k, tokens}:
      List.reverse(&2, Token, tokens)
    case SCon{+c, +rest} Lexed{skip, tokens}:
      lex.go(
        rest,
        (at + 1: U32),
        line_start(c, at, start),
        c,
        lex.step(skip, SCon{c, rest}, at, start, prev, tokens)
      )

def tokens(s: String) -> List<&2, Token>:
  lex.go(s, 0, 0, '\0', Lexed{0n, []})

def Token.text(t: Token) -> String:
  match t:
    case Token{text, beg, end, col, lex}:
      text

def Token.beg(t: Token) -> U32:
  match t:
    case Token{text, beg, end, col, lex}:
      beg

def Token.end(t: Token) -> U32:
  match t:
    case Token{text, beg, end, col, lex}:
      end

def Token.col(t: Token) -> U32:
  match t:
    case Token{text, beg, end, col, lex}:
      col

def is_comment(t: Token) -> Bool:
  match t:
    case Token{text, beg, end, col, Comment{}}:
      True{}
    case _:
      False{}

# Trees
# -----
def first(n: Tree) -> Token:
  match n:
    case Leaf{t}:
      t
    case Group{open, close, children}:
      open

def last(n: Tree) -> Token:
  match n:
    case Leaf{t}:
      t
    case Group{open, close, children}:
      close

def is_newline(n: Tree) -> Bool:
  match n:
    case Leaf{Token{text, beg, end, col, Newline{}}}:
      True{}
    case _:
      False{}

def is_leaf(n: Tree) -> Bool:
  match n:
    case Leaf{t}:
      True{}
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
    case Con{Leaf{Token{text, beg, end, col, Newline{}}}, rest}:
      upcoming(rest)
    case Con{x, rest}:
      Some{x}

# What closes the group t opens, or "".
def close_of(t: String) -> String:
  match t:
    case SCon{'(', SNil{}}:
      ")"
    case SCon{'[', SNil{}}:
      "]"
    case SCon{'{', SNil{}}:
      "}"
    case SCon{'<', SNil{}}:
      ">"
    case _:
      ""

def angled(prev: Maybe<&2, Token>, +t: Token) -> Bool:
  match prev:
    case Some{+p}:
      U32.is_eq(Token.end(p), Token.beg(t)) && is_name(Token.text(p))
    case None{}:
      False{}

def add(n: Tree, stack: List<&2, Open>, root: List<&2, Tree>) -> Built:
  match stack:
    case Nil{}:
      Built{Nil{}, Con{n, root}}
    case Con{Open{t, close, children}, rest}:
      Built{Con{Open{t, close, Con{n, children}}, rest}, root}

def waits(stack: List<&2, Open>, +text: String) -> Bool:
  match stack:
    case Nil{}:
      False{}
    case Con{Open{t, close, children}, rest}:
      String.eq(close, text)

def pop(t: Token, stack: List<&2, Open>, root: List<&2, Tree>) -> Built:
  match stack:
    case Nil{}:
      Built{Nil{}, root}
    case Con{Open{open, close, children}, rest}:
      add(Group{open, t, List.reverse(&2, Tree, children)}, rest, root)

def tree.close(closes: Bool, +t: Token, stack: List<&2, Open>, root: List<&2, Tree>) -> Built:
  match closes:
    case True{}:
      pop(t, stack, root)
    case False{}:
      add(Leaf{t}, stack, root)

def tree.open(
  opens: Bool,
  +close: String,
  +t: Token,
  +stack: List<&2, Open>,
  root: List<&2, Tree>
) -> Built:
  match opens:
    case True{}:
      Built{Con{Open{t, close, []}, stack}, root}
    case False{}:
      tree.close(waits(stack, Token.text(t)), t, stack, root)

def tree.step.of(
  +close: String,
  +t: Token,
  prev: Maybe<&2, Token>,
  stack: List<&2, Open>,
  root: List<&2, Tree>
) -> Built:
  tree.open(
    Bool.not(
      String.is_empty(close)
    )
      && (Bool.not(String.eq(Token.text(t), "<")) || angled(prev, t)),
    close,
    t,
    stack,
    root
  )

def tree.step(
  +t: Token,
  prev: Maybe<&2, Token>,
  stack: List<&2, Open>,
  root: List<&2, Tree>
) -> Built:
  tree.step.of(close_of(Token.text(t)), t, prev, stack, root)

def tree.go(ts: List<&2, Token>, prev: Maybe<&2, Token>, b: Built) -> Maybe<&2, List<&2, Tree>>:
  match ts b:
    case Nil{} Built{Nil{}, root}:
      Some{List.reverse(&2, Tree, root)}
    case Nil{} Built{Con{o, os}, root}:
      None{}
    case Con{+t, rest} Built{stack, root}:
      tree.go(rest, Some{t}, tree.step(t, prev, stack, root))

# Docs
# ----
def soft(flat: String) -> Doc:
  Line{flat, False{}, 0}

def hard(offset: U32) -> Doc:
  Line{"", True{}, offset}

def glued_prefix(+a: Token, b: Maybe<&2, Tree>) -> Bool:
  match b:
    case Some{n}:
      has(["+", "-", "%", "&"], Token.text(a)) && U32.is_eq(Token.end(a), Token.beg(first(n)))
    case None{}:
      False{}

# Whether a group after l is its argument list or type arguments.
def callee(+l: String) -> Bool:
  (
    is_name(l) || String.eq(l, "!") || has([")", "]", "}"], l)
  )
    && Bool.not(has(["return", "case", "match", "for", "exs", "is"], l))

def separator.of(+x: Token, +y: Token, +group: Bool, +b: Tree) -> String:
  Bool.pick(
    String,
    is_comment(y),
    "  ",
    Bool.pick(
      String,
      has([",", ";", ":", "?", "!", "."], Token.text(y)),
      "",
      Bool.pick(
        String,
        has([",", ";", ":"], Token.text(x)),
        " ",
        Bool.pick(
          String,
          has(["~", "@", "?", "!", "\\"], Token.text(x)),
          "",
          Bool.pick(
            String,
            glued_prefix(x, Some{b}),
            "",
            Bool.pick(
              String,
              String.ends_with(Token.text(x), "n+"),
              "",
              Bool.pick(
                String,
                group && String.eq(Token.text(y), "{") && U32.is_ne(Token.end(x), Token.beg(y)),
                " ",
                Bool.pick(
                  String,
                  group && has(["(", "[", "{", "<"], Token.text(y)) && callee(Token.text(x)),
                  "",
                  " "
                )
              )
            )
          )
        )
      )
    )
  )

def separator(a: Tree, +b: Tree) -> String:
  separator.of(last(a), first(b), Bool.not(is_leaf(b)), b)

def comment_text.after(+rest: String) -> String:
  match rest:
    case SNil{}:
      "#"
    case SCon{+c, more}:
      Bool.pick(
        String,
        is_blank(c) || Char.is_eq(c, '#') || Char.is_eq(c, '!') || Char.is_eq(c, '|'),
        SCon{'#', SCon{c, more}},
        "# " ++ SCon{c, more}
      )

def comment_text(text: String) -> String:
  match text:
    case SCon{'#', rest}:
      comment_text.after(rest)
    case SNil{}:
      SNil{}
    case SCon{c, rest}:
      SCon{c, rest}

def leaf_doc(t: Token) -> Doc:
  match t:
    case Token{text, beg, end, col, Newline{}}:
      Str{""}
    case Token{text, beg, end, col, Comment{}}:
      Str{comment_text(text)}
    case Token{text, beg, end, col, lex}:
      Str{text}

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
      Seq{out, Some{[soft(" ")]}, prev, levels, skip}
    case Seq{out, Some{chain}, prev, levels, skip}:
      Seq{out, Some{Con{soft(" "), chain}}, prev, levels, skip}

def Seq.doc(s: Seq, +tab: U32) -> Doc:
  match s:
    case Seq{out, None{}, prev, levels, skip}:
      Grp{Cat{List.reverse(&2, Doc, out)}}
    case Seq{out, Some{chain}, prev, levels, skip}:
      Grp{Cat{List.reverse(&2, Doc, Con{Nest{Cat{List.reverse(&2, Doc, chain)}, tab}, out})}}

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
      Seq.put(s, Str{separator(p, n)})

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
            && has(operators(), Token.text(first(n)))
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
        is_leaf(n) && String.eq(Token.text(first(n)), ","),
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
      Con{soft(" "), Con{Str{","}, acc}}

def content.go(parts: List<&2, Part>, comment: Bool, acc: List<&2, Doc>) -> List<&2, Doc>:
  match parts:
    case Nil{}:
      List.reverse(&2, Doc, acc)
    case Con{Part{d, newlines, next}, rest}:
      content.go(rest, next, Con{d, content.sep(comment, acc)})

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
      soft("")

def closing(+close: String, comments: Bool) -> Doc:
  Bool.pick(Doc, String.eq(close, ">"), Str{""}, opening(comments))

def Split.doc(+open: String, +close: String, +tab: U32, st: State) -> Doc:
  match st:
    case State{seq, Split{+parts, newlines, comment, attach, +comments}}:
      Grp{
        Cat{
          [
            Str{open},
            Nest{
              Cat{
                [
                  opening(comments),
                  Cat{content(List.reverse(&2, Part, drop_parts(parts, should_drop(parts))))}
                ]
              },
              tab
            },
            closing(close, comments),
            Str{close}
          ]
        }
      }

# Build
# -----
def is_block(xs: List<&2, Tree>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{Leaf{t}, rest}:
      has(["match", "case", "do", "=", ";", "%", "\\"], Token.text(t)) || is_block(rest)
    case Con{Group{open, close, children}, rest}:
      is_block(rest)

def mode_of(+open: Token, +close: Token, +children: List<&2, Tree>) -> Mode:
  match children:
    case Nil{}:
      Bare{Token.text(open), Token.text(close)}
    case Con{x, xs}:
      Bool.pick(
        Mode,
        is_block(Con{x, xs}),
        Block{Token.text(open), Token.text(close)},
        Parts{Token.text(open), Token.text(close)}
      )

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
      Cat{[Str{open}, Seq.doc(seq, tab), Str{close}]}
    case Parts{open, close} st2:
      Split.doc(open, close, tab, Split.end(tab, base, st2))
    case Bare{open, close} st2:
      Str{open ++ close}

# The doc of a list of trees, read as mode says. A group's children are
# built first, by the same def, as a smaller part of the list.
def build(nodes: List<&2, Tree>, +tab: U32, +base: U32, +mode: Mode, st: State) -> Doc:
  match nodes:
    case Nil{}:
      finish(mode, st, tab, base)
    case Con{Leaf{+t}, +rest}:
      build(rest, tab, base, mode, visit(mode, Leaf{t}, leaf_doc(t), rest, tab, base, st))
    case Con{Group{+open, +close, +children}, +rest}:
      build(
        rest,
        tab,
        base,
        mode,
        visit(
          mode,
          Group{open, close, children},
          build(children, tab, base, mode_of(open, close, children), start(base)),
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
def push_rev(docs: List<&2, Doc>, +indent: U32, +flat: Bool, jobs: List<&2, Job>) -> List<&2, Job>:
  match docs:
    case Nil{}:
      jobs
    case Con{d, rest}:
      push_rev(rest, indent, flat, Con{Job{d, indent, flat}, jobs})

def push_all(docs: List<&2, Doc>, +indent: U32, +flat: Bool, jobs: List<&2, Job>) -> List<&2, Job>:
  push_rev(List.reverse(&2, Doc, docs), indent, flat, jobs)

def fits.width(stop: Bool, +n: U32, jobs: List<&2, Job>, +left: U32) -> Fit:
  match stop:
    case True{}:
      Stop{True{}}
    case False{}:
      Bool.pick(Fit, U32.is_gt(n, left), Stop{False{}}, Go{jobs, (left - n: U32)})

def fits.step(jobs: List<&2, Job>, +left: U32) -> Fit:
  match jobs:
    case Nil{}:
      Stop{True{}}
    case Con{Job{Str{+text}, indent, flat}, rest}:
      fits.width(has_newline(text), points(text), rest, left)
    case Con{Job{Line{text, hard, offset}, indent, flat}, rest}:
      fits.width(hard || Bool.not(flat), points(text), rest, left)
    case Con{Job{Grp{doc}, indent, flat}, rest}:
      Go{Con{Job{doc, indent, True{}}, rest}, left}
    case Con{Job{Nest{doc, amount}, indent, flat}, rest}:
      Go{Con{Job{doc, (indent + amount: U32), True{}}, rest}, left}
    case Con{Job{Cat{docs}, indent, flat}, rest}:
      Go{push_all(docs, indent, flat, rest), left}

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

def col_after(c: Char, +col: U32) -> U32:
  match c:
    case '\n':
      0
    case _:
      (col + 1: U32)

def emit(s: String, p: Print) -> Print:
  match s p:
    case SNil{} p2:
      p2
    case SCon{+c, rest} Print{jobs, out, col}:
      emit(rest, Print{jobs, SCon{c, out}, col_after(c, col)})

def print.line(
  flat: Bool,
  text: String,
  +at: U32,
  jobs: List<&2, Job>,
  out: String,
  col: U32,
  newline: String
) -> Print:
  match flat:
    case True{}:
      emit(text, Print{jobs, out, col})
    case False{}:
      Print{jobs, pad(U32.to_nat(at), onto(newline, drop_blank(out))), at}

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
  out: String,
  +col: U32,
  +width: Maybe<&2, U32>,
  +newline: String,
  +fuel: Nat
) -> Print:
  match jobs:
    case Nil{}:
      Print{Nil{}, out, col}
    case Con{Job{Str{text}, indent, flat}, rest}:
      emit(text, Print{rest, out, col})
    case Con{Job{Line{text, hard, offset}, +indent, +flat}, rest}:
      print.line(
        Bool.not(hard) && (flat || unbounded(width)),
        text,
        (indent + offset: U32),
        rest,
        out,
        col,
        newline
      )
    case Con{Job{Nest{doc, amount}, indent, flat}, rest}:
      Print{Con{Job{doc, (indent + amount: U32), flat}, rest}, out, col}
    case Con{Job{Grp{+doc}, +indent, +flat}, +rest}:
      Print{
        Con{
          Job{doc, indent, print.flat(flat, fuel, width, col, Con{Job{doc, indent, True{}}, rest})},
          rest
        },
        out,
        col
      }
    case Con{Job{Cat{docs}, indent, flat}, rest}:
      Print{push_all(docs, indent, flat, rest), out, col}

def print.go(fuel: Nat, p: Print, +width: Maybe<&2, U32>, +newline: String, +budget: Nat) -> String:
  match fuel p:
    case _ Print{Nil{}, out, col}:
      String.reverse(drop_blank(out))
    case 0n Print{jobs, out, col}:
      String.reverse(drop_blank(out))
    case 1n+k Print{jobs, out, col}:
      print.go(k, print.step(jobs, out, col, width, newline, budget), width, newline, budget)

# The doc at indent; fuel bounds the steps of the printer and of each fit.
def print(doc: Doc, +width: Maybe<&2, U32>, +indent: U32, +newline: String, +fuel: Nat) -> String:
  print.go(
    fuel,
    Print{[Job{doc, indent, False{}}], pad(U32.to_nat(indent), ""), indent},
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
          && has(operators(), Token.text(first(next)))
      )
        || has(["->", "=", "++", "&&", "||"], Token.text(last(p)))
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
      Cut{Con{n, before}, after, is_leaf(n) && String.eq(Token.text(first(n)), ":")}

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

def split_hash(s: String, acc: String) -> Hash:
  match s:
    case SNil{}:
      Hash{String.reverse(acc), None{}}
    case SCon{'#', rest}:
      Hash{String.reverse(acc), Some{SCon{'#', rest}}}
    case SCon{c, rest}:
      split_hash(rest, SCon{c, acc})

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
      Str{alias(import_space(trim_end(before)))}
    case Hash{before, Some{comment}}:
      Cat{[Str{alias(import_space(trim_end(before)))}, Str{"  "}, Str{comment_text(comment)}]}

# Where the record that head starts ends.
def record_end(head: Token, record: List<&2, Tree>) -> U32:
  Token.end(last(Maybe.default(&2, Tree, last_of(record, None{}), Leaf{head})))

def slice(+source: String, +beg: U32, +end: U32) -> String:
  take(String.drop(source, U32.to_nat(beg)), U32.to_nat((end - beg: U32)))

def import_doc(+source: String, +head: Token, record: List<&2, Tree>) -> Doc:
  import_doc.of(split_hash(trim_end(slice(source, Token.beg(head), record_end(head, record))), ""))

def decl_doc.of(inline: Bool, c: Cut, record: List<&2, Tree>, +tab: U32, +col: U32) -> Doc:
  match inline c:
    case True{} Cut{before, after, found}:
      Cat{[sequence(before, tab, col), Nest{Cat{[hard(0), sequence(after, tab, col)]}, tab}]}
    case False{} c2:
      sequence(record, tab, col)

def decl_doc.cut(+c: Cut, record: List<&2, Tree>, +declaration: Bool, +tab: U32, +col: U32) -> Doc:
  decl_doc.of(U32.is_zero(col) && declaration && cut.inline(c), c, record, tab, col)

def decl_doc(+record: List<&2, Tree>, +declaration: Bool, +tab: U32, +col: U32) -> Doc:
  decl_doc.cut(cut.go(record, Cut{[], [], False{}}), record, declaration, tab, col)

def record_doc(
  is_import: Bool,
  +source: String,
  +head: Token,
  +record: List<&2, Tree>,
  +declaration: Bool,
  +tab: U32,
  +col: U32
) -> Doc:
  match is_import:
    case True{}:
      import_doc(source, head, record)
    case False{}:
      decl_doc(record, declaration, tab, col)

def joined(xs: List<&2, Tree>, acc: String) -> String:
  match xs:
    case Nil{}:
      String.reverse(acc)
    case Con{x, rest}:
      joined(rest, onto(Token.text(first(x)), acc))

def gapped(gap: Bool, rows: List<&2, String>) -> List<&2, String>:
  match gap rows:
    case True{} Con{+row, +rest}:
      Bool.pick(List<&2, String>, String.is_empty(row), Con{row, rest}, Con{"", Con{row, rest}})
    case _ rows2:
      rows2

def is_declaration(+text: String) -> Bool:
  has(["def", "type", "law", "@"], text)

def rows.line(
  +head: Token,
  +record: List<&2, Tree>,
  +source: String,
  +set: Settings,
  r: Rows
) -> Rows:
  match set r:
    case Settings{+tab, +width, +newline} Rows{levels, +blank, unsafe, prior, rows}:
      +col = Token.col(head)
      +levels2 = indented(levels, col)
      +declaration = is_declaration(Token.text(head))
      +comment = is_comment(head)
      +gap = Bool.pick(
        Bool,
        U32.is_zero(col),
        (declaration && Bool.not(prior) && Bool.not(unsafe)) || (comment && blank),
        blank
      )
      +doc = record_doc(
        String.eq(Token.text(head), "import"),
        source,
        head,
        record,
        declaration,
        tab,
        col
      )
      +fuel = U32.to_nat(
        (fuel_per_point() * ((record_end(head, record) - Token.beg(head): U32) + 1): U32)
      )
      Rows{
        levels2,
        False{},
        String.eq(joined(record, ""), "@unsafe"),
        comment,
        Con{print(doc, width, (depth(levels2) * tab: U32), newline, fuel), gapped(gap, rows)}
      }

def rows.step(record: List<&2, Tree>, +source: String, +set: Settings, r: Rows) -> Rows:
  match record r:
    case Nil{} Rows{levels, blank, unsafe, comment, rows}:
      Rows{levels, True{}, unsafe, comment, rows}
    case Con{+x, xs} r2:
      rows.line(first(x), Con{x, xs}, source, set, r2)

def rows.go(records: List<&2, List<&2, Tree>>, +source: String, +set: Settings, r: Rows) -> Rows:
  match records:
    case Nil{}:
      r
    case Con{record, rest}:
      rows.go(rest, source, set, rows.step(record, source, set, r))

def join(rows: List<&2, String>, +newline: String, acc: String) -> String:
  match rows:
    case Nil{}:
      acc
    case Con{row, rest}:
      join(rest, newline, row ++ newline ++ acc)

# The rows, last first, joined, without trailing whitespace, with a newline.
def text_of(rows: List<&2, String>, +newline: String) -> String:
  match rows:
    case Nil{}:
      newline
    case Con{row, rest}:
      String.reverse(onto(newline, drop_blank(String.reverse(join(rest, newline, row)))))

def format.text(r: Rows, +newline: String) -> String:
  match r:
    case Rows{levels, blank, unsafe, comment, rows}:
      text_of(rows, newline)

def format.of(
  nodes: Maybe<&2, List<&2, Tree>>,
  +source: String,
  +set: Settings
) -> Maybe<&2, String>:
  match nodes set:
    case None{} s:
      None{}
    case Some{ns} Settings{tab, width, +newline}:
      Some{
        format.text(
          rows.go(
            records(ns, Recs{[], []}),
            source,
            Settings{tab, width, newline},
            Rows{[0], False{}, False{}, False{}, []}
          ),
          newline
        )
      }

# The formatted text, or None{} if its delimiters do not balance.
def format(+source: String, +set: Settings) -> Maybe<&2, String>:
  format.of(tree.go(tokens(source), None{}, Built{[], []}), source, set)

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
    case SCon{c, rest}:
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
          verdict(format(text, settings(options, text)), text, Lint.Span{path, 0, points(text)})

def main() -> IO(Unit):
  Lint.serve(run)
