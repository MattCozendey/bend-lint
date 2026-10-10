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

# A syntax node: its id, its parent's (0 for none) and its top-level declaration's (its own, at the top), what it is,
# its name as written, the binder it declares or uses (numbered per top-level declaration), its quantity, where it is,
# and the global name it declares or uses, as the check names it (an import's is the path of the file it loads).
type Node is Data:
  Node{
    id: U32,
    parent: U32,
    owner: U32,
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
          0,
          s,
          name,
          U32.read(binder),
          Program.lookup(Quantity, quantity, Quantity.names()),
          Span.read(path, beg, end),
          target
        }
    case _:
      None{}

# `node` with its owner: itself at the top, else the owner of the node read before it.
def Node.owned(previous: List<&2, Node>, node: Node) -> Node:
  match previous node:
    case Con{Node{i, p, owner, s, n, b, q, sp, t}, rest} Node{+id, +parent, o, syntax, name, binder, quantity, span, target}:
      Node{id, parent, Bool.pick(U32, U32.is_eq(parent, 0), id, owner), syntax, name, binder, quantity, span, target}
    case Nil{} Node{+id, parent, o, syntax, name, binder, quantity, span, target}:
      Node{id, parent, id, syntax, name, binder, quantity, span, target}

# The sources read so far, last first, each with its nodes last first; with a node record, its source is the head.
def Program.add_node(fields: List<&2, String>, sources: List<&2, Source>) -> Maybe<&2, List<&2, Source>>:
  match sources:
    case Con{Source{+path, namespace, text, +nodes}, rest}:
      do Maybe<&2, List<&2, Source>>:
        n : Node <- Node.read(path, fields)
        return Source{path, namespace, text, Node.owned(nodes, n) <> nodes} <> rest
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


# Declarations
# ============

# A name a node declares, and the nodes that use it, in order.
type Declaration is Data:
  Declaration{node: Node, references: List<&2, Node>}

# What a syntax declares: a global name, a binder of its top-level declaration, or nothing (an import declares an
# alias, which Imports below handles).
type Declares is Data:
  DeclaresGlobal{}
  DeclaresBinder{}
  DeclaresNothing{}

def Syntax.declares(syntax: Syntax) -> Declares:
  match syntax:
    case Definition{}:
      DeclaresGlobal{}
    case Datatype{}:
      DeclaresGlobal{}
    case Constructor{}:
      DeclaresGlobal{}
    case Law{}:
      DeclaresGlobal{}
    case Parameter{}:
      DeclaresBinder{}
    case Field{}:
      DeclaresBinder{}
    case Binding{}:
      DeclaresBinder{}
    case Lambda{}:
      DeclaresBinder{}
    case Forall{}:
      DeclaresBinder{}
    case PatternVariable{}:
      DeclaresBinder{}
    case _:
      DeclaresNothing{}

# The namespace of a global name: what comes before its first ":", or "" for Base and the checked file's own names.
# `colon` is whether the last character read was that ":"; `out` is what came before it, last first.
def Name.keep(colon: Bool, c: Char, out: String) -> String:
  match colon:
    case True{}:
      out
    case False{}:
      SCon{c, out}

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

# The key that ties a use to what it uses: "g" and a global name, or "l", a top-level declaration's id and a binder.
def Key.global(name: String) -> String:
  "g" ++ name

def Key.binder(owner: U32, binder: U32) -> String:
  "l" ++ U32.show(owner) ++ ":" ++ U32.show(binder)

def Key.declared.of(declares: Declares, owner: U32, binder: Maybe<&2, U32>, anonymous: Bool, target: String) ->
  Maybe<&2, String>:
  match declares binder anonymous:
    case DeclaresGlobal{} _ _:
      Some{Key.global(target)}
    case DeclaresBinder{} Some{b} False{}:
      Some{Key.binder(owner, b)}
    case _ _ _:
      None{}

# The key of what a node declares, if it declares a global or a named binder.
def Key.declared(node: Node) -> Maybe<&2, String>:
  match node:
    case Node{id, parent, owner, syntax, +name, binder, quantity, span, target}:
      Key.declared.of(Syntax.declares(syntax), owner, binder, String.eq(name, "_"), target)

# The global name a node uses, if it uses one.
def Node.used(node: Node) -> Maybe<&2, String>:
  match node:
    case Node{id, parent, owner, Reference{}, name, binder, quantity, span, target}:
      Some{target}
    case Node{id, parent, owner, Construction{}, name, binder, quantity, span, target}:
      Some{target}
    case Node{id, parent, owner, TypeApplication{}, name, binder, quantity, span, target}:
      Some{target}
    case Node{id, parent, owner, PatternConstructor{}, name, binder, quantity, span, target}:
      Some{target}
    case Node{id, parent, owner, Elimination{}, name, binder, quantity, span, target}:
      Some{target}
    case Node{id, parent, owner, Literal{}, name, binder, quantity, span, target}:
      Some{target}
    case _:
      None{}

# The key of what a node uses, if it uses a global or a binder.
def Key.used(node: Node) -> Maybe<&2, String>:
  match node:
    case Node{id, parent, owner, Variable{}, name, Some{binder}, quantity, span, target}:
      Some{Key.binder(owner, binder)}
    case _:
      Maybe.map(&2, String, String, Key.global, Node.used(node))

# The uses of each key, last first.
def Uses.push(got: Map<&2, List<&2, Node>> & List<&2, Node>, key: String, node: Node) -> Map<&2, List<&2, Node>>:
  match got:
    case Tuple{m, old}:
      Map.set(&2, List<&2, Node>, m, key, node <> old)

def Uses.add(m: Map<&2, List<&2, Node>>, key: Maybe<&2, String>, node: Node) -> Map<&2, List<&2, Node>>:
  match key:
    case None{}:
      m
    case Some{+k}:
      Uses.push(Map.get(List<&2, Node>, [], m, k), k, node)

def Uses.of(nodes: List<&2, Node>, m: Map<&2, List<&2, Node>>) -> Map<&2, List<&2, Node>>:
  match nodes:
    case Nil{}:
      m
    case Con{+n, rest}:
      Uses.of(rest, Uses.add(m, Key.used(n), n))

def Uses.found(got: Map<&2, List<&2, Node>> & List<&2, Node>) -> List<&2, Node>:
  match got:
    case Tuple{m, found}:
      List.reverse(&2, Node, found)

# The uses of `key`, in order.
def Uses.get(+uses: Map<&2, List<&2, Node>>, key: String) -> List<&2, Node>:
  Uses.found(Map.get(List<&2, Node>, [], uses, key))

# Imports
# =======

# The namespace of the file at `path`, as the check names it: "" for Base, or a file the check did not parse.
def Imports.namespace(sources: List<&2, Source>, +path: String) -> String:
  match sources:
    case Nil{}:
      ""
    case Con{Source{+p, namespace, text, nodes}, rest}:
      Bool.pick(String, String.eq(p, path), namespace, Imports.namespace(rest, path))

