# The seam to Bend's checker, for as long as it is TS: the requests to seam.ts, and the reading of its answers. A
# check's answer holds the linter's program as seam.ts makes it of what Bend's parser and checker gave (see `check` in
# seam.ts). When the checker is Bend, glue in Bend makes the program, and this file goes.
# - A request is one connection: one line out, the answer in, then the server closes.
# - A line is fields split by a tab. A field escapes \, a tab and a newline as \\, \t and \n.
# - The answer is one line per record. Its first field is its kind.
import Base
import ./lint.bend as Lint

# What checking a file gives: its program, and the check's number on the server; or, if the check failed, the files it
# read, and, if it parsed them, the program they make, without facts.
type Check is Data:
  Passed{program: Lint.Program, check: U32}
  Failed{read: List<&2, String>, parsed: Maybe<&2, Lint.Program>}

# Requests
# ========
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

def mark(c: Char) -> Mark:
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
def unescaped(c: Char) -> Char:
  match c:
    case 'n':
      '\n'
    case 't':
      '\t'
    case _:
      c

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

# Programs
# ========

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

def Span.of(+path: String, beg: Maybe<&2, U32>, end: Maybe<&2, U32>) -> Maybe<&2, Lint.Span>:
  match beg end:
    case Some{b} Some{e}:
      Some{Lint.Span{path, b, e}}
    case _ _:
      None{}

# The top `n` of `stack`, in order (the last pushed last), and the rest of it.
def pop(n: Nat, stack: List<&2, Lint.Node>, out: List<&2, Lint.Node>) -> List<&2, Lint.Node> & List<&2, Lint.Node>:
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
    case Some{s} Reader{check, failed, read, sources, Some{Lint.Source{+path, namespace, text, none}}, nodes, facts}:
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
    case Con{
      SCon{tag, SNil{}},
      Con{name, Con{beg, Con{end, Con{kids, Con{a, Con{b, Nil{}}}}}}}
    }:
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

def Check.of(
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
      Check.of(
        failed,
        check,
        List.reverse(&2, String, read),
        List.reverse(&2, Lint.Source, Reader.close(open, nodes, sources))
      )
    case Garbled{}:
      None{}

# Questions
# =========
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
    ask("ask" <> Question.fields(questions, [])),
    records => Answer.got(Answer.all(records, []))
  )

# Checks
# ======
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
def check(path: String, +facts: Bool, wanted: List<&2, String>) -> IO(Check):
  IO.bind(
    List<&2, List<&2, String>>,
    Check,
    ask(Check.request(path, facts, wanted)),
    records => Check.got(
      Reader.done(Reader.go(records, Reader{None{}, False{}, [], [], None{}, [], []}))
    )
  )

# Frees what the server holds for the passed check numbered `check`: no rule asks about its types again.
def forget(check: U32) -> IO(Unit):
  IO.bind(
    List<&2, List<&2, String>>,
    Unit,
    ask(["forget", U32.show(check)]),
    records => IO.pure(Unit, Unit{})
  )
