# A rules program calls `run` with its rules: `Cli.run(~[R.rule()])`.
import Base
import ../files/main.bend as Files
import ../json/main.bend as Json
import ../shared/lists.bend as Lists
import ../shared/names.bend as Names
import ../text/main.bend as Text
import ./directives.bend as Directives
import ./fixes.bend as Fixes
import ./lint.bend as Lint

# Config
# ======
# bend-lint.json. Its format is in the README.

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

def Config.parsed(path: String, parsed: Result<&2, &2, String, Project>) -> IO(Project):
  match parsed:
    case Done{config}:
      IO.pure(Project, config)
    case Fail{why}:
      IO.die(Project, 2, "bend-lint: " ++ path ++ ": " ++ why)

def Config.read(+folder: String, text: Result<&2, &2, String, String>) -> IO(Project):
  match text:
    case Done{t}:
      Config.parsed(folder ++ "/bend-lint.json", Parsed.of(folder, Json.read(t)))
    case Fail{why}:
      IO.die(Project, 2, "bend-lint: reading a config failed: " ++ why)

def Config.opened(nearest: Maybe<&1, String & File>) -> IO(Project):
  match nearest:
    case Some{Tuple{folder, file}}:
      IO.bind(
        Result<&2, &2, String, String>,
        Project,
        Files.read(file),
        text => Config.read(folder, text)
      )
    case None{}:
      IO.pure(Project, Project{[], None{}, []})

# The config of the file at the real path `path`: the nearest bend-lint.json up from it, or an empty one.
def Config.find(path: String) -> IO(Project):
  IO.bind(Maybe<&1, String & File>, Project, Files.nearest(path, "bend-lint.json"), Config.opened)

# Seam
# ====
# The seam to Bend's checker, for as long as it is TS: the requests to seam.ts, and the reading of its answers. A
# check's answer holds the linter's program as seam.ts makes it of what Bend's parser and checker gave (see `check` in
# seam.ts). When the checker is Bend, glue in Bend makes the program, and this section goes.
# - A request is one connection: one line out, the answer in, then the server closes.
# - A line is fields split by a tab. A field escapes \, a tab and a newline as \\, \t and \n.
# - The answer is one line per record. Its first field is its kind.

# What checking a file gives: its program, and the check's number on the server; or, if the check failed, the files it
# read, and, if it parsed them, the program they make, without facts.
type Check is Data:
  Passed{program: Lint.Program, check: U32}
  Failed{read: List<&2, String>, parsed: Maybe<&2, Lint.Program>}

# Requests
# --------
type Mark is Data:
  Slash{}
  Tab{}
  Newline{}
  Plain{}

# An answer read so far: whether a \ came just before, the field, the record's fields and the records, each last
# first.
type Reading is Data:
  Reading{
    escaped: Bool,
    field: String,
    fields: List<&2, String>,
    records: List<&2, List<&2, String>>
  }

def Wire.mark(c: Char) -> Mark:
  match c:
    case '\\':
      Slash{}
    case '\t':
      Tab{}
    case '\n':
      Newline{}
    case _:
      Plain{}

# A field's character with its escape undone: the character after a \.
def Wire.unescaped(c: Char) -> Char:
  match c:
    case 'n':
      '\n'
    case 't':
      '\t'
    case _:
      c

def Wire.read(mark: Mark, c: Char, r: Reading) -> Reading:
  match mark r:
    case _ Reading{True{}, field, fields, records}:
      Reading{False{}, SCon{Wire.unescaped(c), field}, fields, records}
    case Slash{} Reading{False{}, field, fields, records}:
      Reading{True{}, field, fields, records}
    case Tab{} Reading{False{}, field, fields, records}:
      Reading{False{}, "", String.reverse(field) <> fields, records}
    case Newline{} Reading{False{}, field, fields, records}:
      Reading{False{}, "", [], List.reverse(&2, String, String.reverse(field) <> fields) <> records}
    case Plain{} Reading{False{}, field, fields, records}:
      Reading{False{}, SCon{c, field}, fields, records}

def Wire.read_text(s: String, r: Reading) -> Reading:
  match s:
    case SNil{}:
      r
    case SCon{+c, t}:
      Wire.read_text(t, Wire.read(Wire.mark(c), c, r))

# The records of an answer's chunks, in order. A last record with no newline is dropped.
def Wire.records(chunks: List<&2, String>, r: Reading) -> List<&2, List<&2, String>>:
  match chunks r:
    case Nil{} Reading{escaped, field, fields, records}:
      List.reverse(&2, List<&2, String>, records)
    case Con{h, t} _:
      Wire.records(t, Wire.read_text(h, r))

# A character onto a field, escaped, onto `out`, which is last first.
def Wire.write(mark: Mark, c: Char, out: String) -> String:
  match mark:
    case Slash{}:
      SCon{'\\', SCon{'\\', out}}
    case Tab{}:
      SCon{'t', SCon{'\\', out}}
    case Newline{}:
      SCon{'n', SCon{'\\', out}}
    case Plain{}:
      SCon{c, out}

def Wire.field(s: String, out: String) -> String:
  match s:
    case SNil{}:
      out
    case SCon{+c, t}:
      Wire.field(t, Wire.write(Wire.mark(c), c, out))

# A request's line, from its fields; `out` is the line so far, last first.
def Wire.line(fields: List<&2, String>, out: String) -> String:
  match fields:
    case Nil{}:
      String.reverse(SCon{'\n', out})
    case Con{h, Nil{}}:
      String.reverse(SCon{'\n', Wire.field(h, out)})
    case Con{h, t}:
      Wire.line(t, SCon{'\t', Wire.field(h, out)})

# The chunks read until the server closes, last first, from the last read `step`. `fuel` bounds the reads.
def Wire.receive(
  fuel: Nat,
  step: Socket & Result<&1, &1, U32 & String, Maybe<&1, String>>,
  got: List<&2, String>
) -> IO(List<&2, String>):
  match fuel step:
    case 1n+k Tuple{s, Done{Some{text}}}:
      IO.bind(
        Socket & Result<&1, &1, U32 & String, Maybe<&1, String>>,
        List<&2, String>,
        TCP.recv(s, 65536),
        r => Wire.receive(k, r, text <> got)
      )
    case _ Tuple{s, Done{None{}}}:
      do IO<List<&2, String>>:
        Socket.close(s)
        return got
    case _ Tuple{s, Fail{Tuple{code, why}}}:
      do IO<List<&2, String>>:
        Socket.close(s)
        IO.die(List<&2, String>, 1, "bend-lint: reading the checker's answer failed: " ++ why)
    case 0n Tuple{s, Done{Some{text}}}:
      do IO<List<&2, String>>:
        Socket.close(s)
        IO.die(List<&2, String>, 1, "bend-lint: the checker's answer is too long")

def Wire.sent(r: Socket & Result<&1, &1, (U32 & String) & String, Unit>) -> IO(List<&2, String>):
  match r:
    case Tuple{s, Done{u}}:
      IO.bind(
        Socket & Result<&1, &1, U32 & String, Maybe<&1, String>>,
        List<&2, String>,
        TCP.recv(s, 65536),
        step => Wire.receive(4294967295n, step, [])
      )
    case Tuple{s, Fail{Tuple{Tuple{code, why}, rest}}}:
      do IO<List<&2, String>>:
        Socket.close(s)
        IO.die(List<&2, String>, 1, "bend-lint: asking the checker failed: " ++ why)

def Wire.port.of(port: Maybe<&2, U32>) -> IO(U32):
  match port:
    case Some{p}:
      IO.pure(U32, p)
    case None{}:
      IO.die(
        U32,
        2,
        "bend-lint: BEND_LINT_PORT is not a port; run this program with `bend-lint --program <it>`"
      )

def Wire.port() -> IO(U32):
  do IO<U32>:
    text: String <- IO.try(String, IO.get_env("BEND_LINT_PORT"))
    Wire.port.of(U32.read(text))

# An answer's records, unless the server says it failed to answer (`fail` and why): that stops the run.
def Wire.answered(records: List<&2, List<&2, String>>) -> IO(List<&2, List<&2, String>>):
  match records:
    case Con{Con{SCon{'f', SCon{'a', SCon{'i', SCon{'l', SNil{}}}}}, Con{why, Nil{}}}, Nil{}}:
      IO.die(List<&2, List<&2, String>>, 1, "bend-lint: the checker failed: " ++ why)
    case _:
      IO.pure(List<&2, List<&2, String>>, records)

def Wire.ask(request: List<&2, String>) -> IO(List<&2, List<&2, String>>):
  do IO<List<&2, List<&2, String>>>:
    p: U32 <- Wire.port()
    sock: Socket <- IO.try(Socket, TCP.connect("127.0.0.1", p))
    s: Socket
      & Result<&1, &1, (U32 & String) & String, Unit> <- TCP.send(sock, Wire.line(request, ""))
    got: List<&2, String> <- Wire.sent(s)
    Wire.answered(Wire.records(List.reverse(&2, String, got), Reading{False{}, "", [], []}))

# Programs
# --------

# A quantity as an answer writes it (see `quantity` in seam.ts).
def Quantity.of(field: String) -> Lint.Quantity:
  match field:
    case SCon{'e', SNil{}}:
      Lint.Erased{}
    case SCon{'o', SNil{}}:
      Lint.Once{}
    case SCon{'t', SNil{}}:
      Lint.Template{}
    case _:
      Lint.Many{}

def Quantity.maybe(field: String) -> Maybe<&2, Lint.Quantity>:
  match field:
    case SNil{}:
      None{}
    case SCon{c, rest}:
      Some{Quantity.of(SCon{c, rest})}

def number(field: String) -> U32:
  Maybe.default(&2, U32, U32.read(field), 0)

# What a node is, from its tag (see TAGS in seam.ts) and what an answer writes of its kind: its target or binder (`a`),
# then its quantity, or whether it is unsafe (`b`).
def Syntax.of(tag: Char, a: String, b: String) -> Maybe<&2, Lint.Syntax>:
  match tag:
    case 'I':
      Some{Lint.Import{a}}
    case 'i':
      Some{Lint.ImportPath{}}
    case 'D':
      Some{Lint.Definition{a, String.eq(b, "1")}}
    case 'T':
      Some{Lint.Datatype{a}}
    case 'C':
      Some{Lint.Constructor{a}}
    case 'W':
      Some{Lint.Law{a}}
    case 'p':
      Some{Lint.Parameter{number(a), Quantity.of(b)}}
    case 'f':
      Some{Lint.Field{number(a), Quantity.of(b)}}
    case 'R':
      Some{Lint.Returns{}}
    case 'B':
      Some{Lint.Body{}}
    case 'v':
      Some{Lint.Variable{number(a)}}
    case 'r':
      Some{Lint.Reference{a}}
    case 's':
      Some{Lint.Substitution{}}
    case 'l':
      Some{Lint.Let{}}
    case 'b':
      Some{Lint.Binding{number(a), Quantity.of(b)}}
    case 'S':
      Some{Lint.Sort{}}
    case 'q':
      Some{Lint.QuantityType{}}
    case 'Q':
      Some{Lint.QuantityLiteral{Quantity.of(b)}}
    case 'm':
      Some{Lint.QuantityMinimum{}}
    case 'F':
      Some{Lint.Forall{number(a), Quantity.of(b)}}
    case 'L':
      Some{Lint.Lambda{number(a), Quantity.maybe(b)}}
    case 'A':
      Some{Lint.Application{}}
    case 't':
      Some{Lint.TypeApplication{a}}
    case 'c':
      Some{Lint.Construction{a}}
    case 'n':
      Some{Lint.Literal{a}}
    case 'E':
      Some{Lint.Elimination{a}}
    case 'a':
      Some{Lint.Absurd{}}
    case 'e':
      Some{Lint.Equality{}}
    case 'y':
      Some{Lint.Reflexivity{}}
    case 'w':
      Some{Lint.Rewrite{}}
    case 'h':
      Some{Lint.Hole{}}
    case 'N':
      Some{Lint.Annotation{}}
    case 'M':
      Some{Lint.Match{}}
    case 'k':
      Some{Lint.Case{}}
    case 'd':
      Some{Lint.Destructure{Quantity.of(b)}}
    case 'x':
      Some{Lint.PatternVariable{number(a), Quantity.of(b)}}
    case 'X':
      Some{Lint.PatternConstructor{a}}
    case _:
      None{}

