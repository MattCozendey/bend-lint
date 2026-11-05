import Base

def take.go(n: Nat, s: String, acc: String) -> String:
  match n s:
    case 1n+k SCon{c, rest}:
      take.go(k, rest, SCon{c, acc})
    case _ _:
      String.reverse(acc)

# The first `n` characters of `s`. Base's String.take is not tail-recursive, so long text would overflow the stack.
def take(s: String, n: Nat) -> String:
  take.go(n, s, "")

# The text of `text` from `beg` to `end`, in code points.
def slice(text: String, +beg: U32, end: U32) -> String:
  take(String.drop(text, U32.to_nat(beg)), U32.to_nat((end - beg: U32)))

def line_start.go(s: String, +i: U32, +at: U32, start: U32, going: Bool) -> U32:
  match s going:
    case _ False{}:
      start
    case SNil{} True{}:
      start
    case SCon{c, rest} True{}:
      line_start.go(
        rest,
        (i + 1: U32),
        at,
        Bool.pick(U32, Char.is_eq(c, '\n'), (i + 1: U32), start),
        U32.is_lt((i + 1: U32), at)
      )

# Where the line of `text` that holds the offset `at` starts: after the last newline before it.
def line_start(text: String, +at: U32) -> U32:
  line_start.go(text, 0, at, 0, U32.is_lt(0, at))

def line_end.go(s: String, i: U32) -> U32:
  match s:
    case SNil{}:
      i
    case SCon{'\n', rest}:
      (i + 1: U32)
    case SCon{c, rest}:
      line_end.go(rest, (i + 1: U32))

# Where the line of `text` that starts at `beg` ends: after its newline, or at the end of the text.
def line_end(text: String, +beg: U32) -> U32:
  line_end.go(String.drop(text, U32.to_nat(beg)), beg)

def starts_with(s: String, c: Char) -> Bool:
  match s:
    case SCon{h, t}:
      Char.is_eq(h, c)
    case SNil{}:
      False{}

def before.go(s: String, +sep: Char, acc: String, at: Bool) -> String:
  match s at:
    case SNil{} _:
      ""
    case _ True{}:
      String.reverse(acc)
    case SCon{c, +rest} False{}:
      before.go(rest, sep, SCon{c, acc}, starts_with(rest, sep))

# What comes before the first `sep` of `s`, or "" if there is none.
def before(+s: String, +sep: Char) -> String:
  before.go(s, sep, "", starts_with(s, sep))

def after_last.go(s: String, +sep: Char, seg: String) -> String:
  match s:
    case SNil{}:
      String.reverse(seg)
    case SCon{+c, rest}:
      after_last.go(rest, sep, Bool.pick(String, Char.is_eq(c, sep), "", SCon{c, seg}))

# What comes after the last `sep` of `s`, or all of `s` if there is none.
def after_last(s: String, sep: Char) -> String:
  after_last.go(s, sep, "")

# The chunks of `chunks` (last first) as one text, before `out`. Each chunk is copied once, so it is linear.
def onto(chunks: List<&2, String>, out: String) -> String:
  match chunks:
    case Nil{}:
      out
    case Con{c, rest}:
      onto(rest, c ++ out)

# Whether `text` starts with `from`, which is not empty.
def replace.hits(text: String, +from: String) -> Bool:
  String.starts_with(text, from) && Bool.not(String.is_empty(from))

# `text`, after `out` (the text so far, reversed), with each `from` in it, from the left, as `to`; `hit` says whether
# `text` starts with `from`. `fuel` is at least the length of `text`, as each step takes one character at least.
def replace.go(
  fuel: Nat,
  hit: Bool,
  text: String,
  +from: String,
  +to: String,
  out: String
) -> String:
  match fuel hit text:
    case 1n+k True{} t:
      +next = String.drop(t, String.length(from))
      replace.go(k, replace.hits(next, from), next, from, to, String.reverse(to) ++ out)
    case 1n+k False{} SCon{c, +rest}:
      replace.go(k, replace.hits(rest, from), rest, from, to, SCon{c, out})
    case _ _ rest:
      String.reverse(out) ++ rest

# `text` with each `from` in it, from the left, as `to`: none if `from` is empty.
def replace(+text: String, +from: String, to: String) -> String:
  replace.go(String.length(text), replace.hits(text, from), text, from, to, "")
