# The config: bend-lint.json, the nearest one up from the named file. It says what varies per project; the rules
# program says which rules there are.
#   {"entries": ["src/main.bend"], "imports": true, "rules": {"layout/case": "off", "no-unused/imports": "error"}}
# - entries: files that check the program the named file belongs to, relative to the config's folder.
# - imports: whether to lint the files the named file imports too. The command line's flag wins.
# - rules: a rule's setting, "off" or a severity.
import Base
import ./lint.bend as Lint
import ./shared.bend as Shared
import ./wire.bend as Wire

# JSON
# ====

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

type Token is Data:
  TOpen{}
  TClose{}
  TList{}
  TEnd{}
  TString{text: String}
  TWord{text: String}
  TSkip{}

# What a character is to the lexer.
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

# Where the lexer is: between tokens, in a string, after a \ in one, or in a word; the text so far (last first); and
# the tokens so far (last first).
type LexMode is Data:
  Between{}
  InText{}
  InEscape{}
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

# A character after a \ in a string.
def Json.unescaped(+c: Char) -> Char:
  Bool.pick(
    Char,
    Char.is_eq(c, 'n'),
    '\n',
    Bool.pick(Char, Char.is_eq(c, 't'), '\t', Bool.pick(Char, Char.is_eq(c, 'r'), '\r', c))
  )

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

def Lex.step(lex: Lex, glyph: JGlyph, +c: Char) -> Lex:
  match lex glyph:
    case Lex{Between{}, text, tokens} _:
      Lex.between(glyph, c, tokens)
    case Lex{InText{}, text, tokens} GQuote{}:
      Lex{Between{}, "", TString{String.reverse(text)} <> tokens}
    case Lex{InText{}, text, tokens} GBackslash{}:
      Lex{InEscape{}, text, tokens}
    case Lex{InText{}, text, tokens} _:
      Lex{InText{}, SCon{c, text}, tokens}
    case Lex{InEscape{}, text, tokens} _:
      Lex{InText{}, SCon{Json.unescaped(c), text}, tokens}
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

# The tokens of a text, in order.
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
    Shared.lookup(Json, w, [Shared.Named{"true", JTrue{}}, Shared.Named{"false", JFalse{}}, Shared.Named{"null", JNull{}}]),
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

# The JSON value of a text, if it is JSON.
def Json.read(text: String) -> Maybe<&2, Json>:
  Read.done(Read.go(Lex.done(Lex.go(text, Lex{Between{}, "", []})), Read{[], None{}}))

# Config
# ======

# What the config says of a rule: turn it off, or run it, with a severity for its findings if it gives one, and option
# values. Before a run, the runner checks the values against what the rule declares, and adds the defaults.
type Setting is Data:
  RuleOff{}
  RuleOn{severity: Maybe<&2, Lint.Severity>, options: List<&2, Shared.Named<Lint.Value>>}

# What a project's config says: the entries (paths), whether to lint imports (unless the command line says), and each rule's setting.
type Project is Data:
  Project{entries: List<&2, String>, imports: Maybe<&2, Bool>, rules: List<&2, Shared.Named<Setting>>}

def Severity.names() -> List<&2, Shared.Named<Lint.Severity>>:
  [
    Shared.Named{"error", Lint.Error{}},
    Shared.Named{"warning", Lint.Warning{}},
    Shared.Named{"information", Lint.Information{}},
    Shared.Named{"hint", Lint.Hint{}}
  ]

def Setting.names() -> List<&2, Shared.Named<Setting>>:
  [
    Shared.Named{"off", RuleOff{}},
    Shared.Named{"error", RuleOn{Some{Lint.Error{}}, []}},
    Shared.Named{"warning", RuleOn{Some{Lint.Warning{}}, []}},
    Shared.Named{"information", RuleOn{Some{Lint.Information{}}, []}},
    Shared.Named{"hint", RuleOn{Some{Lint.Hint{}}, []}}
  ]