# A check's answer as read so far: its number, whether it failed, the files it read (last first), the files read whole
# (last first), the file being read, without its nodes, the nodes read of it whose parent is not read yet (last first),
# and the facts read for the next node (last first). A node comes after the nodes under it.
type Reader is Data:
  Reader{
    check: Maybe<&2, U32>,
    failed: Bool,
    read: List<&2, String>,
    sources: List<&2, Lint.Source>,
    open: Maybe<&2, Lint.Source>,
    nodes: List<&2, Lint.Node>,
    facts: List<&2, Lint.Fact>
  }
  Garbled{}

def Span.of(path: String, beg: Maybe<&2, U32>, end: Maybe<&2, U32>) -> Maybe<&2, Lint.Span>:
  match beg end:
    case Some{b} Some{e}:
      Some{Lint.Span{path, b, e}}
    case _ _:
      None{}

# The top `n` of `stack`, in order (the last pushed last), and the rest of it.
def pop(
  n: Nat,
  stack: List<&2, Lint.Node>,
  out: List<&2, Lint.Node>
) -> List<&2, Lint.Node>
  & List<&2, Lint.Node>:
  match n stack:
    case 1n+k Con{x, rest}:
      pop(k, rest, x <> out)
    case _ _:
      (out, stack)

def Reader.made(
  syntax: Lint.Syntax,
  name: String,
  span: Maybe<&2, Lint.Span>,
  facts: List<&2, Lint.Fact>,
  popped: List<&2, Lint.Node> & List<&2, Lint.Node>
) -> List<&2, Lint.Node>:
  match popped:
    case Tuple{kids, rest}:
      Lint.Node{syntax, name, span, kids, List.reverse(&2, Lint.Fact, facts)} <> rest

def Reader.node(
  syntax: Maybe<&2, Lint.Syntax>,
  name: String,
  beg: String,
  end: String,
  kids: String,
  r: Reader
) -> Reader:
  match syntax r:
    case Some{
      s
    } Reader{
      check,
      failed,
      read,
      sources,
      Some{Lint.Source{+path, namespace, text, none}},
      nodes,
      facts
    }:
      Reader{
        check,
        failed,
        read,
        sources,
        Some{Lint.Source{path, namespace, text, none}},
        Reader.made(
          s,
          name,
          Span.of(path, U32.read(beg), U32.read(end)),
          facts,
          pop(U32.to_nat(number(kids)), nodes, [])
        ),
        []
      }
    case _ _:
      Garbled{}

def Role.of(field: String) -> Lint.Role:
  match field:
    case SCon{'b', SNil{}}:
      Lint.OfBinder{}
    case _:
      Lint.OfTerm{}

def Reader.fact(role: String, q: String, used: String, handle: String, r: Reader) -> Reader:
  match r:
    case Reader{+check, failed, read, sources, open, nodes, facts}:
      Reader{
        check,
        failed,
        read,
        sources,
        open,
        nodes,
        Lint.Fact{
          Role.of(role),
          Quantity.of(q),
          Quantity.maybe(used),
          Lint.TypeRef{Maybe.default(&2, U32, check, 0), number(handle)}
        }
          <> facts
      }
    case Garbled{}:
      Garbled{}

# The files read whole, with the one being read, whose nodes are `nodes`.
def Reader.close(
  open: Maybe<&2, Lint.Source>,
  nodes: List<&2, Lint.Node>,
  sources: List<&2, Lint.Source>
) -> List<&2, Lint.Source>:
  match open:
    case Some{Lint.Source{path, namespace, text, none}}:
      Lint.Source{path, namespace, text, List.reverse(&2, Lint.Node, nodes)} <> sources
    case None{}:
      sources

def Reader.file(path: String, namespace: String, text: String, r: Reader) -> Reader:
  match r:
    case Reader{check, failed, read, sources, open, nodes, facts}:
      Reader{
        check,
        failed,
        read,
        Reader.close(open, nodes, sources),
        Some{Lint.Source{path, namespace, text, []}},
        [],
        []
      }
    case Garbled{}:
      Garbled{}

def Reader.checked(n: Maybe<&2, U32>, r: Reader) -> Reader:
  match r:
    case Reader{check, failed, read, sources, open, nodes, facts}:
      Reader{n, failed, read, sources, open, nodes, facts}
    case Garbled{}:
      Garbled{}

def Reader.failed(r: Reader) -> Reader:
  match r:
    case Reader{check, failed, read, sources, open, nodes, facts}:
      Reader{check, True{}, read, sources, open, nodes, facts}
    case Garbled{}:
      Garbled{}

def Reader.read(path: String, r: Reader) -> Reader:
  match r:
    case Reader{check, failed, read, sources, open, nodes, facts}:
      Reader{check, failed, path <> read, sources, open, nodes, facts}
    case Garbled{}:
      Garbled{}

# The reader after a record of a check's answer (see `check` in seam.ts): a fact, a node, the check's number, that it
# failed, a file it read, or a file it parsed.
def Reader.add(fields: List<&2, String>, r: Reader) -> Reader:
  match fields:
    case Con{SCon{'+', SNil{}}, Con{role, Con{q, Con{used, Con{handle, Nil{}}}}}}:
      Reader.fact(role, q, used, handle, r)
    case Con{SCon{tag, SNil{}}, Con{name, Con{beg, Con{end, Con{kids, Con{a, Con{b, Nil{}}}}}}}}:
      Reader.node(Syntax.of(tag, a, b), name, beg, end, kids, r)
    case Con{SCon{'c', rest}, Con{n, Nil{}}}:
      Reader.checked(U32.read(n), r)
    case Con{SCon{'f', SCon{'a', rest}}, Nil{}}:
      Reader.failed(r)
    case Con{SCon{'r', rest}, Con{path, Nil{}}}:
      Reader.read(path, r)
    case Con{SCon{'f', SCon{'i', rest}}, Con{path, Con{namespace, Con{text, Nil{}}}}}:
      Reader.file(path, namespace, text, r)
    case _:
      Garbled{}

def Reader.go(records: List<&2, List<&2, String>>, r: Reader) -> Reader:
  match records:
    case Nil{}:
      r
    case Con{fields, rest}:
      Reader.go(rest, Reader.add(fields, r))

def Check.from(
  failed: Bool,
  check: Maybe<&2, U32>,
  read: List<&2, String>,
  sources: List<&2, Lint.Source>
) -> Maybe<&2, Check>:
  match failed check sources:
    case False{} Some{n} _:
      Some{Passed{Lint.Program{sources}, n}}
    case True{} _ Nil{}:
      Some{Failed{read, None{}}}
    case True{} _ parsed:
      Some{Failed{read, Some{Lint.Program{parsed}}}}
    case _ _ _:
      None{}

# What an answer says, if it is one.
def Reader.done(r: Reader) -> Maybe<&2, Check>:
  match r:
    case Reader{check, failed, read, sources, open, nodes, facts}:
      Check.from(
        failed,
        check,
        List.reverse(&2, String, read),
        List.reverse(&2, Lint.Source, Reader.close(open, nodes, sources))
      )
    case Garbled{}:
      None{}

# Questions
# ---------
def Question.field(q: Lint.Question) -> String:
  match q:
    case Lint.Show{Lint.TypeRef{c, h}}:
      "show:" ++ U32.show(c) ++ ":" ++ U32.show(h)
    case Lint.Same{Lint.TypeRef{c, h}, Lint.TypeRef{d, i}}:
      "same:" ++ U32.show(c) ++ ":" ++ U32.show(h) ++ ":" ++ U32.show(d) ++ ":" ++ U32.show(i)
    case Lint.Normal{Lint.TypeRef{c, h}}:
      "normal:" ++ U32.show(c) ++ ":" ++ U32.show(h)

def Question.fields(questions: List<&2, Lint.Question>, out: List<&2, String>) -> List<&2, String>:
  match questions:
    case Nil{}:
      List.reverse(&2, String, out)
    case Con{q, rest}:
      Question.fields(rest, Question.field(q) <> out)

def Answer.read(record: List<&2, String>) -> Maybe<&2, Lint.Answer>:
  match record:
    case Con{SCon{'s', SCon{'h', rest}}, Con{text, Nil{}}}:
      Some{Lint.Shown{text}}
    case Con{SCon{'s', SCon{'a', rest}}, Con{same, Nil{}}}:
      Some{Lint.Equal{String.eq(same, "true")}}
    case Con{SCon{'n', rest}, Con{check, Con{handle, Nil{}}}}:
      Maybe.map(&2, U32, Lint.Answer, h => Lint.Normalized{h}, U32.read(handle))
    case _:
      None{}

def Answer.all(
  records: List<&2, List<&2, String>>,
  out: List<&2, Lint.Answer>
) -> Maybe<&2, List<&2, Lint.Answer>>:
  match records:
    case Nil{}:
      Some{List.reverse(&2, Lint.Answer, out)}
    case Con{r, rest}:
      do Maybe<&2, List<&2, Lint.Answer>>:
        a: Lint.Answer <- Answer.read(r)
        Answer.all(rest, a <> out)

def Answer.got(answers: Maybe<&2, List<&2, Lint.Answer>>) -> IO(List<&2, Lint.Answer>):
  match answers:
    case Some{a}:
      IO.pure(List<&2, Lint.Answer>, a)
    case None{}:
      IO.die(List<&2, Lint.Answer>, 1, "bend-lint: the checker's answers are malformed")

def answers(questions: List<&2, Lint.Question>) -> IO(List<&2, Lint.Answer>):
  IO.bind(
    List<&2, List<&2, String>>,
    List<&2, Lint.Answer>,
    Wire.ask("ask" <> Question.fields(questions, [])),
    records => Answer.got(Answer.all(records, []))
  )

# Checks
# ------
def Check.got(check: Maybe<&2, Check>) -> IO(Check):
  match check:
    case Some{c}:
      IO.pure(Check, c)
    case None{}:
      IO.die(Check, 1, "bend-lint: the checker's answer is malformed")

def Check.request(path: String, facts: Bool, wanted: List<&2, String>) -> List<&2, String>:
  match facts:
    case True{}:
      "check" <> path <> "facts" <> wanted
    case False{}:
      ["check", path, "syntax"]

# Checks the file at `path`: with `facts`, the checker's facts on the files at `wanted` (on each file, if none).
def Check.file(path: String, facts: Bool, wanted: List<&2, String>) -> IO(Check):
  IO.bind(
    List<&2, List<&2, String>>,
    Check,
    Wire.ask(Check.request(path, facts, wanted)),
    records => Check.got(
      Reader.done(Reader.go(records, Reader{None{}, False{}, [], [], None{}, [], []}))
    )
  )

# Frees what the server holds for the passed check numbered `check`: no rule asks about its types again.
def Check.forget(check: U32) -> IO(Unit):
  IO.bind(
    List<&2, List<&2, String>>,
    Unit,
    Wire.ask(["forget", U32.show(check)]),
    records => IO.pure(Unit, Unit{})
  )

# Rules
# =====

# What the runner reads of a rule, besides its run: its id, what it needs, the options it declares, and, for a program
# rule, whether its findings must be found by every check.
type About is Data:
  About{id: String, needs: Lint.Needs, options: List<&2, Lint.Declared>, every: Maybe<&2, Bool>}

def About.all(rules: List<&1, Lint.Rule>, out: List<&2, About>) -> List<&2, About>:
  match rules:
    case Nil{}:
      List.reverse(&2, About, out)
    case Con{Lint.Rule{id, needs, options, Lint.OnFile{run}}, rest}:
      About.all(rest, About{id, needs, options, None{}} <> out)
    case Con{Lint.Rule{id, needs, options, Lint.OnProgram{every, run}}, rest}:
      About.all(rest, About{id, needs, options, Some{every}} <> out)

def About.facts(about: About) -> Bool:
  match about:
    case About{id, Lint.Needs{facts, declarations}, options, every}:
      facts

