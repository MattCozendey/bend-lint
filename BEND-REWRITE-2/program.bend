# The program a check gives: decoded from the server's answer, and each file's declarations with their uses.
import Base
import ./lint.bend as Lint
import ./shared.bend as Shared
import ./wire.bend as Wire

# Why a check failed: Bend's message, and where, if Bend says: the span, and the text of its file.
type Failure is Data:
  Failure{message: String, at: Maybe<&2, Lint.Span>, text: String}

# What checking a file gives: its program, and the check's number on the server; or why the check failed, the files it
# read, and, if it parsed them, the program they make, without facts.
type Check is Data:
  Passed{program: Lint.Program, check: U32}
  Failed{failure: Failure, read: List<&2, String>, parsed: Maybe<&2, Lint.Program>}

# Decoding
# ========

def Syntax.names() -> List<&2, Shared.Named<Lint.Syntax>>:
  [
    Shared.Named{"Variable", Lint.Variable{}},
    Shared.Named{"Reference", Lint.Reference{}},
    Shared.Named{"Application", Lint.Application{}},
    Shared.Named{"Lambda", Lint.Lambda{}},
    Shared.Named{"Literal", Lint.Literal{}},
    Shared.Named{"Construction", Lint.Construction{}},
    Shared.Named{"PatternVariable", Lint.PatternVariable{}},
    Shared.Named{"PatternConstructor", Lint.PatternConstructor{}},
    Shared.Named{"Forall", Lint.Forall{}},
    Shared.Named{"Annotation", Lint.Annotation{}},
    Shared.Named{"Match", Lint.Match{}},
    Shared.Named{"Case", Lint.Case{}},
    Shared.Named{"Destructure", Lint.Destructure{}},
    Shared.Named{"Let", Lint.Let{}},
    Shared.Named{"Binding", Lint.Binding{}},
    Shared.Named{"Parameter", Lint.Parameter{}},
    Shared.Named{"Field", Lint.Field{}},
    Shared.Named{"Returns", Lint.Returns{}},
    Shared.Named{"Body", Lint.Body{}},
    Shared.Named{"Definition", Lint.Definition{}},
    Shared.Named{"Datatype", Lint.Datatype{}},
    Shared.Named{"Constructor", Lint.Constructor{}},
    Shared.Named{"Law", Lint.Law{}},
    Shared.Named{"Import", Lint.Import{}},
    Shared.Named{"ImportPath", Lint.ImportPath{}},
    Shared.Named{"Substitution", Lint.Substitution{}},
    Shared.Named{"Sort", Lint.Sort{}},
    Shared.Named{"QuantityType", Lint.QuantityType{}},
    Shared.Named{"QuantityLiteral", Lint.QuantityLiteral{}},
    Shared.Named{"QuantityMinimum", Lint.QuantityMinimum{}},
    Shared.Named{"TypeApplication", Lint.TypeApplication{}},
    Shared.Named{"Elimination", Lint.Elimination{}},
    Shared.Named{"Absurd", Lint.Absurd{}},
    Shared.Named{"Equality", Lint.Equality{}},
    Shared.Named{"Reflexivity", Lint.Reflexivity{}},
    Shared.Named{"Rewrite", Lint.Rewrite{}},
    Shared.Named{"Hole", Lint.Hole{}}
  ]

def Quantity.names() -> List<&2, Shared.Named<Lint.Quantity>>:
  [
    Shared.Named{"Once", Lint.Once{}},
    Shared.Named{"Many", Lint.Many{}},
    Shared.Named{"Erased", Lint.Erased{}},
    Shared.Named{"Template", Lint.Template{}}
  ]

def Span.read(path: String, beg: String, end: String) -> Maybe<&2, Lint.Span>:
  do Maybe<&2, Lint.Span>:
    b : U32 <- U32.read(beg)
    e : U32 <- U32.read(end)
    return Lint.Span{path, b, e}

