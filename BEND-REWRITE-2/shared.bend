# What more than one file of bend-lint uses.
import Base

# A value, with the name it is written as.
type Named<-A: Data> is Data:
  Named{name: String, value: A}

# The value `key` names in `table`.
def lookup(-A: Data, +key: String, table: List<&2, Named<A>>) -> Maybe<&2, A>:
  match table:
    case Nil{}:
      None{}
    case Con{Named{+k, +v}, rest}:
      Bool.pick(Maybe<&2, A>, String.eq(k, key), Some{v}, lookup(A, key, rest))

# `xs`, last first, onto `out`.
def onto(-A: Data, xs: List<&2, A>, out: List<&2, A>) -> List<&2, A>:
  match xs:
    case Nil{}:
      out
    case Con{h, t}:
      onto(A, t, h <> out)

# `x`, if there is one, onto `out`.
def push(-A: Data, x: Maybe<&2, A>, out: List<&2, A>) -> List<&2, A>:
  match x:
    case Some{v}:
      v <> out
    case None{}:
      out

def before.of(parts: List<&2, String>) -> String:
  match parts:
    case Con{first, Con{second, rest}}:
      first
    case _:
      ""

# What comes before the first `sep` of `s`, or "" if there is none.
def before(s: String, sep: Char) -> String:
  before.of(String.split(s, sep))

def line.go(s: String, +line: U32) -> U32:
  match s:
    case SNil{}:
      line
    case SCon{+c, t}:
      line.go(t, Bool.pick(U32, Char.is_eq(c, '\n'), (line + 1 : U32), line))

# The line (from 0) of offset `at` of `text`.
def line(text: String, at: U32) -> U32:
  line.go(String.take(text, U32.to_nat(at)), 0)

def position.go(s: String, +line: U32, +column: U32) -> String:
  match s:
    case SNil{}:
      U32.show(line) ++ ":" ++ U32.show(column)
    case SCon{+c, t}:
      position.go(
        t,
        Bool.pick(U32, Char.is_eq(c, '\n'), (line + 1 : U32), line),
        Bool.pick(U32, Char.is_eq(c, '\n'), 1, (column + 1 : U32))
      )

# Where offset `at` of `text` is, as line:column (from 1).
def position(text: String, at: U32) -> String:
  position.go(String.take(text, U32.to_nat(at)), 1, 1)