def About.declarations(about: About) -> Bool:
  match about:
    case About{id, Lint.Needs{facts, declarations}, options, every}:
      declarations

def About.whole(about: About) -> Bool:
  match about:
    case About{id, needs, options, every}:
      Maybe.is_some(&2, Bool, every)

def Setting.on(setting: Maybe<&2, Setting>) -> Bool:
  match setting:
    case Some{RuleOff{}}:
      False{}
    case _:
      True{}

def Setting.severity(setting: Maybe<&2, Setting>) -> Maybe<&2, Lint.Severity>:
  match setting:
    case Some{RuleOn{severity, options}}:
      severity
    case _:
      None{}

# A rule's option values, once settled: each declared one, given or its default.
def Setting.options(setting: Maybe<&2, Setting>) -> List<&2, Names.Named<Lint.Value>>:
  match setting:
    case Some{RuleOn{severity, options}}:
      options
    case _:
      []

def About.on(
  abouts: List<&2, About>,
  +settings: List<&2, Names.Named<Setting>>,
  out: List<&2, About>
) -> List<&2, About>:
  match abouts:
    case Nil{}:
      List.reverse(&2, About, out)
    case Con{About{+id, needs, options, every}, rest}:
      About.on(
        rest,
        settings,
        Lists.push(
          About,
          Lists.when(
            About,
            Setting.on(Names.lookup(Setting, id, settings)),
            About{id, needs, options, every}
          ),
          out
        )
      )

def Rule.keep.if(on: Bool, rule: Lint.Rule, out: List<&1, Lint.Rule>) -> List<&1, Lint.Rule>:
  match on:
    case True{}:
      rule <> out
    case False{}:
      out

def Rule.on(
  rules: List<&1, Lint.Rule>,
  +settings: List<&2, Names.Named<Setting>>,
  out: List<&1, Lint.Rule>
) -> List<&1, Lint.Rule>:
  match rules:
    case Nil{}:
      List.reverse(&1, Lint.Rule, out)
    case Con{Lint.Rule{+id, needs, options, run}, rest}:
      Rule.on(
        rest,
        settings,
        Rule.keep.if(
          Setting.on(Names.lookup(Setting, id, settings)),
          Lint.Rule{id, needs, options, run},
          out
        )
      )

def About.ids(abouts: List<&2, About>, out: List<&2, String>) -> List<&2, String>:
  match abouts:
    case Nil{}:
      List.reverse(&2, String, out)
    case Con{About{id, needs, options, every}, rest}:
      About.ids(rest, id <> out)

# The settings, with each rule that needs facts turned off if the check is `broken`: it gives no facts.
def About.unchecked(
  broken: Bool,
  abouts: List<&2, About>,
  settings: List<&2, Names.Named<Setting>>
) -> List<&2, Names.Named<Setting>>:
  match broken abouts:
    case True{} Con{About{id, Lint.Needs{facts, declarations}, options, every}, rest}:
      About.unchecked(
        True{},
        rest,
        Lists.push(
          Names.Named<Setting>,
          Lists.when(Names.Named<Setting>, facts, Names.Named{id, RuleOff{}}),
          settings
        )
      )
    case _ _:
      settings

def About.modes(
  abouts: List<&2, About>,
  out: List<&2, Names.Named<Bool>>
) -> List<&2, Names.Named<Bool>>:
  match abouts:
    case Nil{}:
      out
    case Con{About{id, needs, options, every}, rest}:
      About.modes(rest, Names.Named{id, Maybe.default(&2, Bool, every, False{})} <> out)

# Options
# =======
def Spec.one(spec: Lint.Spec, value: Lint.Value) -> Bool:
  match spec value:
    case Lint.NumberOption{min, max} Lint.Num{+n}:
      U32.is_le(min, n) && U32.is_le(n, max)
    case Lint.FlagOption{} Lint.Flag{on}:
      True{}
    case Lint.TextOption{Nil{}} Lint.Text{text}:
      True{}
    case Lint.TextOption{choices} Lint.Text{text}:
      List.contains(~String, ~String.eq, choices, text)
    case _ _:
      False{}

# Whether one of `specs` accepts `value`; `fuel` bounds AnyOptions inside AnyOptions.
def Spec.fits(fuel: Nat, specs: List<&2, Lint.Spec>, hit: Bool, +value: Lint.Value) -> Bool:
  match fuel specs hit:
    case _ _ True{}:
      True{}
    case 0n _ False{}:
      False{}
    case _ Nil{} False{}:
      False{}
    case 1n+f Con{Lint.AnyOption{inner}, rest} False{}:
      Spec.fits(f, Lists.append(&2, Lint.Spec, inner, rest), False{}, value)
    case 1n+f Con{spec, rest} False{}:
      Spec.fits(f, rest, Spec.one(spec, value), value)

def Declared.spec(
  declared: List<&2, Lint.Declared>,
  found: Maybe<&2, Lint.Spec>,
  +name: String
) -> Maybe<&2, Lint.Spec>:
  match declared found:
    case _ Some{spec}:
      Some{spec}
    case Nil{} None{}:
      None{}
    case Con{Lint.Declared{n, default, spec}, rest} None{}:
      Declared.spec(rest, Lists.when(Lint.Spec, String.eq(n, name), spec), name)

def Option.problem(spec: Maybe<&2, Lint.Spec>, key: String, value: Lint.Value) -> Maybe<&2, String>:
  match spec:
    case None{}:
      Some{"it has no option " ++ key}
    case Some{s}:
      Lists.when(
        String,
        Bool.not(Spec.fits(8n, [s], False{}, value)),
        key ++ " does not take that value"
      )

# The first problem with the given option values: a name not declared, or a value its spec does not accept.
def Option.given(
  given: List<&2, Names.Named<Lint.Value>>,
  +declared: List<&2, Lint.Declared>
) -> Maybe<&2, String>:
  match given:
    case Nil{}:
      None{}
    case Con{Names.Named{+key, value}, rest}:
      Maybe.or(
        &2,
        String,
        Option.problem(Declared.spec(declared, None{}, key), key, value),
        Option.given(rest, declared)
      )

# The first default its own spec does not accept: a bug in the rule.
def Option.defaults(declared: List<&2, Lint.Declared>) -> Maybe<&2, String>:
  match declared:
    case Nil{}:
      None{}
    case Con{Lint.Declared{name, default, spec}, rest}:
      Maybe.or(
        &2,
        String,
        Lists.when(
          String,
          Bool.not(Spec.fits(8n, [spec], False{}, default)),
          "the default of " ++ name ++ " is not a value it takes"
        ),
        Option.defaults(rest)
      )

def Option.values(
  declared: List<&2, Lint.Declared>,
  +given: List<&2, Names.Named<Lint.Value>>,
  out: List<&2, Names.Named<Lint.Value>>
) -> List<&2, Names.Named<Lint.Value>>:
  match declared:
    case Nil{}:
      List.reverse(&2, Names.Named<Lint.Value>, out)
    case Con{Lint.Declared{+name, default, spec}, rest}:
      Option.values(
        rest,
        given,
        Names.Named{
          name,
          Maybe.default(&2, Lint.Value, Names.lookup(Lint.Value, name, given), default)
        }
          <> out
      )

# The first problem with a rule's options: a default its own spec does not accept, or what the config gives.
def About.problem.of(about: About, settings: List<&2, Names.Named<Setting>>) -> Maybe<&2, String>:
  match about:
    case About{+id, needs, +options, every}:
      Maybe.map(
        &2,
        String,
        String,
        why => id ++ ": " ++ why,
        Maybe.or(
          &2,
          String,
          Option.defaults(options),
          Option.given(Setting.options(Names.lookup(Setting, id, settings)), options)
        )
      )

def About.problem(
  abouts: List<&2, About>,
  +settings: List<&2, Names.Named<Setting>>
) -> Maybe<&2, String>:
  match abouts:
    case Nil{}:
      None{}
    case Con{a, rest}:
      Maybe.or(&2, String, About.problem.of(a, settings), About.problem(rest, settings))

def About.settle.of(about: About, setting: Maybe<&2, Setting>) -> Names.Named<Setting>:
  match about setting:
    case About{id, needs, options, every} Some{RuleOff{}}:
      Names.Named{id, RuleOff{}}
    case About{id, needs, options, every} Some{RuleOn{severity, given}}:
      Names.Named{id, RuleOn{severity, Option.values(options, given, [])}}
    case About{id, needs, options, every} None{}:
      Names.Named{id, RuleOn{None{}, Option.values(options, [], [])}}

# Each rule's setting, its option values settled: off, or on with its severity, if any, and every option it declares.
def About.settle(
  abouts: List<&2, About>,
  +settings: List<&2, Names.Named<Setting>>,
  out: List<&2, Names.Named<Setting>>
) -> List<&2, Names.Named<Setting>>:
  match abouts:
    case Nil{}:
      List.reverse(&2, Names.Named<Setting>, out)
    case Con{About{+id, needs, options, every}, rest}:
      About.settle(
        rest,
        settings,
        About.settle.of(
          About{id, needs, options, every},
          Names.lookup(Setting, id, settings)
        )
          <> out
      )

# Jobs
# ====

# Where rules run: on one file, for file rules; or on the whole program of a check, for program rules, with the path
# of the named file and the check's number (from 1).
type Place is Data:
  AtFile{here: Lint.Here}
  AtProgram{whole: Lint.Whole, path: String, check: U32}

# A rule's run at one place: the rule's id, the severity the config gives its findings, the file a failure of it is
# reported in, its group (0 for a file rule, the check's number for a program rule), and how far it got.
type Job is Type:
  Job{
    rule: String,
    severity: Maybe<&2, Lint.Severity>,
    path: String,
    group: U32,
    step: Lint.Step<List<&2, Lint.Finding>>
  }

def Here.with(here: Lint.Here, options: List<&2, Names.Named<Lint.Value>>) -> Lint.Here:
  match here:
    case Lint.Here{program, source, declarations, none}:
      Lint.Here{program, source, declarations, options}

def Whole.with(whole: Lint.Whole, options: List<&2, Names.Named<Lint.Value>>) -> Lint.Whole:
  match whole:
    case Lint.Whole{program, declarations, none}:
      Lint.Whole{program, declarations, options}

def Job.start(
  +id: String,
  settings: List<&2, Names.Named<Setting>>,
  path: String,
  group: U32,
  run: Lint.Ask(List<&2, Lint.Finding>)
) -> List<&1, Job>:
  [
    Job{
      id,
      Setting.severity(Names.lookup(Setting, id, settings)),
      path,
      group,
      run(List<&2, Lint.Finding>, xs => Lint.Finished{xs})
    }
  ]

# A rule's job at `place`: none where it does not run.
def Rule.at(
  rule: Lint.Rule,
  +settings: List<&2, Names.Named<Setting>>,
  +place: Place
) -> List<&1, Job>:
  match rule place:
    case Lint.Rule{+id, needs, declared, Lint.OnFile{run}} AtFile{+here}:
      Job.start(
        id,
        settings,
        Lint.Here.path(here),
        0,
        run(Here.with(here, Setting.options(Names.lookup(Setting, id, settings))))
      )
    case Lint.Rule{+id, needs, declared, Lint.OnProgram{every, run}} AtProgram{whole, path, check}:
      Job.start(
        id,
        settings,
        path,
        check,
        run(Whole.with(whole, Setting.options(Names.lookup(Setting, id, settings))))
      )
    case _ _:
      []

def Rule.each(
  rules: List<&1, Lint.Rule>,
  +settings: List<&2, Names.Named<Setting>>,
  +place: Place,
  out: List<&1, Job>
) -> List<&1, Job>:
  match rules:
    case Nil{}:
      List.reverse(&1, Job, out)
    case Con{r, rest}:
      Rule.each(rest, settings, place, Lists.onto(&1, Job, Rule.at(r, settings, place), out))