# The global names a file's own top-level declarations declare, as a set.
def Imports.own(nodes: List<&2, Node>, out: Map<&2, Unit>) -> Map<&2, Unit>:
  match nodes:
    case Nil{}:
      out
    case Con{Node{id, 0, owner, syntax, name, binder, quantity, span, target}, rest}:
      Imports.own(rest, Map.set(&2, Unit, out, target, Unit{}))
    case Con{n, rest}:
      Imports.own(rest, out)

# What uses an import: a name written with its alias's prefix (`U.two`, a fill `def U.law(x):`), or, for Base, a
# global name with no namespace that the file does not declare.
type Importer is Data:
  ByAlias{prefix: String}
  ByBase{own: Map<&2, Unit>}

def Imports.not_own(got: Map<&2, Unit> & Bool) -> Bool:
  match got:
    case Tuple{m, has}:
      Bool.not(has)

def Imports.base_name(bare: Bool, +own: Map<&2, Unit>, name: String) -> Bool:
  match bare:
    case True{}:
      Imports.not_own(Map.has(&2, Unit, own, name))
    case False{}:
      False{}

def Imports.base_uses(+own: Map<&2, Unit>, used: Maybe<&2, String>) -> Bool:
  match used:
    case Some{+name}:
      Imports.base_name(String.is_empty(Name.namespace(name)), own, name)
    case None{}:
      False{}

def Imports.uses(+importer: Importer, +node: Node) -> Bool:
  match importer node:
    case ByAlias{+prefix} Node{id, parent, owner, syntax, name, binder, quantity, span, target}:
      String.starts_with(name, prefix)
    case ByBase{+own} _:
      Imports.base_uses(own, Node.used(node))

def Imports.keep(hit: Bool, n: Node, out: List<&2, Node>) -> List<&2, Node>:
  match hit:
    case True{}:
      n <> out
    case False{}:
      out

# The nodes of `nodes` that use an import, in order; `out` holds those so far, last first.
def Imports.references(nodes: List<&2, Node>, +importer: Importer, out: List<&2, Node>) -> List<&2, Node>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Node, out)
    case Con{+n, rest}:
      Imports.references(rest, importer, Imports.keep(Imports.uses(importer, n), n, out))

def Imports.importer(base: Bool, alias: String, +nodes: List<&2, Node>) -> Importer:
  match base:
    case True{}:
      ByBase{Imports.own(nodes, Map.new(&2, Unit))}
    case False{}:
      ByAlias{alias ++ "."}

# The declarations of a file's nodes, in order, with their uses in that file: `uses` indexes them, `sources` says
# which import loads Base.
def Declarations.of.node(
  +sources: List<&2, Source>,
  +nodes: List<&2, Node>,
  +uses: Map<&2, List<&2, Node>>,
  node: Node
) -> Maybe<&2, Declaration>:
  match node:
    case Node{id, parent, owner, Import{}, +name, binder, quantity, span, +target}:
      Some{
        Declaration{
          Node{id, parent, owner, Import{}, name, binder, quantity, span, target},
          Imports.references(
            nodes,
            Imports.importer(String.is_empty(Imports.namespace(sources, target)), name, nodes),
            []
          )
        }
      }
    case +n:
      Maybe.map(&2, String, Declaration, k => Declaration{n, Uses.get(uses, k)}, Key.declared(n))

def Declarations.push(found: Maybe<&2, Declaration>, out: List<&2, Declaration>) -> List<&2, Declaration>:
  match found:
    case Some{d}:
      d <> out
    case None{}:
      out

def Declarations.of.go(
  rest: List<&2, Node>,
  +sources: List<&2, Source>,
  +nodes: List<&2, Node>,
  +uses: Map<&2, List<&2, Node>>,
  out: List<&2, Declaration>
) -> List<&2, Declaration>:
  match rest:
    case Nil{}:
      List.reverse(&2, Declaration, out)
    case Con{n, more}:
      Declarations.of.go(
        more,
        sources,
        nodes,
        uses,
        Declarations.push(Declarations.of.node(sources, nodes, uses, n), out)
      )

def Declarations.of(+sources: List<&2, Source>, +nodes: List<&2, Node>) -> List<&2, Declaration>:
  Declarations.of.go(nodes, sources, nodes, Uses.of(nodes, Map.new(&2, List<&2, Node>)), [])

# Rules
# =====

type Severity is Data:
  Error{}
  Warning{}
  Information{}
  Hint{}

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

# What a rule finds: how severe, where, and what to do about it.
type Finding is Data:
  Finding{severity: Severity, span: Span, message: String}

# A finding, with the id of the rule that found it.
type Found is Data:
  Found{rule: String, finding: Finding}

# What a file rule sees: the program, from one of its files, and that file's declarations, with their uses in it.
type Here is Data:
  Here{program: Program, source: Source, declarations: List<&2, Declaration>}

type Rule is Type:
  Rule{id: String, run: @+here: Here -> List<&2, Finding>}

# The program from one of its files, built once for every rule that runs on that file.
def Here.of(program: Program, source: Source) -> Here:
  match program source:
    case Program{+sources} Source{path, namespace, text, +nodes}:
      Here{Program{sources}, Source{path, namespace, text, nodes}, Declarations.of(sources, nodes)}

# The nodes of the file a rule runs on, parents first.
def Here.nodes(here: Here) -> List<&2, Node>:
  match here:
    case Here{program, Source{path, namespace, text, nodes}, declarations}:
      nodes

def Here.declarations(here: Here) -> List<&2, Declaration>:
  match here:
    case Here{program, source, declarations}:
      declarations

# Whether `f(c, x)` holds for an `x` of `xs`; `hit` is whether it held for one before.
def any.go(~C: Data, ~A: Data, ~f: @+c: C -> A -> Bool, xs: List<&2, A>, hit: Bool, +c: C) -> Bool:
  match xs hit:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{x, rest} False{}:
      any.go(~C, ~A, ~f, rest, f(c, x), c)

def any(~C: Data, ~A: Data, ~f: @+c: C -> A -> Bool, +c: C, xs: List<&2, A>) -> Bool:
  any.go(~C, ~A, ~f, xs, False{}, c)

# `xs` onto `out`, which is last first.
def onto(xs: List<&2, Finding>, out: List<&2, Finding>) -> List<&2, Finding>:
  match xs:
    case Nil{}:
      out
    case Con{h, t}:
      onto(t, h <> out)

# The findings `f(c, x)` gives for each `x` of `xs`, in order; `out` holds those so far, last first.
def each.go(~C: Data, ~A: Data, ~f: @+c: C -> A -> List<&2, Finding>, xs: List<&2, A>, +c: C, out: List<&2, Finding>) ->
  List<&2, Finding>:
  match xs:
    case Nil{}:
      List.reverse(&2, Finding, out)
    case Con{x, rest}:
      each.go(~C, ~A, ~f, rest, c, onto(f(c, x), out))

