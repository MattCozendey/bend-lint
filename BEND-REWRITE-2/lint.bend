# bend-lint, in Bend. A rules program imports this file and calls it with its rules (main.bend is the default one).
# Every comment on this file stays here.
#
# Design
# - Only Bend rules. The target is the C lane; the JS lane must work too.
# - The rules program is an ordinary Bend program: `bend main.bend -o lint` builds it once. No restart, no rule cache.
# - Bend's checker is TS for now. server.ts runs the program and answers its questions about Bend files over local
#   TCP. When the checker is Bend, the server goes, and these questions become calls.
# - Rules are pure, so they can run in parallel. Questions to the checker go through an Ask monad, answered in batches.
# - A rule reads an indexed Program, built once per check: one owner, borrowed by every rule. A file rule reads the
#   same Program, seen from one file. A def's body is a flat list of nodes with numeric IDs.
# - Findings come first. A fix is a list of typed operations that the rule requests; the linter plans them and
#   decides their safety. Until Bend's checker is Bend, every fix is Dangerous.
#
# The wire
# - A request is one connection: one line out, the answer in, then the server closes.
# - A line is fields split by a tab. A field escapes \, a tab and a newline as \\, \t and \n.
# - The answer is one line per record. Its first field is its kind.
import Base

# Wire
# ====

# What a character is to the wire.
type Mark is Data:
  Slash{}
  Tab{}
  Newline{}
  Plain{}

# An answer read so far: whether a \ came just before, the field, the record's fields and the records, each last
# first.
type Reading is Data:
  Reading{escaped: Bool, field: String, fields: List<&2, String>, records: List<&2, List<&2, String>>}

def Wire.mark(+c: Char) -> Mark:
  Bool.pick(
    Mark,
    Char.is_eq(c, '\\'),
    Slash{},
    Bool.pick(Mark, Char.is_eq(c, '\t'), Tab{}, Bool.pick(Mark, Char.is_eq(c, '\n'), Newline{}, Plain{}))
  )

# A field's character with its escape undone: the character after a \.
def Wire.unescaped(+c: Char) -> Char:
  Bool.pick(Char, Char.is_eq(c, 'n'), '\n', Bool.pick(Char, Char.is_eq(c, 't'), '\t', c))

def Wire.read(mark: Mark, +c: Char, r: Reading) -> Reading:
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

# A field onto `out`, which is last first.
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

# The server's port, from BEND_LINT_PORT.
def Wire.port.of(port: Maybe<&2, U32>) -> IO(U32):
  match port:
    case Some{p}:
      IO.pure(U32, p)
    case None{}:
      IO.die(U32, 2, "bend-lint: BEND_LINT_PORT is not a port; run this program with `bun server.ts`")

def Wire.port() -> IO(U32):
  do IO<U32>:
    text : String <- IO.try(String, IO.get_env("BEND_LINT_PORT"))
    Wire.port.of(U32.read(text))

# Asks the server, and gives its answer's records.
def Wire.ask(request: List<&2, String>) -> IO(List<&2, List<&2, String>>):
  do IO<List<&2, List<&2, String>>>:
    port : U32 <- Wire.port()
    sock : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
    sent : Socket & Result<&1, &1, (U32 & String) & String, Unit> <- TCP.send(sock, Wire.line(request, ""))
    got : List<&2, String> <- Wire.sent(sent)
    return Wire.records(List.reverse(&2, String, got), Reading{False{}, "", [], []})

# Program
# =======

# What a syntax node is: a declaration, a part of one, a term, or a pattern, as Bend's parser reads it.
type Syntax is Data:
  Import{}
  Definition{}
  Datatype{}
  Constructor{}
  Law{}
  Parameter{}
  Field{}
  Returns{}
  Body{}
  Variable{}
  Reference{}
  Substitution{}
  Let{}
  Binding{}
  Sort{}
  QuantityType{}
  QuantityLiteral{}
  QuantityMinimum{}
  Forall{}
  Lambda{}
  Application{}
  TypeApplication{}
  Construction{}
  Literal{}
  Elimination{}
  Absurd{}
  Equality{}
  Reflexivity{}
  Rewrite{}
  Hole{}
  Annotation{}
  Match{}
  Case{}
  Destructure{}
  PatternVariable{}
  PatternConstructor{}