# A node from the fields of its record, in the file at `path`.
def Node.read(path: String, fields: List<&2, String>) -> Maybe<&2, Lint.Node>:
  match fields:
    case Con{id, Con{parent, Con{owner, Con{syntax, Con{name, Con{binder, Con{quantity, Con{beg, Con{end, Con{target, Nil{}}}}}}}}}}}:
      do Maybe<&2, Lint.Node>:
        i : U32 <- U32.read(id)
        p : U32 <- U32.read(parent)
        o : U32 <- U32.read(owner)
        s : Lint.Syntax <- Shared.lookup(Lint.Syntax, syntax, Syntax.names())
        return Lint.Node{
          i,
          p,
          o,
          s,
          name,
          U32.read(binder),
          Shared.lookup(Lint.Quantity, quantity, Quantity.names()),
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

def Record.names() -> List<&2, Shared.Named<Record>>:
  [Shared.Named{"node", NodeRecord{}}, Shared.Named{"fact", FactRecord{}}, Shared.Named{"file", SourceRecord{}}]

def Role.names() -> List<&2, Shared.Named<Lint.Role>>:
  [Shared.Named{"term", Lint.OfTerm{}}, Shared.Named{"binder", Lint.OfBinder{}}]

# A fact on `node` from the fields of its record: its role, the check and handle of its type, and its quantity.
def Fact.read(node: Lint.Node, fields: List<&2, String>) -> Maybe<&2, Lint.Fact>:
  match fields:
    case Con{role, Con{check, Con{id, Con{quantity, Nil{}}}}}:
      do Maybe<&2, Lint.Fact>:
        r : Lint.Role <- Shared.lookup(Lint.Role, role, Role.names())
        c : U32 <- U32.read(check)
        i : U32 <- U32.read(id)
        q : Lint.Quantity <- Shared.lookup(Lint.Quantity, quantity, Quantity.names())
        return Lint.Fact{node, r, q, Lint.TypeRef{c, i}}
    case _:
      None{}

# The sources read so far, last first, each with its nodes and facts last first.
def Program.add(kind: Maybe<&2, Record>, fields: List<&2, String>, sources: List<&2, Lint.Source>) ->
  Maybe<&2, List<&2, Lint.Source>>:
  match kind fields sources:
    case Some{NodeRecord{}} _ Con{Lint.Source{+path, namespace, text, nodes, facts}, rest}:
      do Maybe<&2, List<&2, Lint.Source>>:
        n : Lint.Node <- Node.read(path, fields)
        return Lint.Source{path, namespace, text, n <> nodes, facts} <> rest
    case Some{FactRecord{}} _ Con{Lint.Source{path, namespace, text, Con{+node, nodes}, facts}, rest}:
      do Maybe<&2, List<&2, Lint.Source>>:
        f : Lint.Fact <- Fact.read(node, fields)
        return Lint.Source{path, namespace, text, node <> nodes, f <> facts} <> rest
    case Some{SourceRecord{}} Con{path, Con{namespace, Con{text, Nil{}}}} _:
      Some{Lint.Source{path, namespace, text, [], []} <> sources}
    case _ _ _:
      None{}

# The sources in order, each with its nodes and facts in order.
def Program.in_order(sources: List<&2, Lint.Source>, done: List<&2, Lint.Source>) -> List<&2, Lint.Source>:
  match sources:
    case Nil{}:
      done
    case Con{Lint.Source{path, namespace, text, nodes, facts}, rest}:
      Program.in_order(
        rest,
        Lint.Source{path, namespace, text, List.reverse(&2, Lint.Node, nodes), List.reverse(&2, Lint.Fact, facts)} <> done
      )

# The program of an answer's records: a source record, then its nodes and facts, for each source.
def Program.read(records: List<&2, List<&2, String>>, sources: List<&2, Lint.Source>) -> Maybe<&2, Lint.Program>:
  match records:
    case Nil{}:
      Some{Lint.Program{Program.in_order(sources, [])}}
    case Con{Con{tag, fields}, rest}:
      do Maybe<&2, Lint.Program>:
        added : List<&2, Lint.Source> <- Program.add(Shared.lookup(Record, tag, Record.names()), fields, sources)
        Program.read(rest, added)
    case Con{Nil{}, rest}:
      None{}

def Check.malformed(-A: Type) -> IO(A):
  IO.die(A, 1, "bend-lint: the checker's answer is malformed")

def Check.passed(tagged: Bool, check: Maybe<&2, U32>, program: Maybe<&2, Lint.Program>) -> IO(Check):
  match tagged check program:
    case True{} Some{c} Some{p}:
      IO.pure(Check, Passed{p, c})
    case _ _ _:
      Check.malformed(Check)

# A passed check's answer: its number, then its program.
def Check.read(records: List<&2, List<&2, String>>) -> IO(Check):
  match records:
    case Con{Con{tag, Con{check, Nil{}}}, rest}:
      Check.passed(String.eq(tag, "check"), U32.read(check), Program.read(rest, []))
    case _:
      Check.malformed(Check)

def Records.keep(hit: Bool, record: List<&2, String>, out: List<&2, List<&2, String>>) -> List<&2, List<&2, String>>:
  match hit:
    case True{}:
      record <> out
    case False{}:
      out

# The records of the parsed files and their nodes, in order.
def Records.syntax(records: List<&2, List<&2, String>>, out: List<&2, List<&2, String>>) -> List<&2, List<&2, String>> :
  match records:
    case Nil{}:
      List.reverse(&2, List<&2, String>, out)
    case Con{Con{+tag, fields}, rest}:
      Records.syntax(rest, Records.keep(String.eq(tag, "file") || String.eq(tag, "node"), Con{tag, fields}, out))
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
    case Con{Con{+tag, fields}, rest}:
      Check.reads(rest, Records.path(String.eq(tag, "read"), fields, out))
    case Con{Nil{}, rest}:
      Check.reads(rest, out)

# The program of the files a failed check parsed, if it parsed any.
def Check.parsed(syntax: List<&2, List<&2, String>>) -> Maybe<&2, Lint.Program>:
  match syntax:
    case Nil{}:
      None{}
    case _:
      Program.read(syntax, [])

def Check.failed(fail: Bool, failure: Failure, +records: List<&2, List<&2, String>>) -> IO(Check):
  match fail:
    case True{}:
      IO.pure(Check, Failed{failure, Check.reads(records, []), Check.parsed(Records.syntax(records, []))})
    case False{}:
      Check.malformed(Check)

def Check.ended(last: Maybe<&2, List<&2, String>>, records: List<&2, List<&2, String>>) -> IO(Check):
  match last:
    case Some{Con{+tag, Con{message, Nil{}}}}:
      Check.failed(String.eq(tag, "fail"), Failure{message, None{}, ""}, records)
    case Some{Con{+tag, Con{message, Con{path, Con{beg, Con{end, Con{text, Nil{}}}}}}}}:
      Check.failed(String.eq(tag, "fail"), Failure{message, Span.read(path, beg, end), text}, records)
    case _:
      Check.read(records)

# What an answer says: the check's number and the program; or, ending in a `fail` record, why and where the check
# failed, the files it read (its `read` records), and what it parsed (its `file` and `node` records).
def Check.of(+records: List<&2, List<&2, String>>) -> IO(Check):
  Check.ended(List.last(&2, List<&2, String>, records), records)

# Checks the file at `path`, with the checker's facts if `facts`.
def Check.run(path: String, facts: Bool) -> IO(Check):
  IO.bind(
    List<&2, List<&2, String>>,
    Check,
    Wire.ask(["check", path, Bool.pick(String, facts, "facts", "syntax")]),
    records => Check.of(records)
  )

# Frees what the server holds for the passed check numbered `check`: no rule asks about its types again.
def Check.forget(check: U32) -> IO(Unit):
  IO.bind(List<&2, List<&2, String>>, Unit, Wire.ask(["forget", U32.show(check)]), records => IO.pure(Unit, Unit{}))

# Declarations
# ============

# What a syntax declares: a global name, a binder of its top-level declaration, or nothing (an import declares an
# alias, which Imports below handles).
type Declares is Data:
  DeclaresGlobal{}
  DeclaresBinder{}
  DeclaresNothing{}

def Syntax.declares(syntax: Lint.Syntax) -> Declares:
  match syntax:
    case Lint.Definition{}:
      DeclaresGlobal{}
    case Lint.Datatype{}:
      DeclaresGlobal{}
    case Lint.Constructor{}:
      DeclaresGlobal{}
    case Lint.Law{}:
      DeclaresGlobal{}
    case Lint.Parameter{}:
      DeclaresBinder{}
    case Lint.Field{}:
      DeclaresBinder{}
    case Lint.Binding{}:
      DeclaresBinder{}
    case Lint.Lambda{}:
      DeclaresBinder{}
    case Lint.Forall{}:
      DeclaresBinder{}
    case Lint.PatternVariable{}:
      DeclaresBinder{}
    case _:
      DeclaresNothing{}

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
def Key.declared(node: Lint.Node) -> Maybe<&2, String>:
  match node:
    case Lint.Node{id, parent, owner, syntax, +name, binder, quantity, span, target}:
      Key.declared.of(Syntax.declares(syntax), owner, binder, String.eq(name, "_"), target)

# The key of what a node uses, if it uses a global or a binder.
def Key.used(node: Lint.Node) -> Maybe<&2, String>:
  match node:
    case Lint.Node{id, parent, owner, Lint.Variable{}, name, Some{binder}, quantity, span, target}:
      Some{Key.binder(owner, binder)}
    case _:
      Maybe.map(&2, String, String, Key.global, Lint.Node.used(node))

def Uses.add(m: Map<&2, List<&2, Lint.Node>>, key: Maybe<&2, String>, node: Lint.Node) -> Map<&2, List<&2, Lint.Node>>:
  match key:
    case None{}:
      m
    case Some{k}:
      Shared.Group.add(Lint.Node, m, k, node)

# The uses of each key.
def Uses.of(nodes: List<&2, Lint.Node>, m: Map<&2, List<&2, Lint.Node>>) -> Map<&2, List<&2, Lint.Node>>:
  match nodes:
    case Nil{}:
      m
    case Con{+n, rest}:
      Uses.of(rest, Uses.add(m, Key.used(n), n))

# Imports
# =======

# The namespace of the file at `path`, as the check names it: "" for Base, or a file the check did not parse.
def Imports.namespace(sources: List<&2, Lint.Source>, +path: String) -> String:
  match sources:
    case Nil{}:
      ""
    case Con{Lint.Source{+p, namespace, text, nodes, facts}, rest}:
      Bool.pick(String, String.eq(p, path), namespace, Imports.namespace(rest, path))

# The global names a file's own top-level declarations declare, as a set.
def Imports.own(nodes: List<&2, Lint.Node>, out: Map<&2, Unit>) -> Map<&2, Unit>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{id, 0, owner, syntax, name, binder, quantity, span, target}, rest}:
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
      Imports.base_name(String.is_empty(Lint.Name.namespace(name)), own, name)
    case None{}:
      False{}