def each(~C: Data, ~A: Data, ~f: @+c: C -> A -> List<&2, Finding>, +c: C, xs: List<&2, A>) -> List<&2, Finding>:
  each.go(~C, ~A, ~f, xs, c, [])

# The findings `f(x)` gives for each `x` of `xs`, in order; `out` holds those so far, last first.
def findings.go(~A: Data, ~f: A -> List<&2, Finding>, xs: List<&2, A>, out: List<&2, Finding>) -> List<&2, Finding>:
  match xs:
    case Nil{}:
      List.reverse(&2, Finding, out)
    case Con{x, rest}:
      findings.go(~A, ~f, rest, onto(f(x), out))

def findings(~A: Data, ~f: A -> List<&2, Finding>, xs: List<&2, A>) -> List<&2, Finding>:
  findings.go(~A, ~f, xs, [])

# Directives
# ==========
# Comments in a linted file that silence findings (disable) or demand them (expect):
# `# bend-lint: <disable|expect>-<file|begin|end|next|line> <rule>[@severity] -- <reason>`. One directive names one
# rule. An expect pins a severity; a disable takes none. file covers the whole file; begin and end bound a region;
# line covers its own line; next covers the next line that holds code. A finding is covered when its span starts on a
# covered line. Directives that stack on consecutive comment-only lines must be in order, by rule, severity and
# keyword. The checker's and bend-lint's own findings cannot be suppressed.

# A comment: where it is (code points), its line (from 0), whether code comes before it on its line, and its text
# after the #.
type Comment is Data:
  Comment{beg: U32, end: U32, line: U32, trailing: Bool, body: String}

# What a character is to the scan of a text.
type Glyph is Data:
  LineEnd{}
  CarriageReturn{}
  Hash{}
  DoubleQuote{}
  SingleQuote{}
  Backslash{}
  Blank{}
  Other{}

# Where the scan is: in code, a comment, a string or a char literal, or just after a \ in one.
type Mode is Data:
  InCode{}
  InComment{}
  InString{}
  InStringEscape{}
  InChar{}
  InCharEscape{}

# The scan so far: where it is, its offset and line, whether its line holds code, the comment it is in (its body last
# first), the comments before (last first), and whether each line before holds code (last first).
type Scan is Data:
  Scan{mode: Mode, at: U32, line: U32, code: Bool, open: Comment, comments: List<&2, Comment>, lines: List<&2, Bool>}

def Glyph.of(+c: Char) -> Glyph:
  Bool.pick(
    Glyph,
    Char.is_eq(c, '\n'),
    LineEnd{},
    Bool.pick(
      Glyph,
      Char.is_eq(c, '#'),
      Hash{},
      Bool.pick(
        Glyph,
        Char.is_eq(c, '"'),
        DoubleQuote{},
        Bool.pick(
          Glyph,
          Char.is_eq(c, '\''),
          SingleQuote{},
          Bool.pick(
            Glyph,
            Char.is_eq(c, '\\'),
            Backslash{},
            Bool.pick(
              Glyph,
              Char.is_eq(c, '\r'),
              CarriageReturn{},
              Bool.pick(Glyph, Char.is_eq(c, ' ') || Char.is_eq(c, '\t'), Blank{}, Other{})
            )
          )
        )
      )
    )
  )

# No comment: what the scan holds as its open comment outside one.
def Comment.none() -> Comment:
  Comment{0, 0, 0, False{}, ""}

# The comment `open`, ended at `at`, its body in order.
def Comment.closed(open: Comment, at: U32) -> Comment:
  match open:
    case Comment{beg, end, line, trailing, body}:
      Comment{beg, at, line, trailing, String.reverse(body)}

def Comment.push(open: Comment, c: Char) -> Comment:
  match open:
    case Comment{beg, end, line, trailing, body}:
      Comment{beg, end, line, trailing, SCon{c, body}}

def Scan.in_code(glyph: Glyph, +at: U32, +line: U32, +code: Bool, open: Comment, comments: List<&2, Comment>, lines: List<&2, Bool>) -> Scan:
  match glyph:
    case LineEnd{}:
      Scan{InCode{}, (at + 1 : U32), (line + 1 : U32), False{}, open, comments, code <> lines}
    case Hash{}:
      Scan{InComment{}, (at + 1 : U32), line, code, Comment{at, at, line, code, ""}, comments, lines}
    case DoubleQuote{}:
      Scan{InString{}, (at + 1 : U32), line, True{}, open, comments, lines}
    case SingleQuote{}:
      Scan{InChar{}, (at + 1 : U32), line, True{}, open, comments, lines}
    case Blank{}:
      Scan{InCode{}, (at + 1 : U32), line, code, open, comments, lines}
    case CarriageReturn{}:
      Scan{InCode{}, (at + 1 : U32), line, code, open, comments, lines}
    case _:
      Scan{InCode{}, (at + 1 : U32), line, True{}, open, comments, lines}

def Scan.in_comment(glyph: Glyph, c: Char, +at: U32, +line: U32, code: Bool, open: Comment, comments: List<&2, Comment>, lines: List<&2, Bool>) -> Scan:
  match glyph:
    case LineEnd{}:
      Scan{InCode{}, (at + 1 : U32), (line + 1 : U32), False{}, Comment.none(), Comment.closed(open, at) <> comments, code <> lines}
    case CarriageReturn{}:
      Scan{InCode{}, (at + 1 : U32), line, code, Comment.none(), Comment.closed(open, at) <> comments, lines}
    case _:
      Scan{InComment{}, (at + 1 : U32), line, code, Comment.push(open, c), comments, lines}

# A step in a string (`string`) or a char literal: a \ escapes the next character, the closing quote ends it, and a
# line it spans holds code.
def Scan.in_quote(string: Bool, glyph: Glyph, +at: U32, +line: U32, code: Bool, open: Comment, comments: List<&2, Comment>, lines: List<&2, Bool>) -> Scan:
  match string glyph:
    case True{} Backslash{}:
      Scan{InStringEscape{}, (at + 1 : U32), line, code, open, comments, lines}
    case False{} Backslash{}:
      Scan{InCharEscape{}, (at + 1 : U32), line, code, open, comments, lines}
    case True{} DoubleQuote{}:
      Scan{InCode{}, (at + 1 : U32), line, code, open, comments, lines}
    case False{} SingleQuote{}:
      Scan{InCode{}, (at + 1 : U32), line, code, open, comments, lines}
    case True{} LineEnd{}:
      Scan{InString{}, (at + 1 : U32), (line + 1 : U32), True{}, open, comments, True{} <> lines}
    case False{} LineEnd{}:
      Scan{InChar{}, (at + 1 : U32), (line + 1 : U32), True{}, open, comments, True{} <> lines}
    case True{} _:
      Scan{InString{}, (at + 1 : U32), line, code, open, comments, lines}
    case False{} _:
      Scan{InChar{}, (at + 1 : U32), line, code, open, comments, lines}