# The jobs of the rules of both halves at `place`, in the rules' order: the halves in parallel, dealt again until
# `depth` runs out.
def Rule.all(
  +depth: Nat,
  halves: List<&1, Lint.Rule> & List<&1, Lint.Rule>,
  +settings: List<&2, Names.Named<Setting>>,
  +place: Place
) -> List<&1, Job>:
  match depth halves:
    case 0n Tuple{a, b}:
      Lists.append(&1, Job, Rule.each(a, settings, place, []), Rule.each(b, settings, place, []))
    case 1n+d Tuple{a, b}:
      x y = Rule.all(
        d,
        Lists.deal(&1, Lint.Rule, a),
        settings,
        place
      ) Rule.all(d, Lists.deal(&1, Lint.Rule, b), settings, place)
      Lists.append(&1, Job, x, y)

def Rule.jobs(
  ~rules: List<&1, Lint.Rule>,
  +settings: List<&2, Names.Named<Setting>>,
  place: Place
) -> List<&1, Job>:
  Rule.all(3n, Lists.deal(&1, Lint.Rule, Rule.on(rules, settings, [])), settings, place)

def File.each(
  ~rules: List<&1, Lint.Rule>,
  files: List<&2, Lint.Source>,
  +settings: List<&2, Names.Named<Setting>>,
  +program: Lint.Program,
  +declare: Bool,
  out: List<&1, Job>
) -> List<&1, Job>:
  match files:
    case Nil{}:
      out
    case Con{f, rest}:
      File.each(
        ~rules,
        rest,
        settings,
        program,
        declare,
        Lists.onto(
          &1,
          Job,
          Rule.jobs(~rules, settings, AtFile{Lint.Here.of(program, f, declare)}),
          out
        )
      )

# The jobs of the file rules on each file of both halves: the halves in parallel, dealt again until `depth` runs out.
# `declare` says whether a rule needs declarations.
def File.all(
  ~rules: List<&1, Lint.Rule>,
  +depth: Nat,
  halves: List<&2, Lint.Source> & List<&2, Lint.Source>,
  +settings: List<&2, Names.Named<Setting>>,
  +program: Lint.Program,
  +declare: Bool
) -> List<&1, Job>:
  match depth halves:
    case 0n Tuple{a, b}:
      Lists.append(
        &1,
        Job,
        File.each(~rules, a, settings, program, declare, []),
        File.each(~rules, b, settings, program, declare, [])
      )
    case 1n+d Tuple{a, b}:
      x y = File.all(
        ~rules,
        d,
        Lists.deal(&2, Lint.Source, a),
        settings,
        program,
        declare
      ) File.all(~rules, d, Lists.deal(&2, Lint.Source, b), settings, program, declare)
      Lists.append(&1, Job, x, y)

# The jobs of the program rules on the whole program of each check, numbered from `check`; `declare` says whether a
# rule needs declarations.
def Check.jobs(
  ~rules: List<&1, Lint.Rule>,
  programs: List<&2, Lint.Program>,
  +settings: List<&2, Names.Named<Setting>>,
  +path: String,
  +declare: Bool,
  +check: U32,
  out: List<&1, Job>
) -> List<&1, Job>:
  match programs:
    case Nil{}:
      out
    case Con{p, rest}:
      Check.jobs(
        ~rules,
        rest,
        settings,
        path,
        declare,
        (check + 1: U32),
        Lists.onto(
          &1,
          Job,
          Rule.jobs(~rules, settings, AtProgram{Lint.Whole.of(p, declare), path, check}),
          out
        )
      )

# The jobs of the program rules on each check, if one is on (`whole`): else none, and no whole program is built.
def Check.jobs.if(
  ~rules: List<&1, Lint.Rule>,
  whole: Bool,
  programs: List<&2, Lint.Program>,
  settings: List<&2, Names.Named<Setting>>,
  path: String,
  declare: Bool
) -> List<&1, Job>:
  match whole:
    case True{}:
      Check.jobs(~rules, programs, settings, path, declare, 1, [])
    case False{}:
      []

# Rounds
# ======
type Tagged is Data:
  Tagged{group: U32, found: Lint.Found}

# A job held for answers: its rule, severity, path and group, how many answers it waits for, and what it does with
# them; or settled, with its findings.
type Held is Type:
  Held{
    rule: String,
    severity: Maybe<&2, Lint.Severity>,
    path: String,
    group: U32,
    count: Nat,
    then: List<&2, Lint.Answer> -> Lint.Step<List<&2, Lint.Finding>>
  }
  Settled{
    rule: String,
    severity: Maybe<&2, Lint.Severity>,
    path: String,
    group: U32,
    findings: List<&2, Lint.Finding>
  }

type Holding is Type:
  Holding{held: List<&1, Held>, questions: List<&2, Lint.Question>}

def Round.hold(
  jobs: List<&1, Job>,
  held: List<&1, Held>,
  questions: List<&2, Lint.Question>
) -> Holding:
  match jobs:
    case Nil{}:
      Holding{List.reverse(&1, Held, held), List.reverse(&2, Lint.Question, questions)}
    case Con{Job{r, s, p, g, Lint.Finished{fs}}, rest}:
      Round.hold(rest, Settled{r, s, p, g, fs} <> held, questions)
    case Con{Job{r, s, p, g, Lint.Pending{+qs, k}}, rest}:
      Round.hold(
        rest,
        Held{r, s, p, g, Lists.length(&2, Lint.Question, qs), k} <> held,
        Lists.onto(&2, Lint.Question, qs, questions)
      )

# The held jobs, each given its answers (the next of `answers`, as many as it waits for), as jobs again.
def Round.resume(
  held: List<&1, Held>,
  +answers: List<&2, Lint.Answer>,
  out: List<&1, Job>
) -> List<&1, Job>:
  match held:
    case Nil{}:
      List.reverse(&1, Job, out)
    case Con{Held{r, s, p, g, +n, k}, rest}:
      Round.resume(
        rest,
        List.drop(&2, Lint.Answer, answers, n),
        Job{r, s, p, g, k(List.take(&2, Lint.Answer, answers, n))} <> out
      )
    case Con{Settled{r, s, p, g, fs}, rest}:
      Round.resume(rest, answers, Job{r, s, p, g, Lint.Finished{fs}} <> out)

# Each finding of `findings`, tagged with `rule`, `group`, and `severity` if the config gives the rule one, onto
# `out` (last first).
def Found.tag(
  +rule: String,
  +severity: Maybe<&2, Lint.Severity>,
  +group: U32,
  findings: List<&2, Lint.Finding>,
  out: List<&2, Tagged>
) -> List<&2, Tagged>:
  match findings:
    case Nil{}:
      out
    case Con{Lint.Finding{s, span, message, fixes}, rest}:
      Found.tag(
        rule,
        severity,
        group,
        rest,
        Tagged{
          group,
          Lint.Found{
            rule,
            Lint.Finding{Maybe.default(&2, Lint.Severity, severity, s), span, message, fixes}
          }
        }
          <> out
      )

# What the jobs found, in order: a job still waiting when the rounds ran out is a failure of its rule.
def Round.found(held: List<&1, Held>, out: List<&2, Tagged>) -> List<&2, Tagged>:
  match held:
    case Nil{}:
      List.reverse(&2, Tagged, out)
    case Con{Settled{r, s, p, g, fs}, rest}:
      Round.found(rest, Found.tag(r, s, g, fs, out))
    case Con{Held{r, s, p, g, n, k}, rest}:
      Round.found(
        rest,
        Tagged{
          g,
          Lint.Found{
            "bend-lint/rule-crash",
            Lint.Finding{
              Lint.Error{},
              Lint.Span{p, 0, 0},
              "The rule " ++ r ++ " asked the checker more rounds than its budget.",
              []
            }
          }
        }
          <> out
      )

# What the jobs find: each round asks all their questions at once, and resumes them with the answers, until none asks
# or `budget` runs out.
def Rounds.go(budget: Nat, holding: Holding) -> IO(List<&2, Tagged>):
  match budget holding:
    case _ Holding{held, Nil{}}:
      IO.pure(List<&2, Tagged>, Round.found(held, []))
    case 0n Holding{held, questions}:
      IO.pure(List<&2, Tagged>, Round.found(held, []))
    case 1n+b Holding{held, Con{q, qs}}:
      IO.bind(
        List<&2, Lint.Answer>,
        List<&2, Tagged>,
        answers(Con{q, qs}),
        answers => Rounds.go(b, Round.hold(Round.resume(held, answers, []), [], []))
      )

# Merging
# =======

# What makes a finding the same across checks: its rule, severity and span.
def Found.key(found: Lint.Found) -> String:
  match found:
    case Lint.Found{r, Lint.Finding{s, Lint.Span{p, beg, end}, m, fixes}}:
      r
        ++ "\t"
        ++ Lint.Severity.show(s)
        ++ "\t"
        ++ p
        ++ "\t"
        ++ U32.show(beg)
        ++ "\t"
        ++ U32.show(end)

def Found.keys(founds: List<&2, Lint.Found>, keys: Set()) -> Set():
  match founds:
    case Nil{}:
      keys
    case Con{f, rest}:
      Found.keys(rest, Set.add(keys, Found.key(f)))

def Found.among(keys: Set(), found: Lint.Found) -> Bool:
  Pair.snd(Set(), Bool, Set.has(keys, Found.key(found)))

def Found.keep(hit: Bool, found: Lint.Found, out: List<&2, Lint.Found>) -> List<&2, Lint.Found>:
  match hit:
    case True{}:
      found <> out
    case False{}:
      out

def Tagged.of(
  tagged: List<&2, Tagged>,
  +group: U32,
  out: List<&2, Lint.Found>
) -> List<&2, Lint.Found>:
  match tagged:
    case Nil{}:
      List.reverse(&2, Lint.Found, out)
    case Con{Tagged{g, f}, rest}:
      Tagged.of(rest, group, Found.keep(U32.is_eq(g, group), f, out))

# The findings of `more` whose keys are not among `keys`, nor before them in `more`, onto `out`.
def Merge.new(
  more: List<&2, Lint.Found>,
  +keys: Set(),
  out: List<&2, Lint.Found>
) -> List<&2, Lint.Found>:
  match more:
    case Nil{}:
      List.reverse(&2, Lint.Found, out)
    case Con{+f, rest}:
      Merge.new(
        rest,
        Set.add(keys, Found.key(f)),
        Found.keep(Bool.not(Found.among(keys, f)), f, out)
      )

def Merge.union(+founds: List<&2, Lint.Found>, more: List<&2, Lint.Found>) -> List<&2, Lint.Found>:
  Lists.append(&2, Lint.Found, founds, Merge.new(more, Found.keys(founds, Set.new()), []))

def Merge.common(
  founds: List<&2, Lint.Found>,
  +keys: Set(),
  out: List<&2, Lint.Found>
) -> List<&2, Lint.Found>:
  match founds:
    case Nil{}:
      List.reverse(&2, Lint.Found, out)
    case Con{+f, rest}:
      Merge.common(rest, keys, Found.keep(Found.among(keys, f), f, out))

def Merge.every(founds: List<&2, Lint.Found>, more: List<&2, Lint.Found>) -> List<&2, Lint.Found>:
  Merge.common(founds, Found.keys(more, Set.new()), [])

# The findings of every check, `first` with those of the checks numbered from `check` up to `last`: all of them (some),
# or those all of them find (every).
def Merge.checks(
  fuel: Nat,
  +tagged: List<&2, Tagged>,
  +check: U32,
  some: List<&2, Lint.Found>,
  every: List<&2, Lint.Found>
) -> List<&2, Lint.Found>
  & List<&2, Lint.Found>:
  match fuel:
    case 0n:
      (some, every)
    case 1n+k:
      Merge.checks(
        k,
        tagged,
        (check + 1: U32),
        Merge.union(some, Tagged.of(tagged, check, [])),
        Merge.every(every, Tagged.of(tagged, check, []))
      )

# Whether a finding of a rule stays: if the rule's findings must be found by every check (`every`), if every check
# found it (`all`), and no entry that reads the named file failed its check; else, if some check found it.
def Merge.stays(every: Maybe<&2, Bool>, partial: Bool, all: Bool) -> Bool:
  match every partial:
    case Some{True{}} True{}:
      False{}
    case Some{True{}} False{}:
      all
    case _ _:
      True{}