def Imports.uses(+importer: Importer, +node: Lint.Node) -> Bool:
  match importer node:
    case ByAlias{+prefix} Lint.Node{id, parent, owner, syntax, name, binder, quantity, span, target}:
      String.starts_with(name, prefix)
    case ByBase{+own} _:
      Imports.base_uses(own, Lint.Node.used(node))

def Imports.keep(hit: Bool, n: Lint.Node, out: List<&2, Lint.Node>) -> List<&2, Lint.Node>:
  match hit:
    case True{}:
      n <> out
    case False{}:
      out

# The nodes of `nodes` that use an import, in order; `out` holds those so far, last first.
def Imports.references(nodes: List<&2, Lint.Node>, +importer: Importer, out: List<&2, Lint.Node>) -> List<&2, Lint.Node>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Lint.Node, out)
    case Con{+n, rest}:
      Imports.references(rest, importer, Imports.keep(Imports.uses(importer, n), n, out))

def Imports.importer(base: Bool, alias: String, +nodes: List<&2, Lint.Node>) -> Importer:
  match base:
    case True{}:
      ByBase{Imports.own(nodes, Map.new(&2, Unit))}
    case False{}:
      ByAlias{alias ++ "."}

# A node's declaration, if it declares a name, with its uses among `nodes`: `uses` indexes them, `sources` says which
# import loads Base.
def Declarations.of.node(
  +sources: List<&2, Lint.Source>,
  +nodes: List<&2, Lint.Node>,
  +uses: Map<&2, List<&2, Lint.Node>>,
  node: Lint.Node
) -> Maybe<&2, Lint.Declaration>:
  match node:
    case Lint.Node{id, parent, owner, Lint.Import{}, +name, binder, quantity, span, +target}:
      Some{
        Lint.Declaration{
          Lint.Node{id, parent, owner, Lint.Import{}, name, binder, quantity, span, target},
          Imports.references(
            nodes,
            Imports.importer(String.is_empty(Imports.namespace(sources, target)), name, nodes),
            []
          )
        }
      }
    case +n:
      Maybe.map(&2, String, Lint.Declaration, k => Lint.Declaration{n, Shared.Group.get(Lint.Node, uses, k)}, Key.declared(n))