# What is wrong with a config, if anything, or the config.
type Parsed is Data:
  Parsed{config: Project}
  Invalid{why: String}

def Parsed.entry(+folder: String, item: Json) -> Maybe<&2, String>:
  match item:
    case JString{path}:
      Some{folder ++ "/" ++ path}
    case _:
      None{}

def Parsed.entries(+folder: String, items: List<&2, Json>, out: List<&2, String>) -> Maybe<&2, List<&2, String>>:
  match items:
    case Nil{}:
      Some{List.reverse(&2, String, out)}
    case Con{i, rest}:
      do Maybe<&2, List<&2, String>>:
        e : String <- Parsed.entry(folder, i)
        Parsed.entries(folder, rest, e <> out)

# An option's value: a whole number, a flag or text.
def Parsed.value(value: Json) -> Maybe<&2, Lint.Value>:
  match value:
    case JNumber{text}:
      Maybe.map(&2, U32, Lint.Value, n => Lint.Num{n}, U32.read(text))
    case JTrue{}:
      Some{Lint.Flag{True{}}}
    case JFalse{}:
      Some{Lint.Flag{False{}}}
    case JString{text}:
      Some{Lint.Text{text}}
    case _:
      None{}

def Parsed.option(severity: Bool, +key: String, value: Json, out: Maybe<&2, List<&2, Shared.Named<Lint.Value>>>) ->
  Maybe<&2, List<&2, Shared.Named<Lint.Value>>>:
  match severity:
    case True{}:
      out
    case False{}:
      do Maybe<&2, List<&2, Shared.Named<Lint.Value>>>:
        values : List<&2, Shared.Named<Lint.Value>> <- out
        v : Lint.Value <- Parsed.value(value)
        return Shared.Named{key, v} <> values

# The option values of a rule's object, last first: every field but "severity".
def Parsed.options(fields: List<&2, JField>, out: Maybe<&2, List<&2, Shared.Named<Lint.Value>>>) ->
  Maybe<&2, List<&2, Shared.Named<Lint.Value>>>:
  match fields:
    case Nil{}:
      out
    case Con{JField{+key, value}, rest}:
      Parsed.options(rest, Parsed.option(String.eq(key, "severity"), key, value, out))

def Parsed.severity.of(here: Bool, value: Json, found: Maybe<&2, Maybe<&2, Lint.Severity>>) ->
  Maybe<&2, Maybe<&2, Lint.Severity>>:
  match here value:
    case True{} JString{+s}:
      Maybe.map(&2, Lint.Severity, Maybe<&2, Lint.Severity>, sev => Some{sev}, Shared.lookup(Lint.Severity, s, Severity.names()))
    case True{} _:
      None{}
    case False{} _:
      found

# The severity a rule's object gives in "severity": none if it gives none (Some{None{}}), or None{} if it is not one.
def Parsed.severity(fields: List<&2, JField>, found: Maybe<&2, Maybe<&2, Lint.Severity>>) -> Maybe<&2, Maybe<&2, Lint.Severity>>:
  match fields:
    case Nil{}:
      found
    case Con{JField{+key, value}, rest}:
      Parsed.severity(rest, Parsed.severity.of(String.eq(key, "severity"), value, found))

# A rule's setting: "off", a severity, or an object of a severity (if any) and option values.
def Parsed.rule(field: JField) -> Maybe<&2, Shared.Named<Setting>>:
  match field:
    case JField{+id, JString{+s}}:
      Maybe.map(&2, Setting, Shared.Named<Setting>, setting => Shared.Named{id, setting}, Shared.lookup(Setting, s, Setting.names()))
    case JField{+id, JObject{+fields}}:
      do Maybe<&2, Shared.Named<Setting>>:
        severity : Maybe<&2, Lint.Severity> <- Parsed.severity(fields, Some{None{}})
        options : List<&2, Shared.Named<Lint.Value>> <- Parsed.options(fields, Some{[]})
        return Shared.Named{id, RuleOn{severity, List.reverse(&2, Shared.Named<Lint.Value>, options)}}
    case _:
      None{}