def Merge.pick(
  some: List<&2, Lint.Found>,
  +every: Set(),
  +modes: List<&2, Names.Named<Bool>>,
  +partial: Bool,
  out: List<&2, Lint.Found>
) -> List<&2, Lint.Found>:
  match some:
    case Nil{}:
      List.reverse(&2, Lint.Found, out)
    case Con{Lint.Found{+r, +f}, rest}:
      Merge.pick(
        rest,
        every,
        modes,
        partial,
        Found.keep(
          Merge.stays(Names.lookup(Bool, r, modes), partial, Found.among(every, Lint.Found{r, f})),
          Lint.Found{r, f},
          out
        )
      )

def Merge.done(
  merged: List<&2, Lint.Found> & List<&2, Lint.Found>,
  modes: List<&2, Names.Named<Bool>>,
  partial: Bool
) -> List<&2, Lint.Found>:
  match merged:
    case Tuple{some, every}:
      Merge.pick(some, Found.keys(every, Set.new()), modes, partial, [])

# What the program rules find over `checks` checks, merged as each rule's entries say.
def Merge.program(
  +tagged: List<&2, Tagged>,
  checks: Nat,
  modes: List<&2, Names.Named<Bool>>,
  partial: Bool
) -> List<&2, Lint.Found>:
  Merge.done(Merge.checks(checks, tagged, 1, [], Tagged.of(tagged, 1, [])), modes, partial)

# Output
# ======

# What linting the named file found: the findings that stay and those directives suppressed (both last first).
type Report is Data:
  Report{kept: List<&2, Lint.Found>, suppressed: List<&2, Lint.Found>}

# A finding with the edits of each of its fixes: None for a fix the linter cannot make.
type Resolved is Data:
  Resolved{found: Lint.Found, edits: List<&2, Maybe<&2, List<&2, Text.Edit>>>}

# A finding as the run shows it: a line of text, or a JSON object.
type Shown is Data:
  Line{text: String}
  Object{value: Json.Json}

def Found.is_error(found: Lint.Found) -> Bool:
  match found:
    case Lint.Found{rule, Lint.Finding{Lint.Error{}, span, message, fixes}}:
      True{}
    case _:
      False{}

def Found.in(
  founds: List<&2, Lint.Found>,
  +path: String,
  out: List<&2, Lint.Found>
) -> List<&2, Lint.Found>:
  match founds:
    case Nil{}:
      List.reverse(&2, Lint.Found, out)
    case Con{
      Lint.Found{rule, Lint.Finding{severity, Lint.Span{+p, beg, end}, message, fixes}},
      rest
    }:
      Found.in(
        rest,
        path,
        Found.keep(
          String.eq(p, path),
          Lint.Found{rule, Lint.Finding{severity, Lint.Span{p, beg, end}, message, fixes}},
          out
        )
      )

def Found.fixes(founds: List<&2, Lint.Found>, out: List<&2, Lint.Fix>) -> List<&2, Lint.Fix>:
  match founds:
    case Nil{}:
      List.reverse(&2, Lint.Fix, out)
    case Con{Lint.Found{rule, Lint.Finding{severity, span, message, fixes}}, rest}:
      Found.fixes(rest, Lists.onto(&2, Lint.Fix, fixes, out))

# A linted file's findings, after its directives, added to the report.
def Report.add(found: Directives.Suppressed, report: Report) -> Report:
  match found report:
    case Directives.Suppressed{kept, suppressed} Report{k, s}:
      Report{Lists.onto(&2, Lint.Found, kept, k), Lists.onto(&2, Lint.Found, suppressed, s)}

# Each linted file's findings, after `out`: those of the file rules, then those of the program rules, after its
# directives.
def report(
  linted: List<&2, Lint.Source>,
  +files: List<&2, Lint.Found>,
  +program: List<&2, Lint.Found>,
  +known: List<&2, String>,
  +ran: List<&2, String>,
  out: Report
) -> Report:
  match linted:
    case Con{Lint.Source{+path, namespace, text, nodes}, rest}:
      report(
        rest,
        files,
        program,
        known,
        ran,
        Report.add(
          Directives.apply(
            Directives.Linted{path, text, known, ran},
            Lists.append(&2, Lint.Found, Found.in(files, path, []), Found.in(program, path, []))
          ),
          out
        )
      )
    case Nil{}:
      out

# Rendering
# ---------

# Each finding with the edits of its fixes, taken in order from `edits` (empty: none resolved).
def Resolved.of(
  founds: List<&2, Lint.Found>,
  +edits: List<&2, Maybe<&2, List<&2, Text.Edit>>>,
  out: List<&2, Resolved>
) -> List<&2, Resolved>:
  match founds:
    case Nil{}:
      List.reverse(&2, Resolved, out)
    case Con{Lint.Found{rule, Lint.Finding{severity, span, message, +fixes}}, rest}:
      +n = Lists.length(&2, Lint.Fix, fixes)
      Resolved.of(
        rest,
        List.drop(&2, Maybe<&2, List<&2, Text.Edit>>, edits, n),
        Resolved{
          Lint.Found{rule, Lint.Finding{severity, span, message, fixes}},
          List.take(&2, Maybe<&2, List<&2, Text.Edit>>, edits, n)
        }
          <> out
      )

def Edit.places(edits: List<&2, Text.Edit>, out: List<&2, Text.Place>) -> List<&2, Text.Place>:
  match edits:
    case Nil{}:
      out
    case Con{Text.Edit{+path, beg, end, text}, rest}:
      Edit.places(rest, Text.Place{path, end} <> Text.Place{path, beg} <> out)

def Fix.places(
  edits: List<&2, Maybe<&2, List<&2, Text.Edit>>>,
  out: List<&2, Text.Place>
) -> List<&2, Text.Place>:
  match edits:
    case Nil{}:
      out
    case Con{Some{es}, rest}:
      Fix.places(rest, Edit.places(es, out))
    case Con{None{}, rest}:
      Fix.places(rest, out)

# The places a finding shows besides its start, onto `out`: in JSON, its end and its fixes' edits'.
def Shown.more(
  json: Bool,
  path: String,
  end: U32,
  edits: List<&2, Maybe<&2, List<&2, Text.Edit>>>,
  out: List<&2, Text.Place>
) -> List<&2, Text.Place>:
  match json:
    case False{}:
      out
    case True{}:
      Fix.places(edits, Text.Place{path, end} <> out)

def Shown.places(
  +json: Bool,
  resolved: List<&2, Resolved>,
  out: List<&2, Text.Place>
) -> List<&2, Text.Place>:
  match resolved:
    case Nil{}:
      out
    case Con{
      Resolved{
        Lint.Found{rule, Lint.Finding{severity, Lint.Span{+path, beg, end}, message, fixes}},
        edits
      },
      rest
    }:
      Shown.places(json, rest, Shown.more(json, path, end, edits, Text.Place{path, beg} <> out))

def Found.line.at(path: String, at: Text.Position, said: String) -> String:
  match at:
    case Text.Position{line, column}:
      path ++ ":" ++ U32.show(line) ++ ":" ++ U32.show(column) ++ ": " ++ said

def Found.line(found: Lint.Found, places: Map<&2, Text.Position>) -> String:
  match found:
    case Lint.Found{rule, Lint.Finding{severity, Lint.Span{+path, beg, end}, message, fixes}}:
      Found.line.at(
        path,
        Text.Place.at(places, path, beg),
        Lint.Severity.show(severity) ++ " " ++ rule ++ ": " ++ message
      )

def Object.position(at: Text.Position) -> Json.Json:
  match at:
    case Text.Position{line, column}:
      Json.JObject{
        [
          Json.JField{"line", Json.JNumber{U32.show((line - 1: U32))}},
          Json.JField{"character", Json.JNumber{U32.show((column - 1: U32))}}
        ]
      }

def Object.range(+places: Map<&2, Text.Position>, +path: String, beg: U32, end: U32) -> Json.Json:
  Json.JObject{
    [
      Json.JField{"start", Object.position(Text.Place.at(places, path, beg))},
      Json.JField{"end", Object.position(Text.Place.at(places, path, end))}
    ]
  }

def Object.edits(
  edits: List<&2, Text.Edit>,
  +places: Map<&2, Text.Position>,
  out: List<&2, Json.Json>
) -> List<&2, Json.Json>:
  match edits:
    case Nil{}:
      List.reverse(&2, Json.Json, out)
    case Con{Text.Edit{+path, beg, end, text}, rest}:
      Object.edits(
        rest,
        places,
        Json.JObject{
          [
            Json.JField{"path", Json.JString{path}},
            Json.JField{"range", Object.range(places, path, beg, end)},
            Json.JField{"text", Json.JString{text}}
          ]
        }
          <> out
      )

def Object.fix(
  safe: Bool,
  fix: Lint.Fix,
  edits: List<&2, Text.Edit>,
  places: Map<&2, Text.Position>
) -> Json.Json:
  match fix:
    case Lint.Fix{title, ops}:
      Json.JObject{
        [
          Json.JField{"title", Json.JString{title}},
          Json.JField{"applicability", Json.JString{Bool.pick(String, safe, "safe", "dangerous")}},
          Json.JField{"edits", Json.JArray{Object.edits(edits, places, [])}}
        ]
      }

# The fixes the linter can make, as JSON, onto `out`: `edits` says each one's edits.
def Object.fixes(
  fixes: List<&2, Lint.Fix>,
  edits: List<&2, Maybe<&2, List<&2, Text.Edit>>>,
  +places: Map<&2, Text.Position>,
  +comments: Set(),
  out: List<&2, Json.Json>
) -> List<&2, Json.Json>:
  match fixes edits:
    case Con{+fix, rest} Con{Some{es}, more}:
      Object.fixes(
        rest,
        more,
        places,
        comments,
        Object.fix(Fixes.Fix.safe(fix, comments), fix, es, places) <> out
      )
    case Con{fix, rest} Con{None{}, more}:
      Object.fixes(rest, more, places, comments, out)
    case _ _:
      List.reverse(&2, Json.Json, out)

# `comments` says where a safe fix may write.
def Object.finding(
  resolved: Resolved,
  +places: Map<&2, Text.Position>,
  comments: Set()
) -> Json.Json:
  match resolved:
    case Resolved{
      Lint.Found{rule, Lint.Finding{severity, Lint.Span{+path, beg, end}, message, fixes}},
      edits
    }:
      Json.JObject{
        [
          Json.JField{"code", Json.JString{rule}},
          Json.JField{"severity", Json.JString{Lint.Severity.show(severity)}},
          Json.JField{"message", Json.JString{message}},
          Json.JField{"path", Json.JString{path}},
          Json.JField{"range", Object.range(places, path, beg, end)},
          Json.JField{"fixes", Json.JArray{Object.fixes(fixes, edits, places, comments, [])}}
        ]
      }

def Shown.one(
  json: Bool,
  resolved: Resolved,
  places: Map<&2, Text.Position>,
  comments: Set()
) -> Shown:
  match json resolved:
    case False{} Resolved{found, edits}:
      Line{Found.line(found, places)}
    case True{} _:
      Object{Object.finding(resolved, places, comments)}

# The findings as the run shows them (in JSON if `json`), onto `out` (last first): `places` holds where they are, and
# `comments` where a safe fix may write.
def Shown.of(
  +json: Bool,
  resolved: List<&2, Resolved>,
  +places: Map<&2, Text.Position>,
  +comments: Set(),
  out: List<&2, Shown>
) -> List<&2, Shown>:
  match resolved:
    case Nil{}:
      out
    case Con{r, rest}:
      Shown.of(json, rest, places, comments, Shown.one(json, r, places, comments) <> out)

def Shown.text(shown: Shown) -> String:
  match shown:
    case Line{text}:
      text
    case Object{value}:
      Json.show(value)

def Shown.json(shown: Shown) -> Json.Json:
  match shown:
    case Object{value}:
      value
    case Line{text}:
      Json.JString{text}

def Shown.edits(
  json: Bool,
  founds: List<&2, Lint.Found>,
  declarations: List<&2, Lint.Declaration>,
  sources: List<&2, Lint.Source>
) -> List<&2, Maybe<&2, List<&2, Text.Edit>>>:
  match json:
    case False{}:
      []
    case True{}:
      Fixes.edits(Found.fixes(founds, []), declarations, sources)