def Declarations.of.go(
  rest: List<&2, Lint.Node>,
  +sources: List<&2, Lint.Source>,
  +nodes: List<&2, Lint.Node>,
  +uses: Map<&2, List<&2, Lint.Node>>,
  out: List<&2, Lint.Declaration>
) -> List<&2, Lint.Declaration>:
  match rest:
    case Nil{}:
      List.reverse(&2, Lint.Declaration, out)
    case Con{n, more}:
      Declarations.of.go(
        more,
        sources,
        nodes,
        uses,
        Shared.push(Lint.Declaration, Declarations.of.node(sources, nodes, uses, n), out)
      )

# The declarations of a file's nodes, in order, with their uses that `uses` indexes.
def Declarations.of(+sources: List<&2, Lint.Source>, +nodes: List<&2, Lint.Node>, +uses: Map<&2, List<&2, Lint.Node>>) ->
  List<&2, Lint.Declaration>:
  Declarations.of.go(nodes, sources, nodes, uses, [])

def Index.first(nodes: List<&2, Lint.Node>) -> U32:
  match nodes:
    case Con{Lint.Node{id, p, o, s, n, b, q, sp, t}, rest}:
      id
    case Nil{}:
      0

# A file's nodes by id: their ids are consecutive, so the id less the first is a node's number.
def Index.of(+nodes: List<&2, Lint.Node>) -> Lint.Index:
  Lint.Index{
    Index.first(nodes),
    Shared.Table.of(Lint.Node, U32.from_nat(Shared.length(&2, Lint.Node, nodes)), nodes)
  }

