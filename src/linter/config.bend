# bend-lint.json. Its format is in the README.
import Base
import ../files/main.bend as Files
import ../json/main.bend as Json
import ../shared/names.bend as Names
import ./lint.bend as Lint

# Config
# ======

# What the config says of a rule: turn it off, or run it, with a severity for its findings if it gives one, and option
# values. Before a run, the runner checks the values against what the rule declares, and adds the defaults.
type Setting is Data:
  RuleOff{}
  RuleOn{severity: Maybe<&2, Lint.Severity>, options: List<&2, Names.Named<Lint.Value>>}

type Project is Data:
  Project{
    entries: List<&2, String>,
    imports: Maybe<&2, Bool>,
    rules: List<&2, Names.Named<Setting>>
  }

def Setting.severities(
  names: List<&2, Names.Named<Lint.Severity>>
) -> List<&2, Names.Named<Setting>>:
  match names:
    case Nil{}:
      []
    case Con{Names.Named{name, severity}, rest}:
      Names.Named{name, RuleOn{Some{severity}, []}} <> Setting.severities(rest)

def Setting.names() -> List<&2, Names.Named<Setting>>:
  Names.Named{"off", RuleOff{}} <> Setting.severities(Lint.Severity.names())

def Parsed.entry(folder: String, item: Json.Json) -> Maybe<&2, String>:
  match item:
    case Json.JString{path}:
      Some{folder ++ "/" ++ path}
    case _:
      None{}

def Parsed.entries(
  +folder: String,
  items: List<&2, Json.Json>,
  out: List<&2, String>
) -> Maybe<&2, List<&2, String>>:
  match items:
    case Nil{}:
      Some{List.reverse(&2, String, out)}
    case Con{i, rest}:
      do Maybe<&2, List<&2, String>>:
        e: String <- Parsed.entry(folder, i)
        Parsed.entries(folder, rest, e <> out)

def Parsed.value(value: Json.Json) -> Maybe<&2, Lint.Value>:
  match value:
    case Json.JNumber{text}:
      Maybe.map(&2, U32, Lint.Value, n => Lint.Num{n}, U32.read(text))
    case Json.JTrue{}:
      Some{Lint.Flag{True{}}}
    case Json.JFalse{}:
      Some{Lint.Flag{False{}}}
    case Json.JString{text}:
      Some{Lint.Text{text}}
    case _:
      None{}

def Parsed.option(
  severity: Bool,
  key: String,
  value: Json.Json,
  out: Maybe<&2, List<&2, Names.Named<Lint.Value>>>
) -> Maybe<&2, List<&2, Names.Named<Lint.Value>>>:
  match severity:
    case True{}:
      out
    case False{}:
      do Maybe<&2, List<&2, Names.Named<Lint.Value>>>:
        values: List<&2, Names.Named<Lint.Value>> <- out
        v: Lint.Value <- Parsed.value(value)
        return Names.Named{key, v} <> values

# The option values of a rule's object, last first: every field but "severity".
def Parsed.options(
  fields: List<&2, Json.JField>,
  out: Maybe<&2, List<&2, Names.Named<Lint.Value>>>
) -> Maybe<&2, List<&2, Names.Named<Lint.Value>>>:
  match fields:
    case Nil{}:
      out
    case Con{Json.JField{+key, value}, rest}:
      Parsed.options(rest, Parsed.option(String.eq(key, "severity"), key, value, out))

def Parsed.severity.of(
  here: Bool,
  value: Json.Json,
  found: Maybe<&2, Maybe<&2, Lint.Severity>>
) -> Maybe<&2, Maybe<&2, Lint.Severity>>:
  match here value:
    case True{} Json.JString{s}:
      Maybe.map(
        &2,
        Lint.Severity,
        Maybe<&2, Lint.Severity>,
        sev => Some{sev},
        Names.lookup(Lint.Severity, s, Lint.Severity.names())
      )
    case True{} _:
      None{}
    case False{} _:
      found

# The severity a rule's object gives in "severity": none if it gives none (Some{None{}}), or None{} if it is not one.
def Parsed.severity(
  fields: List<&2, Json.JField>,
  found: Maybe<&2, Maybe<&2, Lint.Severity>>
) -> Maybe<&2, Maybe<&2, Lint.Severity>>:
  match fields:
    case Nil{}:
      found
    case Con{Json.JField{key, value}, rest}:
      Parsed.severity(rest, Parsed.severity.of(String.eq(key, "severity"), value, found))

# A rule's setting: "off", a severity, or an object of a severity (if any) and option values.
def Parsed.rule(field: Json.JField) -> Maybe<&2, Names.Named<Setting>>:
  match field:
    case Json.JField{id, Json.JString{s}}:
      Maybe.map(
        &2,
        Setting,
        Names.Named<Setting>,
        setting => Names.Named{id, setting},
        Names.lookup(Setting, s, Setting.names())
      )
    case Json.JField{+id, Json.JObject{+fields}}:
      do Maybe<&2, Names.Named<Setting>>:
        severity: Maybe<&2, Lint.Severity> <- Parsed.severity(fields, Some{None{}})
        options: List<&2, Names.Named<Lint.Value>> <- Parsed.options(fields, Some{[]})
        return Names.Named{id, RuleOn{severity, List.reverse(&2, Names.Named<Lint.Value>, options)}}
    case _:
      None{}