# A step just after a \ in a string (`string`) or a char literal: the character is taken as is.
def Scan.in_escape(string: Bool, glyph: Glyph, +at: U32, +line: U32, code: Bool, open: Comment, comments: List<&2, Comment>, lines: List<&2, Bool>) -> Scan:
  match string glyph:
    case True{} LineEnd{}:
      Scan{InString{}, (at + 1 : U32), (line + 1 : U32), True{}, open, comments, True{} <> lines}
    case False{} LineEnd{}:
      Scan{InChar{}, (at + 1 : U32), (line + 1 : U32), True{}, open, comments, True{} <> lines}
    case True{} _:
      Scan{InString{}, (at + 1 : U32), line, code, open, comments, lines}
    case False{} _:
      Scan{InChar{}, (at + 1 : U32), line, code, open, comments, lines}

def Scan.step(glyph: Glyph, c: Char, s: Scan) -> Scan:
  match s:
    case Scan{InCode{}, at, line, code, open, comments, lines}:
      Scan.in_code(glyph, at, line, code, open, comments, lines)
    case Scan{InComment{}, at, line, code, open, comments, lines}:
      Scan.in_comment(glyph, c, at, line, code, open, comments, lines)
    case Scan{InString{}, at, line, code, open, comments, lines}:
      Scan.in_quote(True{}, glyph, at, line, code, open, comments, lines)
    case Scan{InChar{}, at, line, code, open, comments, lines}:
      Scan.in_quote(False{}, glyph, at, line, code, open, comments, lines)
    case Scan{InStringEscape{}, at, line, code, open, comments, lines}:
      Scan.in_escape(True{}, glyph, at, line, code, open, comments, lines)
    case Scan{InCharEscape{}, at, line, code, open, comments, lines}:
      Scan.in_escape(False{}, glyph, at, line, code, open, comments, lines)

def Scan.go(text: String, s: Scan) -> Scan:
  match text:
    case SNil{}:
      s
    case SCon{+c, t}:
      Scan.go(t, Scan.step(Glyph.of(c), c, s))

# A text's comments, in order, and whether each line holds code, in order.
type Scanned is Data:
  Scanned{comments: List<&2, Comment>, lines: List<&2, Bool>}

def Scan.done(s: Scan) -> Scanned:
  match s:
    case Scan{InComment{}, +at, line, code, open, comments, lines}:
      Scanned{List.reverse(&2, Comment, Comment.closed(open, at) <> comments), List.reverse(&2, Bool, code <> lines)}
    case Scan{mode, at, line, code, open, comments, lines}:
      Scanned{List.reverse(&2, Comment, comments), List.reverse(&2, Bool, code <> lines)}

def Scan.of(text: String) -> Scanned:
  Scan.done(Scan.go(text, Scan{InCode{}, 0, 0, False{}, Comment.none(), [], []}))

type Action is Data:
  Disable{}
  Expect{}

type Scope is Data:
  WholeFile{}
  Begin{}
  End{}
  NextLine{}
  SameLine{}

# A directive: what it does, how far, the rule it names, the severity it pins, its comment, and its place among the
# file's directives.
type Directive is Data:
  Directive{action: Action, scope: Scope, rule: String, severity: Maybe<&2, Severity>, comment: Comment, index: U32}

# A comment that says bend-lint: a directive, or what is wrong with it.
type Said is Data:
  Said{directive: Directive}
  Wrong{comment: Comment, why: String}

def Directive.syntax() -> String:
  "Write `# bend-lint: <disable|expect>-<file|begin|end|next|line> <rule>[@severity] -- <reason>`."

def Action.names() -> List<&2, Named<Action>>:
  [Named{"disable", Disable{}}, Named{"expect", Expect{}}]

def Scope.names() -> List<&2, Named<Scope>>:
  [
    Named{"file", WholeFile{}},
    Named{"begin", Begin{}},
    Named{"end", End{}},
    Named{"next", NextLine{}},
    Named{"line", SameLine{}}
  ]

def Severity.names() -> List<&2, Named<Severity>>:
  [Named{"error", Error{}}, Named{"warning", Warning{}}, Named{"information", Information{}}, Named{"hint", Hint{}}]


def Action.show(a: Action) -> String:
  match a:
    case Disable{}:
      "disable"
    case Expect{}:
      "expect"

def Scope.show(s: Scope) -> String:
  match s:
    case WholeFile{}:
      "file"
    case Begin{}:
      "begin"
    case End{}:
      "end"
    case NextLine{}:
      "next"
    case SameLine{}:
      "line"

def Severity.code(s: Severity) -> U32:
  match s:
    case Error{}:
      0
    case Warning{}:
      1
    case Information{}:
      2
    case Hint{}:
      3

def Severity.same(a: Maybe<&2, Severity>, b: Maybe<&2, Severity>) -> Bool:
  match a b:
    case Some{x} Some{y}:
      U32.is_eq(Severity.code(x), Severity.code(y))
    case None{} None{}:
      True{}
    case _ _:
      False{}

# The words of a text, split at blanks: the word so far, last first, and the words before it, last first.
type Words is Data:
  Words{word: String, out: List<&2, String>}

def Words.step(blank: Bool, c: Char, w: Words) -> Words:
  match blank w:
    case True{} Words{SNil{}, out}:
      Words{"", out}
    case True{} Words{SCon{h, t}, out}:
      Words{"", String.reverse(SCon{h, t}) <> out}
    case False{} Words{word, out}:
      Words{SCon{c, word}, out}

def Words.go(s: String, w: Words) -> Words:
  match s:
    case SNil{}:
      w
    case SCon{+c, t}:
      Words.go(t, Words.step(Char.is_eq(c, ' ') || Char.is_eq(c, '\t'), c, w))

def Words.done(w: Words) -> List<&2, String>:
  match w:
    case Words{SNil{}, out}:
      List.reverse(&2, String, out)
    case Words{SCon{h, t}, out}:
      List.reverse(&2, String, String.reverse(SCon{h, t}) <> out)

def Words.of(s: String) -> List<&2, String>:
  Words.done(Words.go(s, Words{"", []}))

# A directive as written, before its severity and rule are checked.
type Draft is Data:
  Draft{action: Action, scope: Scope, rule: String, pinned: Maybe<&2, String>, reason: Maybe<&2, String>}

# Whether a rule id is two non-empty parts split by a /.
def Draft.rule_ok(parts: List<&2, String>) -> Bool:
  match parts:
    case Con{a, Con{b, Nil{}}}:
      Bool.not(String.is_empty(a)) && Bool.not(String.is_empty(b))
    case _:
      False{}

def Draft.ruled(ok: Bool, action: Action, scope: Scope, rule: String, pinned: Maybe<&2, String>, reason: Maybe<&2, String>) ->
  Maybe<&2, Draft>:
  match ok:
    case True{}:
      Some{Draft{action, scope, rule, pinned, reason}}
    case False{}:
      None{}

