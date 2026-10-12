# The seam to the checker server (server.ts), for as long as Bend's checker is TS: each request
# the linter makes, and its answer decoded. Three calls cross it: check, forget and answers.
# When the checker is Bend, this file becomes those three calls, made directly.
# - A request is one connection: one line out, the answer in, then the server closes.
# - A line is fields split by a tab. A field escapes \, a tab and a newline as \\, \t and \n.
# - The answer is one line per record. Its first field is its kind.
import Base
import ../shared/names.bend as Names
import ./lint.bend as Lint
import ./program.bend as Program

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

def mark(+c: Char) -> Mark:
  Bool.pick(
    Mark,
    Char.is_eq(c, '\\'),
    Slash{},
    Bool.pick(
      Mark,
      Char.is_eq(c, '\t'),
      Tab{},
      Bool.pick(Mark, Char.is_eq(c, '\n'), Newline{}, Plain{})
    )
  )

# A field's character with its escape undone: the character after a \.
def unescaped(+c: Char) -> Char:
  Bool.pick(Char, Char.is_eq(c, 'n'), '\n', Bool.pick(Char, Char.is_eq(c, 't'), '\t', c))

def read(mark: Mark, c: Char, r: Reading) -> Reading:
  match mark r:
    case _ Reading{True{}, field, fields, records}:
      Reading{False{}, SCon{unescaped(c), field}, fields, records}
    case Slash{} Reading{False{}, field, fields, records}:
      Reading{True{}, field, fields, records}
    case Tab{} Reading{False{}, field, fields, records}:
      Reading{False{}, "", String.reverse(field) <> fields, records}
    case Newline{} Reading{False{}, field, fields, records}:
      Reading{False{}, "", [], List.reverse(&2, String, String.reverse(field) <> fields) <> records}
    case Plain{} Reading{False{}, field, fields, records}:
      Reading{False{}, SCon{c, field}, fields, records}

def read_text(s: String, r: Reading) -> Reading:
  match s:
    case SNil{}:
      r
    case SCon{+c, t}:
      read_text(t, read(mark(c), c, r))

# The records of an answer's chunks, in order. A last record with no newline is dropped.
def records(chunks: List<&2, String>, r: Reading) -> List<&2, List<&2, String>>:
  match chunks r:
    case Nil{} Reading{escaped, field, fields, records}:
      List.reverse(&2, List<&2, String>, records)
    case Con{h, t} _:
      records(t, read_text(h, r))

# A character onto a field, escaped, onto `out`, which is last first.
def write(mark: Mark, c: Char, out: String) -> String:
  match mark:
    case Slash{}:
      SCon{'\\', SCon{'\\', out}}
    case Tab{}:
      SCon{'t', SCon{'\\', out}}
    case Newline{}:
      SCon{'n', SCon{'\\', out}}
    case Plain{}:
      SCon{c, out}

def field(s: String, out: String) -> String:
  match s:
    case SNil{}:
      out
    case SCon{+c, t}:
      field(t, write(mark(c), c, out))

# A request's line, from its fields; `out` is the line so far, last first.
def line(fields: List<&2, String>, out: String) -> String:
  match fields:
    case Nil{}:
      String.reverse(SCon{'\n', out})
    case Con{h, Nil{}}:
      String.reverse(SCon{'\n', field(h, out)})
    case Con{h, t}:
      line(t, SCon{'\t', field(h, out)})