type Quantity is Data:
  Erased{}
  Once{}
  Many{}
  Template{}

# Where a node is: its file, and offsets in code points.
type Span is Data:
  Span{path: String, beg: U32, end: U32}

# A syntax node: its id and its parent's (0 for none), what it is, its name as written, the binder it declares or
# uses (numbered per declaration), its quantity, where it is, and the global name it declares or uses, as the check
# names it.
type Node is Data:
  Node{
    id: U32,
    parent: U32,
    syntax: Syntax,
    name: String,
    binder: Maybe<&2, U32>,
    quantity: Maybe<&2, Quantity>,
    span: Maybe<&2, Span>,
    target: String
  }

# A file the check parsed: its path, its namespace in the check, its text, and its nodes, parents first.
type Source is Data:
  Source{path: String, namespace: String, text: String, nodes: List<&2, Node>}

type Program is Data:
  Program{sources: List<&2, Source>}

# What checking a file gives: its program, or why the check failed.
type Check is Data:
  Passed{program: Program}
  Failed{message: String}

# A value with the name the wire gives it.
type Named<-A: Data> is Data:
  Named{name: String, value: A}

# The value `key` names in `table`.
def Program.lookup(-A: Data, +key: String, table: List<&2, Named<A>>) -> Maybe<&2, A>:
  match table:
    case Nil{}:
      None{}
    case Con{Named{+k, +v}, rest}:
      Bool.pick(Maybe<&2, A>, String.eq(k, key), Some{v}, Program.lookup(A, key, rest))

def Syntax.names() -> List<&2, Named<Syntax>>:
  [
    Named{"Variable", Variable{}},
    Named{"Reference", Reference{}},
    Named{"Application", Application{}},
    Named{"Lambda", Lambda{}},
    Named{"Literal", Literal{}},
    Named{"Construction", Construction{}},
    Named{"PatternVariable", PatternVariable{}},
    Named{"PatternConstructor", PatternConstructor{}},
    Named{"Forall", Forall{}},
    Named{"Annotation", Annotation{}},
    Named{"Match", Match{}},
    Named{"Case", Case{}},
    Named{"Destructure", Destructure{}},
    Named{"Let", Let{}},
    Named{"Binding", Binding{}},
    Named{"Parameter", Parameter{}},
    Named{"Field", Field{}},
    Named{"Returns", Returns{}},
    Named{"Body", Body{}},
    Named{"Definition", Definition{}},
    Named{"Datatype", Datatype{}},
    Named{"Constructor", Constructor{}},
    Named{"Law", Law{}},
    Named{"Import", Import{}},
    Named{"Substitution", Substitution{}},
    Named{"Sort", Sort{}},
    Named{"QuantityType", QuantityType{}},
    Named{"QuantityLiteral", QuantityLiteral{}},
    Named{"QuantityMinimum", QuantityMinimum{}},
    Named{"TypeApplication", TypeApplication{}},
    Named{"Elimination", Elimination{}},
    Named{"Absurd", Absurd{}},
    Named{"Equality", Equality{}},
    Named{"Reflexivity", Reflexivity{}},
    Named{"Rewrite", Rewrite{}},
    Named{"Hole", Hole{}}
  ]

def Quantity.names() -> List<&2, Named<Quantity>>:
  [Named{"Once", Once{}}, Named{"Many", Many{}}, Named{"Erased", Erased{}}, Named{"Template", Template{}}]

def Span.read(path: String, beg: String, end: String) -> Maybe<&2, Span>:
  do Maybe<&2, Span>:
    b : U32 <- U32.read(beg)
    e : U32 <- U32.read(end)
    return Span{path, b, e}

# A node from the fields of its record, in a file at `path`.
def Node.read(path: String, fields: List<&2, String>) -> Maybe<&2, Node>:
  match fields:
    case Con{id, Con{parent, Con{syntax, Con{name, Con{binder, Con{quantity, Con{beg, Con{end, Con{target, Nil{}}}}}}}}}}:
      do Maybe<&2, Node>:
        i : U32 <- U32.read(id)
        p : U32 <- U32.read(parent)
        s : Syntax <- Program.lookup(Syntax, syntax, Syntax.names())
        return Node{
          i,
          p,
          s,
          name,
          U32.read(binder),
          Program.lookup(Quantity, quantity, Quantity.names()),
          Span.read(path, beg, end),
          target
        }
    case _:
      None{}