def Draft.named(action: Action, scope: Scope, parts: List<&2, String>, reason: Maybe<&2, String>) -> Maybe<&2, Draft>:
  match parts:
    case Con{+rule, Nil{}}:
      Draft.ruled(Draft.rule_ok(String.split(rule, '/')), action, scope, rule, None{}, reason)
    case Con{+rule, Con{p, rest}}:
      Draft.ruled(Draft.rule_ok(String.split(rule, '/')), action, scope, rule, Some{String.join(p <> rest, "@")}, reason)
    case Nil{}:
      None{}

def Draft.kind(parts: List<&2, String>, named: String, reason: Maybe<&2, String>) -> Maybe<&2, Draft>:
  match parts:
    case Con{a, Con{s, Nil{}}}:
      do Maybe<&2, Draft>:
        action : Action <- Program.lookup(Action, a, Action.names())
        scope : Scope <- Program.lookup(Scope, s, Scope.names())
        Draft.named(action, scope, String.split(named, '@'), reason)
    case _:
      None{}

def Draft.dashed(dash: Bool, kind: String, named: String, reason: String) -> Maybe<&2, Draft>:
  match dash:
    case True{}:
      Draft.kind(String.split(kind, '-'), named, Some{reason})
    case False{}:
      None{}

# The draft of a directive's words, after `bend-lint:`.
def Draft.of(words: List<&2, String>) -> Maybe<&2, Draft>:
  match words:
    case Con{kind, Con{named, Nil{}}}:
      Draft.kind(String.split(kind, '-'), named, None{})
    case Con{kind, Con{named, Con{+dash, Con{r, rest}}}}:
      Draft.dashed(String.eq(dash, "--"), kind, named, String.join(r <> rest, " "))
    case _:
      None{}

def Problem.when(hit: Bool, why: String) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{why}
    case False{}:
      None{}

def Problem.pinned(pinned: Maybe<&2, String>) -> Maybe<&2, String>:
  match pinned:
    case Some{+p}:
      Problem.when(Maybe.is_none(&2, Severity, Program.lookup(Severity, p, Severity.names())), p ++ " is not a severity.")
    case None{}:
      None{}

def Problem.severity(action: Action, pinned: Bool, +rule: String) -> Maybe<&2, String>:
  match action pinned:
    case Disable{} True{}:
      Some{"A disable takes no severity."}
    case Expect{} False{}:
      Some{"An expect pins a severity: " ++ rule ++ "@..."}
    case _ _:
      None{}

def Problem.reason(scope: Scope, reason: Bool) -> Maybe<&2, String>:
  match scope reason:
    case End{} True{}:
      Some{"An end takes no reason; the begin has it."}
    case End{} False{}:
      None{}
    case _ False{}:
      Some{"A reason is required, after `--`."}
    case _ True{}:
      None{}

def Problem.line(scope: Scope, trailing: Bool) -> Maybe<&2, String>:
  match scope trailing:
    case SameLine{} False{}:
      Some{"A line directive must follow code on its line."}
    case _ _:
      None{}

def Problem.first(problems: List<&2, Maybe<&2, String>>) -> Maybe<&2, String>:
  match problems:
    case Nil{}:
      None{}
    case Con{Some{why}, rest}:
      Some{why}
    case Con{None{}, rest}:
      Problem.first(rest)

# The namespace of a rule id: what comes before its first /.
def Rule.namespace.of(parts: List<&2, String>) -> String:
  match parts:
    case Con{ns, rest}:
      ns
    case Nil{}:
      ""

def Rule.namespace(rule: String) -> String:
  Rule.namespace.of(String.split(rule, '/'))

def Said.checked(why: Maybe<&2, String>, draft: Draft, comment: Comment, index: U32) -> Said:
  match why draft:
    case Some{w} _:
      Wrong{comment, w}
    case None{} Draft{action, scope, rule, pinned, reason}:
      Said{
        Directive{
          action,
          scope,
          rule,
          Maybe.bind(&2, String, Severity, pinned, p => Program.lookup(Severity, p, Severity.names())),
          comment,
          index
        }
      }

def Rule.reserved(namespace: String) -> Bool:
  match namespace:
    case +ns:
      String.eq(ns, "bend") || String.eq(ns, "bend-lint")

def Comment.trailing(comment: Comment) -> Bool:
  match comment:
    case Comment{beg, end, line, trailing, body}:
      trailing

# What a comment that holds a draft (or not) says, checked against the rules there are.
def Said.of(draft: Maybe<&2, Draft>, +comment: Comment, +known: List<&2, String>, index: U32) -> Said:
  match draft:
    case None{}:
      Wrong{comment, Directive.syntax()}
    case Some{Draft{+action, +scope, +rule, +pinned, +reason}}:
      Said.checked(
        Problem.first(
          [
            Problem.pinned(pinned),
            Problem.severity(action, Maybe.is_some(&2, String, pinned), rule),
            Problem.reason(scope, Maybe.is_some(&2, String, reason)),
            Problem.line(scope, Comment.trailing(comment)),
            Problem.when(Rule.reserved(Rule.namespace(rule)), rule ++ " findings cannot be suppressed."),
            Problem.when(Bool.not(List.contains(~String, ~String.eq, known, rule)), "There is no rule " ++ rule ++ ".")
          ]
        ),
        Draft{action, scope, rule, pinned, reason},
        comment,
        index
      )

def Said.read.body(directive: Bool, +rest: String, +comment: Comment, +known: List<&2, String>, index: U32) ->
  Maybe<&2, Said>:
  match directive:
    case True{}:
      Some{Said.of(Draft.of(Words.of(String.drop(rest, 10n))), comment, known, index)}
    case False{}:
      None{}

# What a comment says, if it says bend-lint:.
def Said.read(+comment: Comment, +known: List<&2, String>, index: U32) -> Maybe<&2, Said>:
  match comment:
    case Comment{beg, end, line, trailing, body}:
      Said.read.body(
        String.starts_with(String.trim_start(body), "bend-lint:"),
        String.trim_start(body),
        comment,
        known,
        index
      )

def Said.push(said: Maybe<&2, Said>, out: List<&2, Said>) -> List<&2, Said>:
  match said:
    case Some{s}:
      s <> out
    case None{}:
      out

# What the comments say, in order, each numbered; `out` holds those so far, last first.
def Said.all(comments: List<&2, Comment>, +known: List<&2, String>, +index: U32, out: List<&2, Said>) -> List<&2, Said>:
  match comments:
    case Nil{}:
      List.reverse(&2, Said, out)
    case Con{c, rest}:
      Said.all(rest, known, (index + 1 : U32), Said.push(Said.read(c, known, index), out))

# Where a begin was closed: its index, and the line of its end.
type Closed is Data:
  Closed{index: U32, line: U32}