def Parsed.rules(fields: List<&2, JField>, out: List<&2, Shared.Named<Setting>>) -> Maybe<&2, List<&2, Shared.Named<Setting>>>:
  match fields:
    case Nil{}:
      Some{List.reverse(&2, Shared.Named<Setting>, out)}
    case Con{f, rest}:
      do Maybe<&2, List<&2, Shared.Named<Setting>>>:
        r : Shared.Named<Setting> <- Parsed.rule(f)
        Parsed.rules(rest, r <> out)

def Parsed.invalid(problem: Maybe<&2, String>, then: Parsed) -> Parsed:
  match problem:
    case Some{why}:
      Invalid{why}
    case None{}:
      then

# A config's keys.
type Key is Data:
  Entries{}
  Imports{}
  Rules{}

def Key.names() -> List<&2, Shared.Named<Key>>:
  [Shared.Named{"entries", Entries{}}, Shared.Named{"imports", Imports{}}, Shared.Named{"rules", Rules{}}]

def Parsed.set(which: Maybe<&2, Key>, key: String, +folder: String, value: Json, config: Project) -> Parsed:
  match which value config:
    case Some{Entries{}} JArray{items} Project{entries, imports, rules}:
      Maybe.default(&2, Parsed, Maybe.map(&2, List<&2, String>, Parsed, es => Parsed{Project{es, imports, rules}}, Parsed.entries(folder, items, [])), Invalid{"entries must be a list of paths"})
    case Some{Imports{}} JTrue{} Project{entries, imports, rules}:
      Parsed{Project{entries, Some{True{}}, rules}}
    case Some{Imports{}} JFalse{} Project{entries, imports, rules}:
      Parsed{Project{entries, Some{False{}}, rules}}
    case Some{Rules{}} JObject{fields} Project{entries, imports, rules}:
      Maybe.default(&2, Parsed, Maybe.map(&2, List<&2, Shared.Named<Setting>>, Parsed, rs => Parsed{Project{entries, imports, rs}}, Parsed.rules(fields, [])), Invalid{"a rule's setting is \"off\", a severity, or an object of a severity and option values"})
    case Some{Entries{}} _ _:
      Invalid{"entries must be a list of paths"}
    case Some{Imports{}} _ _:
      Invalid{"imports must be true or false"}
    case Some{Rules{}} _ _:
      Invalid{"rules must map rule ids to settings"}
    case _ _ _:
      Invalid{"unknown key " ++ key}

# A config with one field more: `key` set to `value`.
def Parsed.field(+folder: String, field: JField, parsed: Parsed) -> Parsed:
  match field parsed:
    case _ Invalid{why}:
      Invalid{why}
    case JField{+key, value} Parsed{Project{entries, imports, rules}}:
      Parsed.set(Shared.lookup(Key, key, Key.names()), key, folder, value, Project{entries, imports, rules})

def Parsed.fields(+folder: String, fields: List<&2, JField>, parsed: Parsed) -> Parsed:
  match fields:
    case Nil{}:
      parsed
    case Con{f, rest}:
      Parsed.fields(folder, rest, Parsed.field(folder, f, parsed))

# The config a JSON value says, in the folder `folder`.
def Parsed.of(+folder: String, json: Maybe<&2, Json>) -> Parsed:
  match json:
    case Some{JObject{fields}}:
      Parsed.fields(folder, fields, Parsed{Project{[], None{}, []}})
    case _:
      Invalid{"not a JSON object"}

# Finding
# =======

# The real path of `path` (absolute, links resolved, "/" between its parts), as the server gives it.
def real.of(records: List<&2, List<&2, String>>) -> IO(String):
  match records:
    case Con{Con{tag, Con{path, Nil{}}}, Nil{}}:
      IO.pure(String, path)
    case _:
      IO.die(String, 1, "bend-lint: the checker's answer is malformed")