# The program from one of its files, built once for every file rule that runs on that file: references from it alone.
# The runner gives each rule its options.
def Here.of(program: Lint.Program, source: Lint.Source) -> Lint.Here:
  match program source:
    case Lint.Program{+sources} Lint.Source{path, namespace, text, +nodes, +facts}:
      Lint.Here{
        Lint.Program{sources},
        Lint.Source{path, namespace, text, nodes, facts},
        Declarations.of(sources, nodes, Uses.of(nodes, Map.new(&2, List<&2, Lint.Node>))),
        Index.of(nodes),
        []
      }

# Whether a file is the program's own: not of a hub package.
def Source.own(source: Lint.Source) -> Bool:
  match source:
    case Lint.Source{path, namespace, text, nodes, facts}:
      Bool.not(String.starts_with(namespace, "0x"))

# The program's own files, hub packages aside.
def Program.own(sources: List<&2, Lint.Source>) -> List<&2, Lint.Source>:
  List.filter(~Lint.Source, ~Source.own, sources)

# The nodes of every file, in order.
def Program.nodes(sources: List<&2, Lint.Source>, out: List<&2, List<&2, Lint.Node>>) -> List<&2, Lint.Node>:
  match sources:
    case Nil{}:
      Shared.concat(&2, Lint.Node, List.reverse(&2, List<&2, Lint.Node>, out))
    case Con{Lint.Source{path, namespace, text, nodes, facts}, rest}:
      Program.nodes(rest, nodes <> out)

# The declarations of every file, in order, with their uses that `uses` indexes; `files` are those left to read.
def Whole.declarations(
  files: List<&2, Lint.Source>,
  +sources: List<&2, Lint.Source>,
  +uses: Map<&2, List<&2, Lint.Node>>,
  out: List<&2, List<&2, Lint.Declaration>>
) -> List<&2, Lint.Declaration>:
  match files:
    case Nil{}:
      Shared.concat(&2, Lint.Declaration, List.reverse(&2, List<&2, Lint.Declaration>, out))
    case Con{Lint.Source{path, namespace, text, nodes, facts}, rest}:
      Whole.declarations(rest, sources, uses, Declarations.of(sources, nodes, uses) <> out)

def Whole.from(+sources: List<&2, Lint.Source>) -> Lint.Whole:
  Lint.Whole{
    Lint.Program{sources},
    Whole.declarations(sources, sources, Uses.of(Program.nodes(sources, []), Map.new(&2, List<&2, Lint.Node>)), []),
    []
  }

# The whole program, built once for every program rule: references from all its own files.
def Whole.of(program: Lint.Program) -> Lint.Whole:
  match program:
    case Lint.Program{sources}:
      Whole.from(Program.own(sources))