# The chunks read until the server closes, last first, from the last read `step`. `fuel` bounds the reads.
def receive(
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
        r => receive(k, r, text <> got)
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

def sent(r: Socket & Result<&1, &1, (U32 & String) & String, Unit>) -> IO(List<&2, String>):
  match r:
    case Tuple{s, Done{u}}:
      IO.bind(
        Socket & Result<&1, &1, U32 & String, Maybe<&1, String>>,
        List<&2, String>,
        TCP.recv(s, 65536),
        step => receive(4294967295n, step, [])
      )
    case Tuple{s, Fail{Tuple{Tuple{code, why}, rest}}}:
      do IO<List<&2, String>>:
        Socket.close(s)
        IO.die(List<&2, String>, 1, "bend-lint: asking the checker failed: " ++ why)

def port.of(port: Maybe<&2, U32>) -> IO(U32):
  match port:
    case Some{p}:
      IO.pure(U32, p)
    case None{}:
      IO.die(
        U32,
        2,
        "bend-lint: BEND_LINT_PORT is not a port; run this program with `bend-lint --program <it>`"
      )

def port() -> IO(U32):
  do IO<U32>:
    text: String <- IO.try(String, IO.get_env("BEND_LINT_PORT"))
    port.of(U32.read(text))

def ask(request: List<&2, String>) -> IO(List<&2, List<&2, String>>):
  do IO<List<&2, List<&2, String>>>:
    p: U32 <- port()
    sock: Socket <- IO.try(Socket, TCP.connect("127.0.0.1", p))
    s: Socket & Result<&1, &1, (U32 & String) & String, Unit> <- TCP.send(sock, line(request, ""))
    got: List<&2, String> <- sent(s)
    return records(List.reverse(&2, String, got), Reading{False{}, "", [], []})

# Checks
# ======
def Syntax.names() -> List<&2, Names.Named<Lint.Syntax>>:
  [
    Names.Named{"Variable", Lint.Variable{}},
    Names.Named{"Reference", Lint.Reference{}},
    Names.Named{"Application", Lint.Application{}},
    Names.Named{"Lambda", Lint.Lambda{}},
    Names.Named{"Literal", Lint.Literal{}},
    Names.Named{"Construction", Lint.Construction{}},
    Names.Named{"PatternVariable", Lint.PatternVariable{}},
    Names.Named{"PatternConstructor", Lint.PatternConstructor{}},
    Names.Named{"Forall", Lint.Forall{}},
    Names.Named{"Annotation", Lint.Annotation{}},
    Names.Named{"Match", Lint.Match{}},
    Names.Named{"Case", Lint.Case{}},
    Names.Named{"Destructure", Lint.Destructure{}},
    Names.Named{"Let", Lint.Let{}},
    Names.Named{"Binding", Lint.Binding{}},
    Names.Named{"Parameter", Lint.Parameter{}},
    Names.Named{"Field", Lint.Field{}},
    Names.Named{"Returns", Lint.Returns{}},
    Names.Named{"Body", Lint.Body{}},
    Names.Named{"Definition", Lint.Definition{}},
    Names.Named{"Datatype", Lint.Datatype{}},
    Names.Named{"Constructor", Lint.Constructor{}},
    Names.Named{"Law", Lint.Law{}},
    Names.Named{"Import", Lint.Import{}},
    Names.Named{"ImportPath", Lint.ImportPath{}},
    Names.Named{"Substitution", Lint.Substitution{}},
    Names.Named{"Sort", Lint.Sort{}},
    Names.Named{"QuantityType", Lint.QuantityType{}},
    Names.Named{"QuantityLiteral", Lint.QuantityLiteral{}},
    Names.Named{"QuantityMinimum", Lint.QuantityMinimum{}},
    Names.Named{"TypeApplication", Lint.TypeApplication{}},
    Names.Named{"Elimination", Lint.Elimination{}},
    Names.Named{"Absurd", Lint.Absurd{}},
    Names.Named{"Equality", Lint.Equality{}},
    Names.Named{"Reflexivity", Lint.Reflexivity{}},
    Names.Named{"Rewrite", Lint.Rewrite{}},
    Names.Named{"Hole", Lint.Hole{}}
  ]

def Quantity.names() -> List<&2, Names.Named<Lint.Quantity>>:
  [
    Names.Named{"Once", Lint.Once{}},
    Names.Named{"Many", Lint.Many{}},
    Names.Named{"Erased", Lint.Erased{}},
    Names.Named{"Template", Lint.Template{}}
  ]

def Span.read(path: String, beg: String, end: String) -> Maybe<&2, Lint.Span>:
  do Maybe<&2, Lint.Span>:
    b: U32 <- U32.read(beg)
    e: U32 <- U32.read(end)
    return Lint.Span{path, b, e}

# A node from the fields of its record, in the file at `path`; `kinds` is `Syntax.names` as a table.
def Node.read(
  path: String,
  kinds: Map<&2, Maybe<&2, Lint.Syntax>>,
  fields: List<&2, String>
) -> Maybe<&2, Lint.Node>:
  match fields:
    case Con{
      id,
      Con{
        parent,
        Con{
          owner,
          Con{syntax, Con{name, Con{binder, Con{quantity, Con{beg, Con{end, Con{target, Nil{}}}}}}}}
        }
      }
    }:
      do Maybe<&2, Lint.Node>:
        i: U32 <- U32.read(id)
        p: U32 <- U32.read(parent)
        o: U32 <- U32.read(owner)
        s: Lint.Syntax <- Names.find(Lint.Syntax, kinds, syntax)
        return Lint.Node{
          i,
          p,
          o,
          s,
          name,
          U32.read(binder),
          Names.lookup(Lint.Quantity, quantity, Quantity.names()),
          Span.read(path, beg, end),
          target
        }
    case _:
      None{}

# What a record of the answer is: a source, a node of the latest source, or a fact on the latest node.
type Record is Data:
  SourceRecord{}
  NodeRecord{}
  FactRecord{}

def Record.names() -> List<&2, Names.Named<Record>>:
  [
    Names.Named{"node", NodeRecord{}},
    Names.Named{"fact", FactRecord{}},
    Names.Named{"file", SourceRecord{}}
  ]

def Role.names() -> List<&2, Names.Named<Lint.Role>>:
  [Names.Named{"term", Lint.OfTerm{}}, Names.Named{"binder", Lint.OfBinder{}}]

# A fact on `node` from the fields of its record: its role, the check and handle of its type, its quantity, and how
# often its binder is used, if the checker says.
def Fact.read(node: Lint.Node, fields: List<&2, String>) -> Maybe<&2, Lint.Fact>:
  match fields:
    case Con{role, Con{check, Con{id, Con{quantity, Con{used, Nil{}}}}}}:
      do Maybe<&2, Lint.Fact>:
        r: Lint.Role <- Names.lookup(Lint.Role, role, Role.names())
        c: U32 <- U32.read(check)
        i: U32 <- U32.read(id)
        q: Lint.Quantity <- Names.lookup(Lint.Quantity, quantity, Quantity.names())
        return Lint.Fact{
          node,
          r,
          q,
          Names.lookup(Lint.Quantity, used, Quantity.names()),
          Lint.TypeRef{c, i}
        }
    case _:
      None{}

# The sources read so far, last first, each with its nodes and facts last first.
def Decode.add(
  kind: Maybe<&2, Record>,
  fields: List<&2, String>,
  sources: List<&2, Lint.Source>,
  kinds: Map<&2, Maybe<&2, Lint.Syntax>>
) -> Maybe<&2, List<&2, Lint.Source>>:
  match kind fields sources:
    case Some{NodeRecord{}} _ Con{Lint.Source{+path, namespace, text, nodes, facts}, rest}:
      do Maybe<&2, List<&2, Lint.Source>>:
        n: Lint.Node <- Node.read(path, kinds, fields)
        return Lint.Source{path, namespace, text, n <> nodes, facts} <> rest
    case Some{
      FactRecord{}
    } _ Con{Lint.Source{path, namespace, text, Con{+node, nodes}, facts}, rest}:
      do Maybe<&2, List<&2, Lint.Source>>:
        f: Lint.Fact <- Fact.read(node, fields)
        return Lint.Source{path, namespace, text, node <> nodes, f <> facts} <> rest
    case Some{SourceRecord{}} Con{path, Con{namespace, Con{text, Nil{}}}} _:
      Some{Lint.Source{path, namespace, text, [], []} <> sources}
    case _ _ _:
      None{}

def Decode.in_order(
  sources: List<&2, Lint.Source>,
  done: List<&2, Lint.Source>
) -> List<&2, Lint.Source>:
  match sources:
    case Nil{}:
      done
    case Con{Lint.Source{path, namespace, text, nodes, facts}, rest}:
      Decode.in_order(
        rest,
        Lint.Source{
          path,
          namespace,
          text,
          List.reverse(&2, Lint.Node, nodes),
          List.reverse(&2, Lint.Fact, facts)
        }
          <> done
      )

# The program of an answer's records: a source record, then its nodes and facts, for each source. `kinds` is
# `Syntax.names` as a table.
def Decode.read(
  records: List<&2, List<&2, String>>,
  sources: List<&2, Lint.Source>,
  +kinds: Map<&2, Maybe<&2, Lint.Syntax>>
) -> Maybe<&2, Lint.Program>:
  match records:
    case Nil{}:
      Some{Lint.Program{Decode.in_order(sources, [])}}
    case Con{Con{tag, fields}, rest}:
      do Maybe<&2, Lint.Program>:
        added: List<
          &2,
          Lint.Source> <- Decode.add(
          Names.lookup(Record, tag, Record.names()),
          fields,
          sources,
          kinds
        )
        Decode.read(rest, added, kinds)
    case Con{Nil{}, rest}:
      None{}

def Decode.of(records: List<&2, List<&2, String>>) -> Maybe<&2, Lint.Program>:
  Decode.read(
    records,
    [],
    Names.table(Lint.Syntax, Syntax.names(), Map.new(&2, Maybe<&2, Lint.Syntax>))
  )

def Check.malformed(-A: Type) -> IO(A):
  IO.die(A, 1, "bend-lint: the checker's answer is malformed")

def Check.passed(
  tagged: Bool,
  check: Maybe<&2, U32>,
  program: Maybe<&2, Lint.Program>
) -> IO(Program.Check):
  match tagged check program:
    case True{} Some{c} Some{p}:
      IO.pure(Program.Check, Program.Passed{p, c})
    case _ _ _:
      Check.malformed(Program.Check)

# A passed check's answer: its number, then its program.
def Check.read(records: List<&2, List<&2, String>>) -> IO(Program.Check):
  match records:
    case Con{Con{tag, Con{check, Nil{}}}, rest}:
      Check.passed(String.eq(tag, "check"), U32.read(check), Decode.of(rest))
    case _:
      Check.malformed(Program.Check)

def Records.keep(
  hit: Bool,
  record: List<&2, String>,
  out: List<&2, List<&2, String>>
) -> List<&2, List<&2, String>>:
  match hit:
    case True{}:
      record <> out
    case False{}:
      out

# The records of the parsed files and their nodes, in order.
def Records.syntax(
  records: List<&2, List<&2, String>>,
  out: List<&2, List<&2, String>>
) -> List<&2, List<&2, String>>:
  match records:
    case Nil{}:
      List.reverse(&2, List<&2, String>, out)
    case Con{Con{+tag, fields}, rest}:
      Records.syntax(
        rest,
        Records.keep(String.eq(tag, "file") || String.eq(tag, "node"), Con{tag, fields}, out)
      )
    case Con{Nil{}, rest}:
      Records.syntax(rest, out)

def Records.path(hit: Bool, fields: List<&2, String>, out: List<&2, String>) -> List<&2, String>:
  match hit fields:
    case True{} Con{path, Nil{}}:
      path <> out
    case _ _:
      out

# The files a failed check read: the paths of its `read` records, in order.
def Check.reads(records: List<&2, List<&2, String>>, out: List<&2, String>) -> List<&2, String>:
  match records:
    case Nil{}:
      List.reverse(&2, String, out)
    case Con{Con{tag, fields}, rest}:
      Check.reads(rest, Records.path(String.eq(tag, "read"), fields, out))
    case Con{Nil{}, rest}:
      Check.reads(rest, out)

# The program of the files a failed check parsed, if it parsed any.
def Check.parsed(syntax: List<&2, List<&2, String>>) -> Maybe<&2, Lint.Program>:
  match syntax:
    case Nil{}:
      None{}
    case _:
      Decode.of(syntax)

def Check.failed(
  failure: Program.Failure,
  +records: List<&2, List<&2, String>>
) -> IO(Program.Check):
  IO.pure(
    Program.Check,
    Program.Failed{failure, Check.reads(records, []), Check.parsed(Records.syntax(records, []))}
  )

# What an answer whose last record has `fields` says: if it is a `fail` record, why and maybe where the check failed.
def Check.closed(
  fail: Bool,
  fields: List<&2, String>,
  records: List<&2, List<&2, String>>
) -> IO(Program.Check):
  match fail fields:
    case True{} Con{message, Nil{}}:
      Check.failed(Program.Failure{message, None{}, ""}, records)
    case True{} Con{message, Con{path, Con{beg, Con{end, Con{text, Nil{}}}}}}:
      Check.failed(Program.Failure{message, Span.read(path, beg, end), text}, records)
    case True{} _:
      Check.malformed(Program.Check)
    case False{} _:
      Check.read(records)

def Check.ended(
  last: Maybe<&2, List<&2, String>>,
  records: List<&2, List<&2, String>>
) -> IO(Program.Check):
  match last:
    case Some{Con{tag, fields}}:
      Check.closed(String.eq(tag, "fail"), fields, records)
    case _:
      Check.read(records)

# What an answer says: the check's number and the program; or, ending in a `fail` record, why and where the check
# failed, the files it read (its `read` records), and what it parsed (its `file` and `node` records).
def Check.of(+records: List<&2, List<&2, String>>) -> IO(Program.Check):
  Check.ended(List.last(&2, List<&2, String>, records), records)

def check(path: String, facts: Bool) -> IO(Program.Check):
  IO.bind(
    List<&2, List<&2, String>>,
    Program.Check,
    ask(["check", path, Bool.pick(String, facts, "facts", "syntax")]),
    records => Check.of(records)
  )

# Frees what the server holds for the passed check numbered `check`: no rule asks about its types again.
def forget(check: U32) -> IO(Unit):
  IO.bind(
    List<&2, List<&2, String>>,
    Unit,
    ask(["forget", U32.show(check)]),
    records => IO.pure(Unit, Unit{})
  )

# Questions
# =========
def Question.field(q: Lint.Question) -> String:
  match q:
    case Lint.Show{Lint.TypeRef{c, i}}:
      "show:" ++ U32.show(c) ++ ":" ++ U32.show(i)
    case Lint.Same{Lint.TypeRef{c, i}, Lint.TypeRef{d, j}}:
      "same:" ++ U32.show(c) ++ ":" ++ U32.show(i) ++ ":" ++ U32.show(d) ++ ":" ++ U32.show(j)
    case Lint.Normal{Lint.TypeRef{c, i}}:
      "normal:" ++ U32.show(c) ++ ":" ++ U32.show(i)

def Question.fields(questions: List<&2, Lint.Question>, out: List<&2, String>) -> List<&2, String>:
  match questions:
    case Nil{}:
      List.reverse(&2, String, out)
    case Con{q, rest}:
      Question.fields(rest, Question.field(q) <> out)

def Answer.normalized(check: String, id: String) -> Maybe<&2, Lint.Answer>:
  do Maybe<&2, Lint.Answer>:
    c: U32 <- U32.read(check)
    i: U32 <- U32.read(id)
    return Lint.Normalized{Lint.TypeRef{c, i}}

def Answer.read.two(which: Maybe<&2, U32>, text: String) -> Maybe<&2, Lint.Answer>:
  match which:
    case Some{0}:
      Some{Lint.Shown{text}}
    case Some{1}:
      Some{Lint.Equal{String.eq(text, "true")}}
    case _:
      None{}

def Answer.read(record: List<&2, String>) -> Maybe<&2, Lint.Answer>:
  match record:
    case Con{tag, Con{text, Nil{}}}:
      Answer.read.two(
        Names.lookup(U32, tag, [Names.Named{"shown", 0}, Names.Named{"same", 1}]),
        text
      )
    case Con{tag, Con{check, Con{id, Nil{}}}}:
      Answer.normalized(check, id)
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
    ask("ask" <> Question.fields(questions, [])),
    records => Answer.got(Answer.all(records, []))
  )