# The sources read so far, last first, each with its nodes last first; with a node record, its source is the head.
def Program.add_node(fields: List<&2, String>, sources: List<&2, Source>) -> Maybe<&2, List<&2, Source>>:
  match sources:
    case Con{Source{+path, namespace, text, nodes}, rest}:
      do Maybe<&2, List<&2, Source>>:
        n : Node <- Node.read(path, fields)
        return Source{path, namespace, text, n <> nodes} <> rest
    case Nil{}:
      None{}

def Program.add_source(fields: List<&2, String>, sources: List<&2, Source>) -> Maybe<&2, List<&2, Source>>:
  match fields:
    case Con{path, Con{namespace, Con{text, Nil{}}}}:
      Some{Source{path, namespace, text, []} <> sources}
    case _:
      None{}

def Program.add(is_node: Bool, fields: List<&2, String>, sources: List<&2, Source>) -> Maybe<&2, List<&2, Source>>:
  match is_node:
    case True{}:
      Program.add_node(fields, sources)
    case False{}:
      Program.add_source(fields, sources)

# The sources in order, each with its nodes in order.
def Program.sources_in_order(sources: List<&2, Source>, done: List<&2, Source>) -> List<&2, Source>:
  match sources:
    case Nil{}:
      done
    case Con{Source{path, namespace, text, nodes}, rest}:
      Program.sources_in_order(rest, Source{path, namespace, text, List.reverse(&2, Node, nodes)} <> done)

# The program of an answer's records: a source record, then its nodes, for each source.
def Program.read(records: List<&2, List<&2, String>>, sources: List<&2, Source>) -> Maybe<&2, Program>:
  match records:
    case Nil{}:
      Some{Program{Program.sources_in_order(sources, [])}}
    case Con{Con{+tag, fields}, rest}:
      do Maybe<&2, Program>:
        added : List<&2, Source> <- Program.add(String.eq(tag, "node"), fields, sources)
        Program.read(rest, added)
    case Con{Nil{}, rest}:
      None{}

def Check.read(program: Maybe<&2, Program>) -> IO(Check):
  match program:
    case Some{p}:
      IO.pure(Check, Passed{p})
    case None{}:
      IO.die(Check, 1, "bend-lint: the checker's answer is malformed")

# What the check of the file at `path` gives.
def Check.of(records: List<&2, List<&2, String>>) -> IO(Check):
  match records:
    case Con{Con{+tag, Con{message, Nil{}}}, rest}:
      IO.pure(Check, Bool.pick(Check, String.eq(tag, "fail"), Failed{message}, Failed{"bend-lint: the checker's answer is malformed"}))
    case _:
      Check.read(Program.read(records, []))

def Check.run(path: String) -> IO(Check):
  IO.bind(List<&2, List<&2, String>>, Check, Wire.ask(["check", path]), Check.of)


# Rules
# =====

type Severity is Data:
  Error{}
  Warning{}
  Information{}
  Hint{}

# What a rule finds: how severe, where, and what to do about it.
type Finding is Data:
  Finding{severity: Severity, span: Span, message: String}

# A finding, with the id of the rule that found it.
type Found is Data:
  Found{rule: String, finding: Finding}

# What a file rule sees: the program, from one of its files.
type Here is Data:
  Here{program: Program, source: Source}

type Rule is Type:
  Rule{id: String, run: @+here: Here -> List<&2, Finding>}

# The nodes of the file a rule runs on.
def Here.nodes(here: Here) -> List<&2, Node>:
  match here:
    case Here{program, Source{path, namespace, text, nodes}}:
      nodes

# The namespace of the file at `path`, as the check names it: "" for Base, or a file the check did not parse.
def Here.namespace_of.go(sources: List<&2, Source>, +path: String) -> String:
  match sources:
    case Nil{}:
      ""
    case Con{Source{+p, namespace, text, nodes}, rest}:
      Bool.pick(String, String.eq(p, path), namespace, Here.namespace_of.go(rest, path))

def Here.namespace_of(here: Here, path: String) -> String:
  match here:
    case Here{Program{sources}, source}:
      Here.namespace_of.go(sources, path)