def Parsed.rules(
  fields: List<&2, Json.JField>,
  out: List<&2, Names.Named<Setting>>
) -> Maybe<&2, List<&2, Names.Named<Setting>>>:
  match fields:
    case Nil{}:
      Some{List.reverse(&2, Names.Named<Setting>, out)}
    case Con{f, rest}:
      do Maybe<&2, List<&2, Names.Named<Setting>>>:
        r: Names.Named<Setting> <- Parsed.rule(f)
        Parsed.rules(rest, r <> out)

type Key is Data:
  Entries{}
  Imports{}
  Rules{}

def Key.names() -> List<&2, Names.Named<Key>>:
  [
    Names.Named{"entries", Entries{}},
    Names.Named{"imports", Imports{}},
    Names.Named{"rules", Rules{}}
  ]

def Parsed.set(
  which: Maybe<&2, Key>,
  key: String,
  folder: String,
  value: Json.Json,
  config: Project
) -> Result<&2, &2, String, Project>:
  match which value config:
    case Some{Entries{}} Json.JArray{items} Project{entries, imports, rules}:
      Maybe.default(
        &2,
        Result<&2, &2, String, Project>,
        Maybe.map(
          &2,
          List<&2, String>,
          Result<&2, &2, String, Project>,
          es => Done{Project{es, imports, rules}},
          Parsed.entries(folder, items, [])
        ),
        Fail{"entries must be a list of paths"}
      )
    case Some{Imports{}} Json.JTrue{} Project{entries, imports, rules}:
      Done{Project{entries, Some{True{}}, rules}}
    case Some{Imports{}} Json.JFalse{} Project{entries, imports, rules}:
      Done{Project{entries, Some{False{}}, rules}}
    case Some{Rules{}} Json.JObject{fields} Project{entries, imports, rules}:
      Maybe.default(
        &2,
        Result<&2, &2, String, Project>,
        Maybe.map(
          &2,
          List<&2, Names.Named<Setting>>,
          Result<&2, &2, String, Project>,
          rs => Done{Project{entries, imports, rs}},
          Parsed.rules(fields, [])
        ),
        Fail{
          "a rule's setting is \"off\", a severity, or an object of a severity and option values"
        }
      )
    case Some{Entries{}} _ _:
      Fail{"entries must be a list of paths"}
    case Some{Imports{}} _ _:
      Fail{"imports must be true or false"}
    case Some{Rules{}} _ _:
      Fail{"rules must map rule ids to settings"}
    case _ _ _:
      Fail{"unknown key " ++ key}

def Parsed.field(
  folder: String,
  field: Json.JField,
  parsed: Result<&2, &2, String, Project>
) -> Result<&2, &2, String, Project>:
  match field parsed:
    case _ Fail{why}:
      Fail{why}
    case Json.JField{+key, value} Done{Project{entries, imports, rules}}:
      Parsed.set(
        Names.lookup(Key, key, Key.names()),
        key,
        folder,
        value,
        Project{entries, imports, rules}
      )

def Parsed.fields(
  +folder: String,
  fields: List<&2, Json.JField>,
  parsed: Result<&2, &2, String, Project>
) -> Result<&2, &2, String, Project>:
  match fields:
    case Nil{}:
      parsed
    case Con{f, rest}:
      Parsed.fields(folder, rest, Parsed.field(folder, f, parsed))

# The config a JSON value says, in the folder `folder`.
def Parsed.of(folder: String, json: Maybe<&2, Json.Json>) -> Result<&2, &2, String, Project>:
  match json:
    case Some{Json.JObject{fields}}:
      Parsed.fields(folder, fields, Done{Project{[], None{}, []}})
    case _:
      Fail{"not a JSON object"}

# Finding
# =======
def parsed(path: String, parsed: Result<&2, &2, String, Project>) -> IO(Project):
  match parsed:
    case Done{config}:
      IO.pure(Project, config)
    case Fail{why}:
      IO.die(Project, 2, "bend-lint: " ++ path ++ ": " ++ why)

def read(+folder: String, text: Result<&2, &2, String, String>) -> IO(Project):
  match text:
    case Done{t}:
      parsed(folder ++ "/bend-lint.json", Parsed.of(folder, Json.read(t)))
    case Fail{why}:
      IO.die(Project, 2, "bend-lint: reading a config failed: " ++ why)

def opened(nearest: Maybe<&1, String & File>) -> IO(Project):
  match nearest:
    case Some{Tuple{folder, file}}:
      IO.bind(Result<&2, &2, String, String>, Project, Files.read(file), text => read(folder, text))
    case None{}:
      IO.pure(Project, Project{[], None{}, []})

# The config of the file at the real path `path`: the nearest bend-lint.json up from it, or an empty one.
def find(path: String) -> IO(Project):
  IO.bind(Maybe<&1, String & File>, Project, Files.nearest(path, "bend-lint.json"), opened)