def real(path: String) -> IO(String):
  IO.bind(List<&2, List<&2, String>>, String, Wire.ask(["real", path]), real.of)

# The folders a path's folder parts make, nearest first; `at` is the folder so far, `out` the folders so far
# (nearest first).
def Folders.go(parts: List<&2, String>, +at: String, out: List<&2, String>) -> List<&2, String>:
  match parts:
    case Nil{}:
      out
    case Con{+p, rest}:
      Folders.go(rest, at ++ "/" ++ p, (at ++ "/" ++ p) <> out)

def Folders.from(parts: List<&2, String>) -> List<&2, String>:
  match parts:
    case Con{+first, rest}:
      Folders.go(rest, first, [first])
    case Nil{}:
      []

# A path's folder parts: its parts, less the last (the file's name).
def Folders.parts(reversed: List<&2, String>) -> List<&2, String>:
  match reversed:
    case Con{name, rest}:
      List.reverse(&2, String, rest)
    case Nil{}:
      []

# The folders a path is in, nearest first: "C:/a/b/c.bend" gives "C:/a/b", "C:/a", "C:"; "/a/b.bend" gives "/a", "".
def Folders.of(path: String) -> List<&2, String>:
  Folders.from(Folders.parts(List.reverse(&2, String, String.split(path, '/'))))

# A file's text: the chunks read so far (last first), from the last read `step`. `fuel` bounds the reads.
def Text.read(fuel: Nat, step: File & Result<&1, &1, U32 & String, String>, got: List<&2, String>) -> IO(String):
  match fuel step:
    case 1n+k Tuple{f, Done{SCon{h, t}}}:
      IO.bind(
        File & Result<&1, &1, U32 & String, String>,
        String,
        File.read(f, 65536),
        r => Text.read(k, r, SCon{h, t} <> got)
      )
    case _ Tuple{f, Done{SNil{}}}:
      do IO<String>:
        File.close(f)
        return String.concat(List.reverse(&2, String, got))
    case _ Tuple{f, Fail{Tuple{code, why}}}:
      do IO<String>:
        File.close(f)
        IO.die(String, 2, "bend-lint: reading a config failed: " ++ why)
    case 0n Tuple{f, Done{text}}:
      do IO<String>:
        File.close(f)
        IO.die(String, 2, "bend-lint: a config is too long")

def parsed(+path: String, parsed: Parsed) -> IO(Project):
  match parsed:
    case Parsed{config}:
      IO.pure(Project, config)
    case Invalid{why}:
      IO.die(Project, 2, "bend-lint: " ++ path ++ ": " ++ why)

# The config in `folder`, read from the file `file`.
def read(+folder: String, file: File) -> IO(Project):
  IO.bind(
    String,
    Project,
    IO.bind(File & Result<&1, &1, U32 & String, String>, String, File.read(file, 65536), r => Text.read(4294967295n, r, [])),
    text => parsed(folder ++ "/bend-lint.json", Parsed.of(folder, Json.read(text)))
  )

# The config of the nearest folder of `folders` that has one, from the last attempt to open one (in `folder`).
def search(folders: List<&2, String>, opened: Result<&1, &1, U32 & String, File>, +folder: String) -> IO(Project):
  match folders opened:
    case _ Done{file}:
      read(folder, file)
    case Con{+next, rest} Fail{why}:
      IO.bind(
        Result<&1, &1, U32 & String, File>,
        Project,
        File.open(next ++ "/bend-lint.json", "r"),
        r => search(rest, r, next)
      )
    case Nil{} Fail{why}:
      IO.pure(Project, Project{[], None{}, []})

# The config of the file at the real path `path`: the nearest bend-lint.json up from it, or an empty one.
def find(path: String) -> IO(Project):
  search(Folders.of(path), Fail{(0, "")}, "")