# The global names the declarations of a file declare, onto `out`.
def Here.declared.go(nodes: List<&2, Node>, out: List<&2, String>) -> List<&2, String>:
  match nodes:
    case Nil{}:
      out
    case Con{Node{id, 0, syntax, name, binder, quantity, span, target}, rest}:
      Here.declared.go(rest, target <> out)
    case Con{n, rest}:
      Here.declared.go(rest, out)

def Here.declared(here: Here) -> List<&2, String>:
  Here.declared.go(Here.nodes(here), [])

# The global name a node uses, if it uses one.
def Node.used(node: Node) -> Maybe<&2, String>:
  match node:
    case Node{id, parent, Reference{}, name, binder, quantity, span, target}:
      Some{target}
    case Node{id, parent, Construction{}, name, binder, quantity, span, target}:
      Some{target}
    case Node{id, parent, TypeApplication{}, name, binder, quantity, span, target}:
      Some{target}
    case Node{id, parent, PatternConstructor{}, name, binder, quantity, span, target}:
      Some{target}
    case Node{id, parent, Elimination{}, name, binder, quantity, span, target}:
      Some{target}
    case Node{id, parent, Literal{}, name, binder, quantity, span, target}:
      Some{target}
    case _:
      None{}

# `c` onto `out`, unless it is the ":" that ends a namespace.
def Name.keep(colon: Bool, c: Char, out: String) -> String:
  match colon:
    case True{}:
      out
    case False{}:
      SCon{c, out}

# The namespace of a global name: what comes before its first ":", or "" for Base and the checked file's own names.
# `colon` is whether the last character read was that ":"; `out` is what came before it, last first.
def Name.namespace.go(s: String, colon: Bool, out: String) -> String:
  match s colon:
    case _ True{}:
      String.reverse(out)
    case SNil{} False{}:
      ""
    case SCon{+c, t} False{}:
      Name.namespace.go(t, Char.is_eq(c, ':'), Name.keep(Char.is_eq(c, ':'), c, out))

def Name.namespace(name: String) -> String:
  Name.namespace.go(name, False{}, "")

# Whether `f(c, node)` holds for a node of `nodes`; `hit` is whether it held for one before.
def any.go(~C: Data, ~f: @+c: C -> Node -> Bool, nodes: List<&2, Node>, hit: Bool, +c: C) -> Bool:
  match nodes hit:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{n, rest} False{}:
      any.go(~C, ~f, rest, f(c, n), c)

def any(~C: Data, ~f: @+c: C -> Node -> Bool, +c: C, nodes: List<&2, Node>) -> Bool:
  any.go(~C, ~f, nodes, False{}, c)

# `xs` onto `out`, which is last first.
def onto(xs: List<&2, Finding>, out: List<&2, Finding>) -> List<&2, Finding>:
  match xs:
    case Nil{}:
      out
    case Con{h, t}:
      onto(t, h <> out)

# The findings `f(c, node)` gives for the nodes of `nodes`, in order; `out` holds those so far, last first.
def each.go(~C: Data, ~f: @+c: C -> Node -> List<&2, Finding>, nodes: List<&2, Node>, +c: C, out: List<&2, Finding>) -> List<&2, Finding>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Finding, out)
    case Con{n, rest}:
      each.go(~C, ~f, rest, c, onto(f(c, n), out))

def each(~C: Data, ~f: @+c: C -> Node -> List<&2, Finding>, +c: C, nodes: List<&2, Node>) -> List<&2, Finding>:
  each.go(~C, ~f, nodes, c, [])

# Running
# =======

# Each finding of `findings`, tagged with `rule`, onto `out` (last first).
def Found.tag(+rule: String, findings: List<&2, Finding>, out: List<&2, Found>) -> List<&2, Found>:
  match findings:
    case Nil{}:
      out
    case Con{f, rest}:
      Found.tag(rule, rest, Found{rule, f} <> out)

# What each rule finds on `here`, tagged with its id, onto `out` (last first).
def Rule.run_each(rules: List<&1, Rule>, +here: Here, out: List<&2, Found>) -> List<&2, Found>:
  match rules:
    case Nil{}:
      out
    case Con{Rule{id, run}, rest}:
      Rule.run_each(rest, here, Found.tag(id, run(here), out))