def Shown.safety(json: Bool, founds: List<&2, Lint.Found>, sources: List<&2, Lint.Source>) -> Set():
  match json:
    case False{}:
      Set.new()
    case True{}:
      Fixes.safety(Found.fixes(founds, []), sources)

# The declarations of the program's files (`sources`), if the run needs them: to show fixes, or to make them.
def Declarations.of(need: Bool, sources: List<&2, Lint.Source>) -> List<&2, Lint.Declaration>:
  match need:
    case True{}:
      Lint.Whole.declarations(Lint.Whole.of(Lint.Program{sources}, True{}))
    case False{}:
      []

def Declarations.needed(json: Bool, fixing: Maybe<&2, Bool>) -> Bool:
  match json fixing:
    case False{} None{}:
      False{}
    case _ _:
      True{}

# Ending
# ------

# What linting named files gave: how many findings stay; those to show at the end, and those directives suppressed
# (both last first); whether a file fails the run; and how many fixes the run made.
type Outcome is Data:
  Outcome{
    count: Nat,
    findings: List<&2, Shown>,
    suppressed: List<&2, Shown>,
    failed: Bool,
    fixed: U32
  }

def Outcome.add(a: Outcome, b: Outcome) -> Outcome:
  match a b:
    case Outcome{n, f, s, e, x} Outcome{m, g, t, d, y}:
      Outcome{
        Nat.add(n, m),
        Lists.append(&2, Shown, g, f),
        Lists.append(&2, Shown, t, s),
        e || d,
        (x + y: U32)
      }

def summary.fixed(fixing: Maybe<&2, Bool>, fixed: U32) -> String:
  match fixing:
    case None{}:
      ""
    case _:
      ", " ++ U32.show(fixed) ++ " fixed"

def summary(n: Nat, suppressed: Nat, fixed: String) -> String:
  match suppressed:
    case 0n:
      "bend-lint: " ++ Nat.show(n) ++ " finding(s)" ++ fixed
    case _:
      "bend-lint: "
        ++ Nat.show(n)
        ++ " finding(s), "
        ++ Nat.show(suppressed)
        ++ " suppressed"
        ++ fixed

def say(lines: List<&2, String>) -> IO(Unit):
  match lines:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{h, t}:
      IO.print(String.join(h <> t, "\n"))

def Shown.texts(shown: List<&2, Shown>, out: List<&2, String>) -> List<&2, String>:
  match shown:
    case Nil{}:
      out
    case Con{s, rest}:
      Shown.texts(rest, Shown.text(s) <> out)

def Shown.values(shown: List<&2, Shown>, out: List<&2, Json.Json>) -> List<&2, Json.Json>:
  match shown:
    case Nil{}:
      out
    case Con{s, rest}:
      Shown.values(rest, Shown.json(s) <> out)

# The lines of the findings directives suppressed (last first), if the run shows them and there are some.
def suppressed.lines(show: Bool, shown: List<&2, Shown>) -> List<&2, String>:
  match show shown:
    case True{} Con{s, ss}:
      "bend-lint: suppressed" <> Shown.texts(Con{s, ss}, [])
    case _ _:
      []

def end.json(failed: Bool, summary: String) -> IO(Unit):
  match failed:
    case True{}:
      IO.die(Unit, 1, "bend-lint: FAIL")
    case False{}:
      IO.print_err(summary)

def end(json: Bool, total: Outcome, show: Bool, fixing: Maybe<&2, Bool>) -> IO(Unit):
  match json total:
    case False{} Outcome{n, f, s, True{}, x}:
      do IO<Unit>:
        say(suppressed.lines(show, s))
        IO.die(Unit, 1, "bend-lint: FAIL")
    case False{} Outcome{n, f, +s, False{}, x}:
      do IO<Unit>:
        say(suppressed.lines(show, s))
        IO.print(summary(n, Lists.length(&2, Shown, s), summary.fixed(fixing, x)))
    case True{} Outcome{n, f, +s, +failed, x}:
      do IO<Unit>:
        IO.print(
          Json.show(
            Json.JObject{
              [
                Json.JField{"ok", Bool.pick(Json.Json, failed, Json.JFalse{}, Json.JTrue{})},
                Json.JField{"findings", Json.JArray{Shown.values(f, [])}},
                Json.JField{"suppressed", Json.JArray{Shown.values(s, [])}}
              ]
            }
          )
        )
        end.json(failed, summary(n, Lists.length(&2, Shown, s), summary.fixed(fixing, x)))

# An outcome as a worker gives it: its count, fixes and failure, then its findings and those directives suppressed
# (first first; a line as a JSON string, an object as itself).
def Outcome.json(total: Outcome) -> Json.Json:
  match total:
    case Outcome{n, f, s, failed, x}:
      Json.JArray{
        [
          Json.JNumber{Nat.show(n)},
          Json.JNumber{U32.show(x)},
          Bool.pick(Json.Json, failed, Json.JTrue{}, Json.JFalse{}),
          Json.JArray{Shown.values(f, [])},
          Json.JArray{Shown.values(s, [])}
        ]
      }

def Shown.back(items: List<&2, Json.Json>, out: List<&2, Shown>) -> List<&2, Shown>:
  match items:
    case Nil{}:
      out
    case Con{Json.JString{text}, rest}:
      Shown.back(rest, Line{text} <> out)
    case Con{value, rest}:
      Shown.back(rest, Object{value} <> out)

def Outcome.of(
  failed: Bool,
  n: Maybe<&2, U32>,
  x: Maybe<&2, U32>,
  f: List<&2, Json.Json>,
  s: List<&2, Json.Json>
) -> Maybe<&2, Outcome>:
  match n x:
    case Some{n} Some{x}:
      Some{Outcome{U32.to_nat(n), Shown.back(f, []), Shown.back(s, []), failed, x}}
    case _ _:
      None{}

# The outcome a worker gave (see Outcome.json), if `answer` is one.
def Outcome.read(answer: Maybe<&2, Json.Json>) -> Maybe<&2, Outcome>:
  match answer:
    case Some{
      Json.JArray{
        Con{
          Json.JNumber{n},
          Con{Json.JNumber{x}, Con{Json.JTrue{}, Con{Json.JArray{f}, Con{Json.JArray{s}, Nil{}}}}}
        }
      }
    }:
      Outcome.of(True{}, U32.read(n), U32.read(x), f, s)
    case Some{
      Json.JArray{
        Con{
          Json.JNumber{n},
          Con{Json.JNumber{x}, Con{Json.JFalse{}, Con{Json.JArray{f}, Con{Json.JArray{s}, Nil{}}}}}
        }
      }
    }:
      Outcome.of(False{}, U32.read(n), U32.read(x), f, s)
    case _:
      None{}

# The findings to keep for the end of the run: in JSON, all of them; in text, none, as they are printed already.
def Shown.kept(json: Bool, shown: List<&2, Shown>) -> List<&2, Shown>:
  match json:
    case False{}:
      []
    case True{}:
      shown

# The lines the run prints for a named file as it goes: in text, its findings; in JSON, none.
def Shown.printed(json: Bool, shown: List<&2, Shown>) -> List<&2, String>:
  match json:
    case False{}:
      List.reverse(&2, String, Shown.texts(shown, []))
    case True{}:
      []

# Prints the report in text, then makes the fixes `fixing` allows in `program`'s files: what linting the named file
# gave. It fails if a finding that stays is an error.
def outcome(
  report: Report,
  +json: Bool,
  +fixing: Maybe<&2, Bool>,
  program: Lint.Program
) -> IO(Outcome):
  match report program:
    case Report{kept, suppressed} Lint.Program{+sources}:
      +founds = List.reverse(&2, Lint.Found, kept)
      +all = Lists.append(&2, Lint.Found, founds, List.reverse(&2, Lint.Found, suppressed))
      +declarations = Declarations.of(Declarations.needed(json, fixing), sources)
      +resolved = Resolved.of(all, Shown.edits(json, all, declarations, sources), [])
      +n = Lists.length(&2, Lint.Found, founds)
      +shown = List.reverse(
        &2,
        Shown,
        Shown.of(
          json,
          resolved,
          Text.places(Fixes.texts(sources, Map.new(&2, String)), Shown.places(json, resolved, [])),
          Shown.safety(json, all, sources),
          []
        )
      )
      do IO<Outcome>:
        say(Shown.printed(json, List.take(&2, Shown, shown, n)))
        fixed: U32 <- Fixes.apply(fixing, founds, declarations, sources)
        return Outcome{
          n,
          List.reverse(&2, Shown, Shown.kept(json, List.take(&2, Shown, shown, n))),
          List.reverse(&2, Shown, List.drop(&2, Shown, shown, n)),
          Lists.any(~Lint.Found, ~Found.is_error, founds),
          fixed
        }

# CLI
# ===

# How many rounds of questions a run may ask: past it, a rule still asking fails.
def budget() -> Nat:
  64n

# Prints what the jobs found in the linted files, and makes the fixes; `checks` is the number of checks.
def finish(
  linted: List<&2, Lint.Source>,
  +tagged: List<&2, Tagged>,
  checks: Nat,
  modes: List<&2, Names.Named<Bool>>,
  partial: Bool,
  known: List<&2, String>,
  ran: List<&2, String>,
  json: Bool,
  fixing: Maybe<&2, Bool>,
  program: Lint.Program
) -> IO(Outcome):
  outcome(
    report(
      linted,
      Tagged.of(tagged, 0, []),
      Merge.program(tagged, checks, modes, partial),
      known,
      ran,
      Report{[], []}
    ),
    json,
    fixing,
    program
  )

# Gives `outcome` once the server frees the checks numbered `checks`.
def forgotten(checks: List<&2, U32>, outcome: Outcome) -> IO(Outcome):
  match checks:
    case Nil{}:
      IO.pure(Outcome, outcome)
    case Con{c, rest}:
      IO.bind(Unit, Outcome, Check.forget(c), done => forgotten(rest, outcome))

# Lints `linted`, files of the first of `programs` (the checks of the named file, at `path`), with the rules the
# config leaves on. Program rules run on each check; `partial` says whether an entry that reads the named file failed
# its check.
def lint(
  ~rules: List<&1, Lint.Rule>,
  +linted: List<&2, Lint.Source>,
  path: String,
  +programs: List<&2, Lint.Program>,
  partial: Bool,
  +settings: List<&2, Names.Named<Setting>>,
  json: Bool,
  fixing: Maybe<&2, Bool>
) -> IO(Outcome):
  +abouts = About.all(rules, [])
  +on = About.on(abouts, settings, [])
  +declare = Lists.any(~About, ~About.declarations, on)
  IO.bind(
    List<&2, Tagged>,
    Outcome,
    Rounds.go(
      budget(),
      Round.hold(
        Lists.append(
          &1,
          Job,
          File.all(
            ~rules,
            3n,
            Lists.deal(&2, Lint.Source, linted),
            settings,
            Maybe.default(
              &2,
              Lint.Program,
              List.head(&2, Lint.Program, programs),
              Lint.Program{[]}
            ),
            declare
          ),
          Check.jobs.if(
            ~rules,
            Lists.any(~About, ~About.whole, on),
            programs,
            settings,
            path,
            declare
          )
        ),
        [],
        []
      )
    ),
    tagged => finish(
      linted,
      tagged,
      Lists.length(&2, Lint.Program, programs),
      About.modes(abouts, []),
      partial,
      About.ids(abouts, []),
      About.ids(on, []),
      json,
      fixing,
      Maybe.default(&2, Lint.Program, List.head(&2, Lint.Program, programs), Lint.Program{[]})
    )
  )

def Source.at(
  sources: List<&2, Lint.Source>,
  found: Maybe<&2, Lint.Source>,
  +path: String
) -> Maybe<&2, Lint.Source>:
  match sources found:
    case _ Some{source}:
      Some{source}
    case Nil{} None{}:
      None{}
    case Con{Lint.Source{+p, namespace, text, nodes}, rest} None{}:
      Source.at(
        rest,
        Lists.when(Lint.Source, String.eq(p, path), Lint.Source{p, namespace, text, nodes}),
        path
      )

