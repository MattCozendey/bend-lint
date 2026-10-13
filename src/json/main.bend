import Base
import ../shared/names.bend as Names
import ../shared/strings.bend as Strings

# Types
# =====
type Json is Data:
  JNull{}
  JTrue{}
  JFalse{}
  JNumber{text: String}
  JString{text: String}
  JArray{items: List<&2, Json>}
  JObject{fields: List<&2, JField>}

type JField is Data:
  JField{key: String, value: Json}

# Reading
# =======
type Token is Data:
  TOpen{}
  TClose{}
  TList{}
  TEnd{}
  TString{text: String}
  TWord{text: String}
  TSkip{}

type JGlyph is Data:
  GOpen{}
  GClose{}
  GList{}
  GEnd{}
  GQuote{}
  GBackslash{}
  GSeparator{}
  GBlank{}
  GOther{}

# Where the lexer is: between tokens, in a string, after a \ in one, in a \u escape (the code so far, and how many hex
# digits are left), after a \u escape of a high surrogate, or in a word; the text so far (last first); and the tokens so
# far (last first). `high` is the high surrogate an escape follows, or 0.
type LexMode is Data:
  Between{}
  InText{}
  InEscape{high: U32}
  InHex{code: U32, left: U32, high: U32}
  InHigh{high: U32}
  InWord{}

type Lex is Data:
  Lex{mode: LexMode, text: String, tokens: List<&2, Token>}

def JGlyph.of(+c: Char) -> JGlyph:
  Bool.pick(
    JGlyph,
    Char.is_eq(c, '{'),
    GOpen{},
    Bool.pick(
      JGlyph,
      Char.is_eq(c, '}'),
      GClose{},
      Bool.pick(
        JGlyph,
        Char.is_eq(c, '['),
        GList{},
        Bool.pick(
          JGlyph,
          Char.is_eq(c, ']'),
          GEnd{},
          Bool.pick(
            JGlyph,
            Char.is_eq(c, '"'),
            GQuote{},
            Bool.pick(
              JGlyph,
              Char.is_eq(c, '\\'),
              GBackslash{},
              Bool.pick(
                JGlyph,
                Char.is_eq(c, ':') || Char.is_eq(c, ','),
                GSeparator{},
                Bool.pick(JGlyph, Char.is_space(c), GBlank{}, GOther{})
              )
            )
          )
        )
      )
    )
  )

# The token a structural glyph is, between tokens.
def Token.of(glyph: JGlyph) -> Token:
  match glyph:
    case GOpen{}:
      TOpen{}
    case GClose{}:
      TClose{}
    case GList{}:
      TList{}
    case GEnd{}:
      TEnd{}
    case _:
      TSkip{}

def Json.unescaped(+c: Char) -> Char:
  Bool.pick(
    Char,
    Char.is_eq(c, 'n'),
    '\n',
    Bool.pick(Char, Char.is_eq(c, 't'), '\t', Bool.pick(Char, Char.is_eq(c, 'r'), '\r', c))
  )

# The replacement character, for a surrogate an escape leaves alone.
def Lex.replacement() -> Char:
  Char.from_u32(65533)

# `text` after the high surrogate `high`, if no low one follows it: with a replacement for it.
def Lex.lone(high: U32, text: String) -> String:
  match high:
    case 0:
      text
    case _:
      SCon{Lex.replacement(), text}

def Lex.escape(c: Char, high: U32, text: String, tokens: List<&2, Token>) -> Lex:
  match c:
    case 'u':
      Lex{InHex{0, 4, high}, text, tokens}
    case e:
      Lex{InText{}, SCon{Json.unescaped(e), Lex.lone(high, text)}, tokens}

# `code` with the hex digit `c` after it.
def Lex.digit(code: U32, +c: Char) -> U32:
  (
    code
      * 16
      + Bool.pick(
        U32,
        U32.is_le(Char.to_u32(c), Char.to_u32('9')),
        (Char.to_u32(c) - Char.to_u32('0'): U32),
        (Char.to_u32(c) % 32 + 9: U32)
      ): U32
  )

def Surrogate.high(+u: U32) -> Bool:
  U32.is_le(55296, u) && U32.is_le(u, 56319)

def Surrogate.low(+u: U32) -> Bool:
  U32.is_le(56320, u) && U32.is_le(u, 57343)

# A \u escape of `code`, alone: a high surrogate waits for its low one; a low one alone is replaced.
def Lex.single(high: Bool, low: Bool, code: U32, text: String, tokens: List<&2, Token>) -> Lex:
  match high low:
    case True{} _:
      Lex{InHigh{code}, text, tokens}
    case False{} True{}:
      Lex{InText{}, SCon{Lex.replacement(), text}, tokens}
    case False{} False{}:
      Lex{InText{}, SCon{Char.from_u32(code), text}, tokens}

# A \u escape of `code` after one of the high surrogate `high` (or 0): a low surrogate makes one character with it.
def Lex.paired(pair: Bool, +code: U32, high: U32, text: String, tokens: List<&2, Token>) -> Lex:
  match pair:
    case True{}:
      Lex{
        InText{},
        SCon{Char.from_u32((65536 + (high - 55296) * 1024 + (code - 56320): U32)), text},
        tokens
      }
    case False{}:
      Lex.single(Surrogate.high(code), Surrogate.low(code), code, Lex.lone(high, text), tokens)