# The begins open so far (latest first), the begins closed, and what is wrong (last first).
type Pairing is Data:
  Pairing{open: List<&2, Directive>, closed: List<&2, Closed>, wrong: List<&2, Said>}

# The latest open begin of an action and a rule.
def Open.latest(open: List<&2, Directive>, +action: String, +rule: String) -> Maybe<&2, Directive>:
  match open:
    case Nil{}:
      None{}
    case Con{Directive{+a, s, +r, +sev, +c, +i}, rest}:
      Bool.pick(
        Maybe<&2, Directive>,
        String.eq(Action.show(a), action) && String.eq(r, rule),
        Some{Directive{a, s, r, sev, c, i}},
        Open.latest(rest, action, rule)
      )

def Open.keep(drop: Bool, d: Directive, rest: List<&2, Directive>) -> List<&2, Directive>:
  match drop:
    case True{}:
      rest
    case False{}:
      d <> rest

# The open begins, less the one numbered `index`.
def Open.without(open: List<&2, Directive>, +index: U32) -> List<&2, Directive>:
  match open:
    case Nil{}:
      []
    case Con{Directive{a, s, r, sev, c, +i}, rest}:
      Open.keep(U32.is_eq(i, index), Directive{a, s, r, sev, c, i}, Open.without(rest, index))

def Pairing.closing(same: Bool, +index: U32, line: U32, rule: String, comment: Comment, p: Pairing) -> Pairing:
  match same p:
    case True{} Pairing{open, closed, wrong}:
      Pairing{Open.without(open, index), Closed{index, line} <> closed, wrong}
    case False{} Pairing{open, closed, wrong}:
      Pairing{open, closed, Wrong{comment, "This end closes no begin of " ++ rule ++ "."} <> wrong}

def Pairing.close(begin: Maybe<&2, Directive>, end: Directive, p: Pairing) -> Pairing:
  match begin end p:
    case Some{Directive{a, s, r, sev, c, +i}} Directive{ea, es, er, esev, Comment{b, e, +line, t, body}, ei} Pairing{+open, closed, wrong}:
      Pairing.closing(Severity.same(sev, esev), i, line, er, Comment{b, e, line, t, body}, Pairing{open, closed, wrong})
    case None{} Directive{ea, es, er, esev, ec, ei} Pairing{open, closed, wrong}:
      Pairing{open, closed, Wrong{ec, "This end closes no begin of " ++ er ++ "."} <> wrong}

def Pairing.step(said: Said, p: Pairing) -> Pairing:
  match said p:
    case Said{Directive{a, Begin{}, r, sev, c, i}} Pairing{open, closed, wrong}:
      Pairing{Directive{a, Begin{}, r, sev, c, i} <> open, closed, wrong}
    case Said{Directive{+a, End{}, +r, sev, c, i}} Pairing{+open, closed, wrong}:
      Pairing.close(Open.latest(open, Action.show(a), r), Directive{a, End{}, r, sev, c, i}, Pairing{open, closed, wrong})
    case _ _:
      p

def Pairing.go(saids: List<&2, Said>, p: Pairing) -> Pairing:
  match saids:
    case Nil{}:
      p
    case Con{s, rest}:
      Pairing.go(rest, Pairing.step(s, p))

# The begins left open, as what is wrong, onto `wrong`.
def Pairing.unclosed(open: List<&2, Directive>, wrong: List<&2, Said>) -> List<&2, Said>:
  match open:
    case Nil{}:
      wrong
    case Con{Directive{a, s, r, sev, c, i}, rest}:
      Pairing.unclosed(rest, Wrong{c, "This begin of " ++ r ++ " is never closed."} <> wrong)

# A directive and the lines it covers, both ends included (from 1 to 0 covers none).
type Covering is Data:
  Covering{directive: Directive, from: U32, to: U32}

def Lines.pick(hit: Bool, i: U32) -> Maybe<&2, U32>:
  match hit:
    case True{}:
      Some{i}
    case False{}:
      None{}

# The first line after `after` that holds code; `i` is the line of the head of `lines`.
def Lines.next_code(lines: List<&2, Bool>, found: Maybe<&2, U32>, +i: U32, +after: U32) -> Maybe<&2, U32>:
  match lines found:
    case _ Some{x}:
      Some{x}
    case Nil{} None{}:
      None{}
    case Con{code, rest} None{}:
      Lines.next_code(rest, Lines.pick(code && U32.is_gt(i, after), i), (i + 1 : U32), after)

def Closed.find(closed: List<&2, Closed>, +index: U32) -> Maybe<&2, U32>:
  match closed:
    case Nil{}:
      None{}
    case Con{Closed{+i, +line}, rest}:
      Bool.pick(Maybe<&2, U32>, U32.is_eq(i, index), Some{line}, Closed.find(rest, index))

def Covering.next(d: Directive, found: Maybe<&2, U32>) -> Covering:
  match found:
    case Some{+l}:
      Covering{d, l, l}
    case None{}:
      Covering{d, 1, 0}

# The lines a directive covers; `last` is the file's last line.
def Covering.of(said: Said, +lines: List<&2, Bool>, +closed: List<&2, Closed>, +last: U32) -> Maybe<&2, Covering>:
  match said:
    case Said{Directive{a, WholeFile{}, r, sev, c, i}}:
      Some{Covering{Directive{a, WholeFile{}, r, sev, c, i}, 0, last}}
    case Said{Directive{a, SameLine{}, r, sev, Comment{b, e, +l, t, body}, i}}:
      Some{Covering{Directive{a, SameLine{}, r, sev, Comment{b, e, l, t, body}, i}, l, l}}
    case Said{Directive{a, NextLine{}, r, sev, Comment{b, e, +l, t, body}, i}}:
      Some{Covering.next(Directive{a, NextLine{}, r, sev, Comment{b, e, l, t, body}, i}, Lines.next_code(lines, None{}, 0, l))}
    case Said{Directive{a, Begin{}, r, sev, Comment{b, e, +l, t, body}, +i}}:
      Some{
        Covering{
          Directive{a, Begin{}, r, sev, Comment{b, e, l, t, body}, i},
          l,
          Maybe.default(&2, U32, Closed.find(closed, i), last)
        }
      }
    case _:
      None{}

def Covering.push(c: Maybe<&2, Covering>, out: List<&2, Covering>) -> List<&2, Covering>:
  match c:
    case Some{x}:
      x <> out
    case None{}:
      out

def Covering.all(
  saids: List<&2, Said>,
  +lines: List<&2, Bool>,
  +closed: List<&2, Closed>,
  +last: U32,
  out: List<&2, Covering>
) -> List<&2, Covering>:
  match saids:
    case Nil{}:
      List.reverse(&2, Covering, out)
    case Con{s, rest}:
      Covering.all(rest, lines, closed, last, Covering.push(Covering.of(s, lines, closed, last), out))