# Whether to lint the files the named file imports: as the command line says, else as the config says, else not.
def imports(flag: Maybe<&2, Bool>, project: Maybe<&2, Bool>) -> Bool:
  Maybe.default(&2, Bool, Maybe.or(&2, Bool, flag, project), False{})

# The checks of the named file: the programs to lint it in (the first one's file rules run); the entries that read it
# and failed their check; whether its own check failed (then the program is what it parsed, if it parsed the files);
# and the checks to free after it.
type Checks is Data:
  Checks{
    programs: List<&2, Lint.Program>,
    failing: List<&2, String>,
    failed: Bool,
    forget: List<&2, U32>
  }

# The files to lint: the named file (at `path`), or, with `imports`, every own file of its check.
def linted(imports: Bool, path: String, sources: List<&2, Lint.Source>) -> List<&2, Lint.Source>:
  match imports:
    case True{}:
      Lint.Program.own(sources)
    case False{}:
      Maybe.default(
        &2,
        List<&2, Lint.Source>,
        Maybe.map(
          &2,
          Lint.Source,
          List<&2, Lint.Source>,
          s => [s],
          Source.at(sources, None{}, path)
        ),
        []
      )

# Says, if the named file's check failed and a rule on needs its facts, that those rules did not run.
def unchecked(failed: Bool, needs: Bool, path: String) -> IO(Unit):
  match failed needs:
    case True{} True{}:
      IO.print_err(
        "bend-lint: Bend's check of "
          ++ path
          ++ " fails, so the rules that need its facts did not run; `bend <file> --check-only` says why"
      )
    case _ _:
      IO.pure(Unit, Unit{})

# Says, for each entry of `failing` that reads the named file and failed its check, that the file was linted without
# it. If the file's own check failed too (`failed`), `unchecked` says so instead.
def unentered(failed: Bool, failing: List<&2, String>, +path: String) -> IO(Unit):
  match failed failing:
    case False{} Con{entry, rest}:
      do IO<Unit>:
        IO.print_err(
          "bend-lint: Bend's check of the entry "
            ++ entry
            ++ " fails, so "
            ++ path
            ++ " was linted without it; `bend <file> --check-only` says why"
        )
        unentered(False{}, rest, path)
    case _ _:
      IO.pure(Unit, Unit{})

def checked(
  ~rules: List<&1, Lint.Rule>,
  +path: String,
  imports: Bool,
  +settings: List<&2, Names.Named<Setting>>,
  json: Bool,
  fixing: Maybe<&2, Bool>,
  checks: Checks
) -> IO(Outcome):
  match checks:
    case Checks{Con{Lint.Program{+sources}, rest}, +failing, +failed, forget}:
      do IO<Outcome>:
        unchecked(
          failed,
          Lists.any(~About, ~About.facts, About.on(About.all(rules, []), settings, [])),
          path
        )
        unentered(failed, failing, path)
        o: Outcome <- lint(
          ~rules,
          linted(imports, path, sources),
          path,
          Lint.Program{sources} <> rest,
          Bool.not(List.is_empty(&2, String, failing)),
          About.unchecked(failed, About.all(rules, []), settings),
          json,
          fixing
        )
        forgotten(forget, o)
    case Checks{Nil{}, failing, failed, forget}:
      do IO<Outcome>:
        IO.print_err(
          "bend-lint: Bend does not load "
            ++ path
            ++ ", so no rule ran on it; `bend <file> --check-only` says why"
        )
        return Outcome{0n, [], [], False{}, 0}

# The named file's own check, as the checks to lint it in, after the entries that read it and failed (`failing`). If
# it fails, the rules that need no facts run on what it parsed, if it parsed the files.
def Check.own(failing: List<&2, String>, check: Check) -> Checks:
  match check:
    case Passed{p, c}:
      Checks{[p], failing, False{}, [c]}
    case Failed{read, parsed}:
      Checks{
        Maybe.default(
          &2,
          List<&2, Lint.Program>,
          Maybe.map(&2, Lint.Program, List<&2, Lint.Program>, p => [p], parsed),
          []
        ),
        failing,
        True{},
        []
      }

def Check.reads(path: String, +check: Check) -> Bool:
  match check:
    case Passed{Lint.Program{sources}, c}:
      Maybe.is_some(&2, Lint.Source, Source.at(sources, None{}, path))
    case Failed{read, parsed}:
      List.contains(~String, ~String.eq, read, path)

# The check of `entry` sorted into `checks`: if it reads the named file, its program joins the programs (and the checks
# to free), or, if it failed, the entry joins the failing ones.
def Check.sort.step(reads: Bool, entry: String, check: Check, checks: Checks) -> Checks:
  match reads check checks:
    case True{} Passed{p, c} Checks{programs, failing, failed, forget}:
      Checks{p <> programs, failing, failed, c <> forget}
    case True{} Failed{read, parsed} Checks{programs, failing, failed, forget}:
      Checks{programs, entry <> failing, failed, forget}
    case False{} _ _:
      checks

# The checks of `entries` (in order) that read the named file (at `path`): the programs of those that passed, and the
# entries of those that failed.
def Check.sort(
  checks: List<&2, Check>,
  entries: List<&2, String>,
  +path: String,
  sorted: Checks
) -> Checks:
  match checks entries sorted:
    case Con{+c, rest} Con{e, more} _:
      Check.sort(rest, more, path, Check.sort.step(Check.reads(path, c), e, c, sorted))
    case _ _ Checks{programs, failing, failed, forget}:
      Checks{
        List.reverse(&2, Lint.Program, programs),
        List.reverse(&2, String, failing),
        failed,
        forget
      }

# The checks of `entries`, with the facts of the file at `path`, if `facts`.
def Check.all(
  entries: List<&2, String>,
  +facts: Bool,
  +path: String,
  out: List<&2, Check>
) -> IO(List<&2, Check>):
  match entries:
    case Nil{}:
      IO.pure(List<&2, Check>, List.reverse(&2, Check, out))
    case Con{e, rest}:
      IO.bind(
        Check,
        List<&2, Check>,
        Check.file(e, facts, [path]),
        c => Check.all(rest, facts, path, c <> out)
      )

# The checks to lint the named file in: those of the entries that read it and passed; if none, its own.
def Check.chosen(sorted: Checks, +path: String, facts: Bool) -> IO(Checks):
  match sorted:
    case Checks{Nil{}, failing, failed, forget}:
      IO.bind(
        Check,
        Checks,
        Check.file(path, facts, [path]),
        c => IO.pure(Checks, Check.own(failing, c))
      )
    case _:
      IO.pure(Checks, sorted)

# The checks to lint the named file (at `path`) in: with `imports` or no entries, its own; else those `Check.chosen`
# picks. A check gives the facts of the files it lints: the named one, or, with `imports`, each.
def Check.of(imports: Bool, entries: List<&2, String>, +path: String, +facts: Bool) -> IO(Checks):
  match imports entries:
    case False{} Con{+e, +es}:
      IO.bind(
        List<&2, Check>,
        Checks,
        Check.all(Con{e, es}, facts, path, []),
        checks => Check.chosen(
          Check.sort(checks, Con{e, es}, path, Checks{[], [], False{}, []}),
          path,
          facts
        )
      )
    case True{} _:
      IO.bind(Check, Checks, Check.file(path, facts, []), c => IO.pure(Checks, Check.own([], c)))
    case False{} Nil{}:
      IO.bind(
        Check,
        Checks,
        Check.file(path, facts, [path]),
        c => IO.pure(Checks, Check.own([], c))
      )

def Options.checked(problem: Maybe<&2, String>) -> IO(Unit):
  match problem:
    case Some{why}:
      IO.die(Unit, 2, "bend-lint config: " ++ why)
    case None{}:
      IO.pure(Unit, Unit{})

# What the command line asks: `worker` says whether this run lints its file for another run (see Workers).
type Options is Data:
  Options{
    inputs: List<&2, String>,
    imports: Maybe<&2, Bool>,
    fixing: Maybe<&2, Bool>,
    shown: Bool,
    json: Bool,
    worker: Bool
  }

# Stops the run if it lints the imports of more than one file: a run with imports has one root.
def Options.single(imports: Bool, many: Bool) -> IO(Unit):
  match imports many:
    case True{} True{}:
      IO.die(Unit, 2, "bend-lint: --imports takes one file to lint, also from the config")
    case _ _:
      IO.pure(Unit, Unit{})

def settled(
  ~rules: List<&1, Lint.Rule>,
  +path: String,
  +imports: Bool,
  json: Bool,
  fixing: Maybe<&2, Bool>,
  entries: List<&2, String>,
  +settings: List<&2, Names.Named<Setting>>
) -> IO(Outcome):
  IO.bind(
    Checks,
    Outcome,
    Check.of(
      imports,
      entries,
      path,
      Lists.any(~About, ~About.facts, About.on(About.all(rules, []), settings, []))
    ),
    checks => checked(~rules, path, imports, settings, json, fixing, checks)
  )

# Lints the file at `path` as its config says: `many` says whether the run lints more than one file.
def configured(
  ~rules: List<&1, Lint.Rule>,
  path: String,
  +options: Options,
  many: Bool,
  project: Project
) -> IO(Outcome):
  match options project:
    case Options{inputs, flag, fixing, shown, json, worker} Project{entries, from, +settings}:
      +on = imports(flag, from)
      do IO<Outcome>:
        Options.checked(About.problem(About.all(rules, []), settings))
        Options.single(on, many)
        settled(
          ~rules,
          path,
          on,
          json,
          fixing,
          entries,
          About.settle(About.all(rules, []), settings, [])
        )

type Flag is Data:
  ImportsFlag{on: Bool}
  FixFlag{fixing: Maybe<&2, Bool>}
  ShownFlag{}
  JsonFlag{}
  WorkerFlag{}

def flags() -> List<&2, Names.Named<Flag>>:
  [
    Names.Named{"--imports", ImportsFlag{True{}}},
    Names.Named{"--no-imports", ImportsFlag{False{}}},
    Names.Named{"--fix", FixFlag{Some{False{}}}},
    Names.Named{"--fix-dangerously", FixFlag{Some{True{}}}},
    Names.Named{"--show-suppressed", ShownFlag{}},
    Names.Named{"--json", JsonFlag{}},
    Names.Named{"--worker", WorkerFlag{}}
  ]

def Options.set(flag: Maybe<&2, Flag>, options: Maybe<&2, Options>) -> Maybe<&2, Options>:
  match flag options:
    case Some{ImportsFlag{on}} Some{Options{inputs, imports, fixing, shown, json, worker}}:
      Some{Options{inputs, Some{on}, fixing, shown, json, worker}}
    case Some{FixFlag{set}} Some{Options{inputs, imports, fixing, shown, json, worker}}:
      Some{Options{inputs, imports, set, shown, json, worker}}
    case Some{ShownFlag{}} Some{Options{inputs, imports, fixing, shown, json, worker}}:
      Some{Options{inputs, imports, fixing, True{}, json, worker}}
    case Some{JsonFlag{}} Some{Options{inputs, imports, fixing, shown, json, worker}}:
      Some{Options{inputs, imports, fixing, shown, True{}, worker}}
    case Some{WorkerFlag{}} Some{Options{inputs, imports, fixing, shown, json, worker}}:
      Some{Options{inputs, imports, fixing, shown, json, True{}}}
    case _ _:
      None{}

def Options.input(input: String, options: Maybe<&2, Options>) -> Maybe<&2, Options>:
  match options:
    case Some{Options{inputs, imports, fixing, shown, json, worker}}:
      Some{Options{input <> inputs, imports, fixing, shown, json, worker}}
    case None{}:
      None{}

def Options.arg(flag: Bool, arg: String, options: Maybe<&2, Options>) -> Maybe<&2, Options>:
  match flag:
    case True{}:
      Options.set(Names.lookup(Flag, arg, flags()), options)
    case False{}:
      Options.input(arg, options)

# The options, once every argument is read: the files in order; none if there are none.
def Options.done(options: Maybe<&2, Options>) -> Maybe<&2, Options>:
  match options:
    case Some{Options{Con{first, more}, imports, fixing, shown, json, worker}}:
      Some{
        Options{List.reverse(&2, String, Con{first, more}), imports, fixing, shown, json, worker}
      }
    case _:
      None{}