def Lex.hexed(
  done: Bool,
  +code: U32,
  left: U32,
  +high: U32,
  text: String,
  tokens: List<&2, Token>
) -> Lex:
  match done:
    case True{}:
      Lex.paired(Surrogate.low(code) && Surrogate.high(high), code, high, text, tokens)
    case False{}:
      Lex{InHex{code, left, high}, text, tokens}

def Lex.hex(code: U32, +left: U32, high: U32, text: String, tokens: List<&2, Token>) -> Lex:
  Lex.hexed(U32.is_eq(left, 0), code, left, high, text, tokens)

# A step in a string: a quote closes it, a backslash starts an escape, another character goes on it.
def Lex.text(glyph: JGlyph, c: Char, text: String, tokens: List<&2, Token>) -> Lex:
  match glyph:
    case GQuote{}:
      Lex{Between{}, "", TString{String.reverse(text)} <> tokens}
    case GBackslash{}:
      Lex{InEscape{0}, text, tokens}
    case _:
      Lex{InText{}, SCon{c, text}, tokens}

# A step between tokens: a quote opens a string, a blank or separator is skipped, another character starts a word.
def Lex.between(glyph: JGlyph, c: Char, tokens: List<&2, Token>) -> Lex:
  match glyph:
    case GQuote{}:
      Lex{InText{}, "", tokens}
    case GBlank{}:
      Lex{Between{}, "", tokens}
    case GSeparator{}:
      Lex{Between{}, "", tokens}
    case GOther{}:
      Lex{InWord{}, SCon{c, SNil{}}, tokens}
    case GBackslash{}:
      Lex{InWord{}, SCon{c, SNil{}}, tokens}
    case _:
      Lex{Between{}, "", Token.of(glyph) <> tokens}

def Lex.step(lex: Lex, glyph: JGlyph, c: Char) -> Lex:
  match lex glyph:
    case Lex{Between{}, text, tokens} _:
      Lex.between(glyph, c, tokens)
    case Lex{InText{}, text, tokens} _:
      Lex.text(glyph, c, text, tokens)
    case Lex{InEscape{high}, text, tokens} _:
      Lex.escape(c, high, text, tokens)
    case Lex{InHex{code, left, high}, text, tokens} _:
      Lex.hex(Lex.digit(code, c), (left - 1: U32), high, text, tokens)
    case Lex{InHigh{high}, text, tokens} GBackslash{}:
      Lex{InEscape{high}, text, tokens}
    case Lex{InHigh{high}, text, tokens} _:
      Lex.text(glyph, c, Lex.lone(high, text), tokens)
    case Lex{InWord{}, text, tokens} GOther{}:
      Lex{InWord{}, SCon{c, text}, tokens}
    case Lex{InWord{}, text, tokens} _:
      Lex.between(glyph, c, TWord{String.reverse(text)} <> tokens)

def Lex.go(s: String, lex: Lex) -> Lex:
  match s:
    case SNil{}:
      lex
    case SCon{+c, t}:
      Lex.go(t, Lex.step(lex, JGlyph.of(c), c))

def Lex.done(lex: Lex) -> List<&2, Token>:
  match lex:
    case Lex{InWord{}, text, tokens}:
      List.reverse(&2, Token, TWord{String.reverse(text)} <> tokens)
    case Lex{mode, text, tokens}:
      List.reverse(&2, Token, tokens)

# A list or an object being read: its items, or its fields and the key read for the next one (all last first).
type Frame is Data:
  InList{items: List<&2, Json>}
  InObject{fields: List<&2, JField>, key: Maybe<&2, String>}

# What is read so far: the open lists and objects (innermost first), and the value read whole, if any; None if the
# text is not JSON.
type Read is Data:
  Read{stack: List<&2, Frame>, value: Maybe<&2, Json>}
  Unreadable{}

def Json.word(+w: String) -> Json:
  Maybe.default(
    &2,
    Json,
    Names.lookup(
      Json,
      w,
      [Names.Named{"true", JTrue{}}, Names.Named{"false", JFalse{}}, Names.Named{"null", JNull{}}]
    ),
    JNumber{w}
  )

# A value read whole: into the innermost list or object, or as the text's value.
def Read.value(v: Json, stack: List<&2, Frame>, value: Maybe<&2, Json>) -> Read:
  match stack value:
    case Nil{} None{}:
      Read{[], Some{v}}
    case Con{InList{items}, rest} _:
      Read{InList{v <> items} <> rest, value}
    case Con{InObject{fields, Some{k}}, rest} _:
      Read{InObject{JField{k, v} <> fields, None{}} <> rest, value}
    case _ _:
      Unreadable{}