# The file the check was for: the last it parsed, as its imports come first.
def Program.root(sources: List<&2, Source>, last: Maybe<&2, Source>) -> Maybe<&2, Source>:
  match sources:
    case Nil{}:
      last
    case Con{s, rest}:
      Program.root(rest, Some{s})

# Output
# ======

def Severity.show(s: Severity) -> String:
  match s:
    case Error{}:
      "error"
    case Warning{}:
      "warning"
    case Information{}:
      "information"
    case Hint{}:
      "hint"

def Severity.is_error(s: Severity) -> Bool:
  match s:
    case Error{}:
      True{}
    case _:
      False{}

# The line and column (from 1) after reading `s`, from `line` and `column`.
def Text.position.go(s: String, +line: U32, +column: U32) -> String:
  match s:
    case SNil{}:
      U32.show(line) ++ ":" ++ U32.show(column)
    case SCon{+c, t}:
      Text.position.go(
        t,
        Bool.pick(U32, Char.is_eq(c, '\n'), (line + 1 : U32), line),
        Bool.pick(U32, Char.is_eq(c, '\n'), 1, (column + 1 : U32))
      )

# Where offset `at` of `text` is, as line:column (from 1).
def Text.position(text: String, at: U32) -> String:
  Text.position.go(String.take(text, U32.to_nat(at)), 1, 1)

# A finding as a line: path:line:column: severity rule: message.
def Found.show(+text: String, found: Found) -> String:
  match found:
    case Found{rule, Finding{+severity, Span{path, beg, end}, message}}:
      path ++ ":" ++ Text.position(text, beg) ++ ": " ++ Severity.show(severity) ++ " " ++ rule ++ ": " ++ message

def Found.lines(+text: String, founds: List<&2, Found>, out: List<&2, String>) -> List<&2, String>:
  match founds:
    case Nil{}:
      out
    case Con{f, rest}:
      Found.lines(text, rest, Found.show(text, f) <> out)

def Found.any_error(founds: List<&2, Found>, hit: Bool) -> Bool:
  match founds hit:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{Found{rule, Finding{severity, span, message}}, rest} False{}:
      Found.any_error(rest, Severity.is_error(severity))

# CLI
# ===

def cli.file(args: List<String>) -> IO(String):
  match args:
    case Con{program, Con{file, rest}}:
      IO.pure(String, file)
    case _:
      IO.die(String, 2, "usage: bun server.ts <program> <file>")

# Prints `lines`, if there are any.
def cli.say(lines: List<&2, String>) -> IO(Unit):
  match lines:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{h, t}:
      IO.print(String.join(h <> t, "\n"))

def cli.end(failed: Bool, n: Nat) -> IO(Unit):
  match failed:
    case True{}:
      IO.die(Unit, 1, "bend-lint: FAIL")
    case False{}:
      IO.print("bend-lint: " ++ Nat.show(n) ++ " finding(s)")

# Prints the findings, last first, of the file whose text is `text`; fails if one is an error.
def cli.print(+text: String, +founds: List<&2, Found>) -> IO(Unit):
  do IO<Unit>:
    cli.say(Found.lines(text, founds, []))
    cli.end(Found.any_error(founds, False{}), List.length(&2, Found, founds))

def cli.lint(~rules: List<&1, Rule>, +program: Program, root: Maybe<&2, Source>) -> IO(Unit):
  match root:
    case Some{Source{+path, namespace, +text, nodes}}:
      cli.print(text, Rule.run_each(rules, Here{program, Source{path, namespace, text, nodes}}, []))
    case None{}:
      IO.die(Unit, 2, "bend-lint: the check parsed no file")

def cli.checked(~rules: List<&1, Rule>, +file: String, check: Check) -> IO(Unit):
  match check:
    case Passed{Program{+sources}}:
      cli.lint(~rules, Program{sources}, Program.root(sources, None{}))
    case Failed{message}:
      do IO<Unit>:
        IO.print(file ++ ": error bend/check: " ++ message)
        IO.die(Unit, 1, "bend-lint: FAIL")

def cli.run(~rules: List<&1, Rule>, +file: String) -> IO(Unit):
  IO.bind(Check, Unit, Check.run(file), check => cli.checked(~rules, file, check))

# The command line: lint the named file with `rules`.
def cli(~rules: List<&1, Rule>) -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    file : String <- cli.file(args)
    cli.run(~rules, file)