def Covering.pins(action: Action, pinned: Maybe<&2, Severity>, severity: Severity) -> Bool:
  match action:
    case Disable{}:
      True{}
    case Expect{}:
      Severity.same(pinned, Some{severity})

# Whether a covering covers a finding of `rule` and `severity` on line `row`.
def Covering.covers(+rule: String, +severity: Severity, +row: U32, covering: Covering) -> Bool:
  match covering:
    case Covering{Directive{action, scope, r, sev, c, i}, +from, +to}:
      String.eq(r, rule) && U32.is_le(from, row) && U32.is_le(row, to) && Covering.pins(action, sev, severity)

def Covering.hit(hit: Bool, c: Covering, out: List<&2, U32>) -> List<&2, U32>:
  match hit c:
    case True{} Covering{Directive{a, s, r, sev, comment, i}, from, to}:
      i <> out
    case False{} _:
      out

# The indexes of the coverings that cover a finding, onto `out`.
def Covering.hits(coverings: List<&2, Covering>, +rule: String, +severity: Severity, +row: U32, out: List<&2, U32>) ->
  List<&2, U32>:
  match coverings:
    case Nil{}:
      out
    case Con{+c, rest}:
      Covering.hits(rest, rule, severity, row, Covering.hit(Covering.covers(rule, severity, row, c), c, out))

# The line (from 0) of offset `at` of `text`.
def Text.line.go(s: String, +line: U32) -> U32:
  match s:
    case SNil{}:
      line
    case SCon{+c, t}:
      Text.line.go(t, Bool.pick(U32, Char.is_eq(c, '\n'), (line + 1 : U32), line))

def Text.line(text: String, at: U32) -> U32:
  Text.line.go(String.take(text, U32.to_nat(at)), 0)

# The findings so far: those that stay, those a directive covers (both last first), and the directives that covered
# one.
type Applied is Data:
  Applied{kept: List<&2, Found>, suppressed: List<&2, Found>, used: List<&2, U32>}

def Applied.add(hits: List<&2, U32>, found: Found, a: Applied) -> Applied:
  match hits a:
    case Nil{} Applied{kept, suppressed, used}:
      Applied{found <> kept, suppressed, used}
    case Con{h, t} Applied{kept, suppressed, used}:
      Applied{kept, found <> suppressed, List.append(&2, U32, Con{h, t}, used)}

def Applied.go(founds: List<&2, Found>, +coverings: List<&2, Covering>, +text: String, a: Applied) -> Applied:
  match founds:
    case Nil{}:
      a
    case Con{Found{+rule, Finding{+severity, Span{path, +beg, end}, message}}, rest}:
      Applied.go(
        rest,
        coverings,
        text,
        Applied.add(
          Covering.hits(coverings, rule, severity, Text.line(text, beg), []),
          Found{rule, Finding{severity, Span{path, beg, end}, message}},
          a
        )
      )

def Unmet.add(used: Bool, action: Action, rule: String, pinned: Maybe<&2, Severity>, span: Span, out: List<&2, Found>) ->
  List<&2, Found>:
  match used action:
    case True{} _:
      out
    case False{} Expect{}:
      Found{
        "bend-lint/unmet-expectation",
        Finding{
          Error{},
          span,
          "Expected a " ++ rule ++ "@" ++ Maybe.default(&2, String, Maybe.map(&2, Severity, String, Severity.show, pinned), "")
            ++ " finding on the lines this covers; none."
        }
      } <> out
    case False{} Disable{}:
      Found{
        "bend-lint/unused-disable",
        Finding{Warning{}, span, "This disables " ++ rule ++ ", but nothing on the lines it covers needs it."}
      } <> out

# The findings about the directives that nothing used: an expect not met, a disable that covered nothing.
def Unmet.go(coverings: List<&2, Covering>, +used: List<&2, U32>, +path: String, out: List<&2, Found>) -> List<&2, Found>:
  match coverings:
    case Nil{}:
      List.reverse(&2, Found, out)
    case Con{Covering{Directive{a, s, r, sev, Comment{b, e, l, t, body}, +i}, from, to}, rest}:
      Unmet.go(rest, used, path, Unmet.add(List.contains(~U32, ~U32.is_eq, used, i), a, r, sev, Span{path, b, e}, out))

# The key stacked directives are sorted by: rule, then severity, then keyword.
def Directive.key(a: Action, s: Scope, r: String, sev: Maybe<&2, Severity>) -> String:
  r ++ "\t" ++ Maybe.default(&2, String, Maybe.map(&2, Severity, String, Severity.show, sev), "") ++ "\t"
    ++ Action.show(a) ++ "-" ++ Scope.show(s)

# A run of directives on consecutive comment-only lines: where it starts and ends, its last line, its last key, and
# whether it is in order.
type Run is Data:
  Run{beg: U32, end: U32, line: U32, key: String, sorted: Bool}

# The runs so far: the open one, and the findings about the closed ones that are out of order (last first).
type Runs is Data:
  Runs{open: Maybe<&2, Run>, out: List<&2, Found>}

def Runs.close(open: Maybe<&2, Run>, +path: String, out: List<&2, Found>) -> List<&2, Found>:
  match open:
    case Some{Run{beg, end, line, key, False{}}}:
      Found{
        "bend-lint/directive",
        Finding{Error{}, Span{path, beg, end}, "Directives that stack must be in order: by rule, then severity, then keyword."}
      } <> out
    case _:
      out

def Runs.start(+b: U32, +e: U32, +l: U32, key: String) -> Run:
  Run{b, e, l, key, True{}}

def Runs.extend(continues: Bool, run: Run, comment: Comment, +key: String, +path: String, out: List<&2, Found>) -> Runs:
  match continues run comment:
    case True{} Run{beg, end, line, +last, sorted} Comment{b, e, l, t, body}:
      Runs{Some{Run{beg, e, l, key, sorted && String.is_le(last, key)}}, out}
    case False{} _ Comment{b, e, l, t, body}:
      Runs{Some{Runs.start(b, e, l, key)}, Runs.close(Some{run}, path, out)}

def Runs.step(said: Said, +path: String, runs: Runs) -> Runs:
  match said runs:
    case Said{Directive{a, s, r, sev, Comment{b, e, +l, False{}, body}, i}} Runs{Some{Run{rb, re, +rl, rk, rs}}, out}:
      Runs.extend(
        U32.is_eq(l, (rl + 1 : U32)),
        Run{rb, re, rl, rk, rs},
        Comment{b, e, l, False{}, body},
        Directive.key(a, s, r, sev),
        path,
        out
      )
    case Said{Directive{a, s, r, sev, Comment{+b, +e, +l, False{}, body}, i}} Runs{None{}, out}:
      Runs{Some{Runs.start(b, e, l, Directive.key(a, s, r, sev))}, out}
    case _ _:
      runs