def Read.step(token: Token, r: Read) -> Read:
  match token r:
    case _ Unreadable{}:
      Unreadable{}
    case TSkip{} _:
      r
    case TOpen{} Read{stack, value}:
      Read{InObject{[], None{}} <> stack, value}
    case TList{} Read{stack, value}:
      Read{InList{[]} <> stack, value}
    case TEnd{} Read{Con{InList{items}, rest}, value}:
      Read.value(JArray{List.reverse(&2, Json, items)}, rest, value)
    case TClose{} Read{Con{InObject{fields, None{}}, rest}, value}:
      Read.value(JObject{List.reverse(&2, JField, fields)}, rest, value)
    case TString{text} Read{Con{InObject{fields, None{}}, rest}, value}:
      Read{InObject{fields, Some{text}} <> rest, value}
    case TString{text} Read{stack, value}:
      Read.value(JString{text}, stack, value)
    case TWord{w} Read{stack, value}:
      Read.value(Json.word(w), stack, value)
    case _ _:
      Unreadable{}

def Read.go(tokens: List<&2, Token>, r: Read) -> Read:
  match tokens:
    case Nil{}:
      r
    case Con{t, rest}:
      Read.go(rest, Read.step(t, r))

def Read.done(r: Read) -> Maybe<&2, Json>:
  match r:
    case Read{Nil{}, value}:
      value
    case _:
      None{}

def read(text: String) -> Maybe<&2, Json>:
  Read.done(Read.go(Lex.done(Lex.go(text, Lex{Between{}, "", []})), Read{[], None{}}))

# Writing
# =======

# What is left to write: a value, or text as it is.
type Piece is Data:
  PValue{value: Json}
  PText{text: String}

def hex(+n: U32) -> Char:
  Bool.pick(Char, U32.is_lt(n, 10), Char.from_u32((48 + n: U32)), Char.from_u32((87 + n: U32)))

# A character of a string, escaped if it is a control character (as \u00XX), onto `out` (last first).
def escaped.char(control: Bool, +c: Char, out: String) -> String:
  match control:
    case True{}:
      SCon{hex((Char.to_u32(c) % 16: U32)), SCon{hex((Char.to_u32(c) / 16: U32)), "00u\\" ++ out}}
    case False{}:
      SCon{c, out}

def escaped.go(s: String, out: String) -> String:
  match s:
    case SNil{}:
      String.reverse(out)
    case SCon{'"', rest}:
      escaped.go(rest, SCon{'"', SCon{'\\', out}})
    case SCon{'\\', rest}:
      escaped.go(rest, SCon{'\\', SCon{'\\', out}})
    case SCon{'\n', rest}:
      escaped.go(rest, SCon{'n', SCon{'\\', out}})
    case SCon{'\r', rest}:
      escaped.go(rest, SCon{'r', SCon{'\\', out}})
    case SCon{'\t', rest}:
      escaped.go(rest, SCon{'t', SCon{'\\', out}})
    case SCon{+c, rest}:
      escaped.go(rest, escaped.char(U32.is_lt(Char.to_u32(c), 32), c, out))

def quoted(s: String) -> String:
  "\"" ++ escaped.go(s, "") ++ "\""

# The pieces of `items` (last first), with a comma between each two, onto `out`.
def items(reversed: List<&2, Json>, out: List<&2, Piece>) -> List<&2, Piece>:
  match reversed:
    case Nil{}:
      out
    case Con{v, Nil{}}:
      PValue{v} <> out
    case Con{v, rest}:
      items(rest, PText{","} <> PValue{v} <> out)

# The pieces of `fields` (last first), with a comma between each two, onto `out`.
def fields(reversed: List<&2, JField>, out: List<&2, Piece>) -> List<&2, Piece>:
  match reversed:
    case Nil{}:
      out
    case Con{JField{k, v}, Nil{}}:
      PText{quoted(k) ++ ":"} <> PValue{v} <> out
    case Con{JField{k, v}, rest}:
      fields(rest, PText{","} <> PText{quoted(k) ++ ":"} <> PValue{v} <> out)

# A value as pieces, onto `rest`: its lists and objects open one level.
def pieces(v: Json, rest: List<&2, Piece>) -> List<&2, Piece>:
  match v:
    case JNull{}:
      PText{"null"} <> rest
    case JTrue{}:
      PText{"true"} <> rest
    case JFalse{}:
      PText{"false"} <> rest
    case JNumber{text}:
      PText{text} <> rest
    case JString{text}:
      PText{quoted(text)} <> rest
    case JArray{xs}:
      PText{"["} <> items(List.reverse(&2, Json, xs), PText{"]"} <> rest)
    case JObject{fs}:
      PText{"{"} <> fields(List.reverse(&2, JField, fs), PText{"}"} <> rest)

# The text of `todo`, chunk by chunk, onto `out` (last first). `fuel` bounds the pieces.
def write(fuel: Nat, todo: List<&2, Piece>, out: List<&2, String>) -> List<&2, String>:
  match fuel todo:
    case 0n _:
      out
    case _ Nil{}:
      out
    case 1n+f Con{PText{t}, rest}:
      write(f, rest, t <> out)
    case 1n+f Con{PValue{v}, rest}:
      write(f, pieces(v, rest), out)

def show(v: Json) -> String:
  Strings.joined(write(4294967295n, [PValue{v}], []), "")