def Options.read(args: List<String>, options: Maybe<&2, Options>) -> Maybe<&2, Options>:
  match args:
    case Nil{}:
      Options.done(options)
    case Con{+a, rest}:
      Options.read(rest, Options.arg(String.starts_with(a, "--"), a, options))

def File.lint(
  ~rules: List<&1, Lint.Rule>,
  +path: String,
  options: Options,
  many: Bool
) -> IO(Outcome):
  IO.bind(
    Project,
    Outcome,
    Config.find(path),
    project => configured(~rules, path, options, many, project)
  )

# Ends a run that linted its files here: a worker gives its outcome to the run it lints for, as a line of JSON (see
# Workers); another run shows it.
def ended(options: Options, total: Outcome) -> IO(Unit):
  match options:
    case Options{inputs, imports, fixing, shown, json, True{}}:
      IO.print(Json.show(Outcome.json(total)))
    case Options{inputs, imports, fixing, shown, json, False{}}:
      end(json, total, shown, fixing)

def Paths.lint(
  ~rules: List<&1, Lint.Rule>,
  paths: List<&2, String>,
  +options: Options,
  +many: Bool,
  total: Outcome
) -> IO(Unit):
  match paths:
    case Nil{}:
      ended(options, total)
    case Con{path, rest}:
      IO.bind(
        Outcome,
        Unit,
        File.lint(~rules, path, options, many),
        o => Paths.lint(~rules, rest, options, many, Outcome.add(total, o))
      )

def files.of(found: Result<&2, &2, String, List<&2, String>>) -> IO(List<&2, String>):
  match found:
    case Done{paths}:
      IO.pure(List<&2, String>, paths)
    case Fail{why}:
      IO.die(List<&2, String>, 2, "bend-lint: " ++ why)

# The files the inputs name. One that names none ends the run with a usage error.
def files(inputs: List<&2, String>) -> IO(List<&2, String>):
  IO.bind(
    Result<&2, &2, String, List<&2, String>>,
    List<&2, String>,
    Files.named(inputs),
    found => files.of(found)
  )

# Workers
# -------

# A run of several files that fixes none lints each in a worker: this program again, on that file alone
# (`--worker`), with a heap of its own. As many workers run at once as half the threads, two threads each, and the run
# shows what each found in the order of the files. A run that fixes lints its files here, one after another, as a fix
# changes what the files after it read; so does a build to JavaScript, which runs one process at a time.
#
# A heap of its own matters as much as the threads. Bend's runtime gives back freed cells last freed first, so after a
# big check is freed, the cells of the next ones scatter over the heap, and each costs a cache miss: in one process, a
# check late in a run of this repo cost 3 to 6 times as much per byte of its answer as the first.

# What running a worker gives: its exit status, with its stdout and stderr; or why it did not run.
def Ran() -> Type:
  Result<&1, &1, U32 & String, U32 & (String & String)>

# A worker's stdout: what it showed, and its last line, its outcome.
type Said is Data:
  Said{shown: String, last: String}

# `reversed`, a worker's stdout last character first, from before its last newline: `line` is its last line so far.
def Said.go(reversed: String, line: String) -> Said:
  match reversed:
    case SNil{}:
      Said{"", line}
    case SCon{'\n', rest}:
      Said{String.reverse(SCon{'\n', rest}), line}
    case SCon{c, rest}:
      Said.go(rest, SCon{c, line})

# `reversed` without the newline it starts with, if it does.
def Said.end(reversed: String) -> String:
  match reversed:
    case SCon{'\n', rest}:
      rest
    case SCon{c, rest}:
      SCon{c, rest}
    case SNil{}:
      SNil{}

# A worker's stderr, as a message: without its last newline.
def Said.message(err: String) -> String:
  String.reverse(Said.end(String.reverse(err)))

def Worker.answer(outcome: Maybe<&2, Outcome>) -> IO(Outcome):
  match outcome:
    case Some{o}:
      IO.pure(Outcome, o)
    case None{}:
      IO.die(Outcome, 1, "bend-lint: a worker's answer is malformed")

def Worker.errors(err: String) -> IO(Unit):
  match err:
    case SNil{}:
      IO.pure(Unit, Unit{})
    case SCon{c, rest}:
      IO.print_err(Said.message(SCon{c, rest}))

def Worker.said(said: Said, err: String) -> IO(Outcome):
  match said:
    case Said{shown, last}:
      do IO<Outcome>:
        IO.write(shown)
        Worker.errors(err)
        Worker.answer(Outcome.read(Json.read(last)))

# Why a worker stopped with `status`: what it said, or its status if it said nothing.
def Worker.why(status: U32, err: String) -> String:
  match err:
    case SNil{}:
      "bend-lint: a worker stopped with status " ++ U32.show(status)
    case SCon{c, rest}:
      Said.message(SCon{c, rest})

def Worker.stopped(ok: Bool, +status: U32, out: String, err: String) -> IO(Outcome):
  match ok:
    case True{}:
      Worker.said(Said.go(Said.end(String.reverse(out)), ""), err)
    case False{}:
      do IO<Outcome>:
        IO.write(out)
        IO.die(Outcome, status, Worker.why(status, err))

# What a worker found: the run shows what it showed and takes its outcome. One that stopped ends the run as it would
# have ended it.
def Worker.outcome(ran: Ran()) -> IO(Outcome):
  match ran:
    case Done{(+status, (out, err))}:
      Worker.stopped(U32.is_eq(status, 0), status, out, err)
    case Fail{(code, why)}:
      IO.die(Outcome, 1, "bend-lint: a worker did not run: " ++ why)

def Worker.imports(imports: Maybe<&2, Bool>) -> List<String>:
  match imports:
    case Some{True{}}:
      ["--imports"]
    case Some{False{}}:
      ["--no-imports"]
    case None{}:
      []

def Worker.flag(on: Bool, flag: String) -> List<String>:
  match on:
    case True{}:
      [flag]
    case False{}:
      []

# The command line of the worker of the file at `path`: two threads, then the flags of this run that it reads.
def Worker.args(options: Options, path: String) -> List<String>:
  match options:
    case Options{inputs, imports, fixing, shown, json, worker}:
      "--threads"
        <> "2"
        <> "--worker"
        <> List.append(
          &1,
          String,
          Worker.imports(imports),
          List.append(
            &1,
            String,
            Worker.flag(shown, "--show-suppressed"),
            List.append(&1, String, Worker.flag(json, "--json"), [path])
          )
        )

# Runs a worker once one of `slots` is free, then frees it.
def Worker.run(+slots: Chan(Unit), program: String, args: List<String>) -> IO(Ran()):
  do IO<Ran()>:
    slot: Maybe<&1, Unit> <- Chan.recv(Unit, slots)
    ran: Ran() <- Process.run(program, args, "", 4294967295, 4294967295)
    freed: Result<&1, &1, Unit, Unit> <- Chan.send(Unit, slots, Unit{})
    return ran

# Starts the workers of `paths`, after those of `out` (last first).
def Workers.start(
  +slots: Chan(Unit),
  +program: String,
  +options: Options,
  paths: List<&2, String>,
  out: List<&2, Chan(Ran())>
) -> IO(List<&2, Chan(Ran())>):
  match paths:
    case Nil{}:
      IO.pure(List<&2, Chan(Ran())>, List.reverse(&2, Chan(Ran()), out))
    case Con{path, rest}:
      IO.bind(
        Chan(Ran()),
        List<&2, Chan(Ran())>,
        IO.fork(Ran(), Worker.run(slots, program, Worker.args(options, path))),
        c => Workers.start(slots, program, options, rest, c <> out)
      )

# What the workers found, in order, after `total`.
def Workers.collect(workers: List<&2, Chan(Ran())>, total: Outcome) -> IO(Outcome):
  match workers:
    case Nil{}:
      IO.pure(Outcome, total)
    case Con{w, rest}:
      do IO<Outcome>:
        ran: Ran() <- IO.join(Ran(), w)
        o: Outcome <- Worker.outcome(ran)
        Workers.collect(rest, Outcome.add(total, o))

def Slots.filled(+slots: Chan(Unit), n: Nat) -> IO(Chan(Unit)):
  match n:
    case 0n:
      IO.pure(Chan(Unit), slots)
    case 1n+k:
      IO.bind(
        Result<&1, &1, Unit, Unit>,
        Chan(Unit),
        Chan.send(Unit, slots, Unit{}),
        sent => Slots.filled(slots, k)
      )

# `count` slots for workers, all free.
def Slots.of(+count: U32) -> IO(Chan(Unit)):
  IO.bind(
    Chan(Unit),
    Chan(Unit),
    Chan.new(Unit, count),
    slots => Slots.filled(slots, U32.to_nat(count))
  )

# Lints `paths` in workers of `program`, as `options` say: half as many at once as the threads.
def Workers.lint(program: String, paths: List<&2, String>, +options: Options) -> IO(Unit):
  do IO<Unit>:
    threads: U32 <- IO.thread_count()
    slots: Chan(Unit) <- Slots.of(U32.max(1, U32.shr(threads)))
    workers: List<&2, Chan(Ran())> <- Workers.start(slots, program, options, paths, [])
    total: Outcome <- Workers.collect(workers, Outcome{0n, [], [], False{}, 0})
    ended(options, total)

# Whether `program`, as invoked, is a native build: one whose workers run at once.
def Workers.native(+program: String) -> Bool:
  Bool.not(
    String.ends_with(
      program,
      ".js"
    )
      || String.ends_with(program, ".mjs")
      || String.ends_with(program, ".cjs")
      || String.ends_with(program, ".bend")
  )

# Whether a run lints its files in workers: a run of several files, that fixes none, by a native build.
def Workers.wanted(program: String, paths: List<&2, String>, options: Options) -> Bool:
  match options:
    case Options{inputs, imports, None{}, shown, json, False{}}:
      Workers.native(program) && Nat.is_gt(Lists.length(&2, String, paths), 1n)
    case _:
      False{}

# Whether the run lints more than one file: a worker's does, for the run it lints for.
def Options.many(options: Options, paths: List<&2, String>) -> Bool:
  match options:
    case Options{inputs, imports, fixing, shown, json, worker}:
      worker || Nat.is_gt(Lists.length(&2, String, paths), 1n)

def Paths.go(
  ~rules: List<&1, Lint.Rule>,
  workers: Bool,
  program: String,
  +paths: List<&2, String>,
  +options: Options
) -> IO(Unit):
  match workers:
    case True{}:
      Workers.lint(program, paths, options)
    case False{}:
      Paths.lint(
        ~rules,
        paths,
        options,
        Options.many(options, paths),
        Outcome{0n, [], [], False{}, 0}
      )

# Lints `paths` as `options` say: in workers, if the run can (see Workers), else here.
def Paths.run(
  ~rules: List<&1, Lint.Rule>,
  +program: String,
  +paths: List<&2, String>,
  +options: Options
) -> IO(Unit):
  Paths.go(~rules, Workers.wanted(program, paths, options), program, paths, options)

def checking(~rules: List<&1, Lint.Rule>, program: String, options: Maybe<&2, Options>) -> IO(Unit):
  match options:
    case Some{Options{+inputs, flag, fixing, shown, json, worker}}:
      IO.bind(
        List<&2, String>,
        Unit,
        files(inputs),
        +paths => Paths.run(
          ~rules,
          program,
          paths,
          Options{inputs, flag, fixing, shown, json, worker}
        )
      )
    case None{}:
      IO.die(
        Unit,
        2,
        "usage: bend-lint [--program <rules program>] <file or glob>... [--imports | --no-imports] [--fix | --fix-dangerously] [--show-suppressed] [--json]"
      )

# Runs the command line `args`: the program as invoked, then its arguments.
def started(~rules: List<&1, Lint.Rule>, args: List<String>) -> IO(Unit):
  match args:
    case Con{program, rest}:
      checking(
        ~rules,
        program,
        Options.read(rest, Some{Options{[], None{}, None{}, False{}, False{}, False{}}})
      )
    case Nil{}:
      checking(~rules, "", None{})

def run(~rules: List<&1, Lint.Rule>) -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), args => started(~rules, args))