def Runs.go(saids: List<&2, Said>, +path: String, runs: Runs) -> List<&2, Found>:
  match saids runs:
    case Nil{} Runs{open, out}:
      List.reverse(&2, Found, Runs.close(open, path, out))
    case Con{s, rest} _:
      Runs.go(rest, path, Runs.step(s, path, runs))

# What is wrong with the directives, in order, as findings.
def Wrong.found(saids: List<&2, Said>, +path: String, out: List<&2, Found>) -> List<&2, Found>:
  match saids:
    case Nil{}:
      List.reverse(&2, Found, out)
    case Con{Wrong{Comment{b, e, l, t, body}, why}, rest}:
      Wrong.found(rest, path, Found{"bend-lint/directive", Finding{Error{}, Span{path, b, e}, why}} <> out)
    case Con{s, rest}:
      Wrong.found(rest, path, out)

# A file's findings after its directives: those that stay, then the findings about its directives, and those a
# directive covers.
type Suppressed is Data:
  Suppressed{kept: List<&2, Found>, suppressed: List<&2, Found>}

def Directives.done(
  a: Applied,
  +coverings: List<&2, Covering>,
  unpaired: List<&2, Said>,
  +saids: List<&2, Said>,
  +path: String
) -> Suppressed:
  match a:
    case Applied{kept, suppressed, used}:
      Suppressed{
        List.concat(
          &2,
          Found,
          [
            List.reverse(&2, Found, kept),
            Wrong.found(saids, path, []),
            Wrong.found(List.reverse(&2, Said, unpaired), path, []),
            Runs.go(saids, path, Runs{None{}, []}),
            Unmet.go(coverings, used, path, [])
          ]
        ),
        List.reverse(&2, Found, suppressed)
      }

def Directives.covered(
  +coverings: List<&2, Covering>,
  unpaired: List<&2, Said>,
  +saids: List<&2, Said>,
  +path: String,
  +text: String,
  founds: List<&2, Found>
) -> Suppressed:
  Directives.done(Applied.go(founds, coverings, text, Applied{[], [], []}), coverings, unpaired, saids, path)

def Directives.paired(
  p: Pairing,
  +saids: List<&2, Said>,
  +lines: List<&2, Bool>,
  +path: String,
  +text: String,
  founds: List<&2, Found>
) -> Suppressed:
  match p:
    case Pairing{open, closed, wrong}:
      Directives.covered(
        Covering.all(saids, lines, closed, (U32.from_nat(List.length(&2, Bool, lines)) - 1 : U32), []),
        Pairing.unclosed(open, wrong),
        saids,
        path,
        text,
        founds
      )

def Directives.read(
  +saids: List<&2, Said>,
  +lines: List<&2, Bool>,
  +path: String,
  +text: String,
  founds: List<&2, Found>
) -> Suppressed:
  Directives.paired(Pairing.go(saids, Pairing{[], [], []}), saids, lines, path, text, founds)

def Directives.scanned(scanned: Scanned, +known: List<&2, String>, +path: String, +text: String, founds: List<&2, Found>) ->
  Suppressed:
  match scanned:
    case Scanned{comments, +lines}:
      Directives.read(Said.all(comments, known, 0, []), lines, path, text, founds)

def Directives.when(has: Bool, +known: List<&2, String>, +path: String, +text: String, founds: List<&2, Found>) -> Suppressed:
  match has:
    case True{}:
      Directives.scanned(Scan.of(text), known, path, text, founds)
    case False{}:
      Suppressed{founds, []}

# A file's findings after the directives of its text: `known` are the ids of the rules there are.
def Directives.apply(+known: List<&2, String>, +path: String, +text: String, founds: List<&2, Found>) -> Suppressed:
  Directives.when(String.contains(text, "bend-lint:"), known, path, text, founds)

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

# Rules dealt into two halves of about the same size, one at a time.
def Rule.deal(rules: List<&1, Rule>, a: List<&1, Rule>, b: List<&1, Rule>) -> List<&1, Rule> & List<&1, Rule>:
  match rules:
    case Nil{}:
      (a, b)
    case Con{r, rest}:
      Rule.deal(rest, b, r <> a)

# What the rules of both halves find on `here`, in order: each half in parallel, dealt again until `depth` runs out.
# A half's findings come in its rules' order; the halves interleave the rules, so the order is the halves'.
def Rule.run_all(+depth: Nat, halves: List<&1, Rule> & List<&1, Rule>, +here: Here) -> List<&2, Found>:
  match depth halves:
    case 0n Tuple{a, b}:
      List.reverse(&2, Found, Rule.run_each(b, here, Rule.run_each(a, here, [])))
    case 1n+d Tuple{a, b}:
      x y = Rule.run_all(d, Rule.deal(a, [], []), here) Rule.run_all(d, Rule.deal(b, [], []), here)
      List.append(&2, Found, x, y)

# The file the check was for: the last it parsed, as its imports come first.
def Program.root(sources: List<&2, Source>, last: Maybe<&2, Source>) -> Maybe<&2, Source>:
  match sources:
    case Nil{}:
      last
    case Con{s, rest}:
      Program.root(rest, Some{s})

# Output
# ======

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
      List.reverse(&2, String, out)
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

# The summary line: how many findings stay, and how many directives suppressed.
def cli.summary(n: Nat, suppressed: Nat) -> String:
  match suppressed:
    case 0n:
      "bend-lint: " ++ Nat.show(n) ++ " finding(s)"
    case _:
      "bend-lint: " ++ Nat.show(n) ++ " finding(s), " ++ Nat.show(suppressed) ++ " suppressed"

def cli.end(failed: Bool, summary: String) -> IO(Unit):
  match failed:
    case True{}:
      IO.die(Unit, 1, "bend-lint: FAIL")
    case False{}:
      IO.print(summary)

# Prints the findings that stay, of the file whose text is `text`; fails if one is an error.
def cli.print(+text: String, found: Suppressed) -> IO(Unit):
  match found:
    case Suppressed{+kept, suppressed}:
      do IO<Unit>:
        cli.say(Found.lines(text, kept, []))
        cli.end(
          Found.any_error(kept, False{}),
          cli.summary(List.length(&2, Found, kept), List.length(&2, Found, suppressed))
        )

# The ids of the rules, in order.
def Rule.ids(rules: List<&1, Rule>, out: List<&2, String>) -> List<&2, String>:
  match rules:
    case Nil{}:
      List.reverse(&2, String, out)
    case Con{Rule{id, run}, rest}:
      Rule.ids(rest, id <> out)

def cli.lint(~rules: List<&1, Rule>, +program: Program, root: Maybe<&2, Source>) -> IO(Unit):
  match root:
    case Some{Source{+path, namespace, +text, nodes}}:
      cli.print(
        text,
        Directives.apply(
          Rule.ids(rules, []),
          path,
          text,
          Rule.run_all(4n, Rule.deal(rules, [], []), Here.of(program, Source{path, namespace, text, nodes}))
        )
      )
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
