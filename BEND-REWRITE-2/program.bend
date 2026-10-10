# The program a check gives: decoded from the server's answer, and each file's declarations with their uses.
import Base
import ./lint.bend as Lint
import ./shared.bend as Shared
import ./wire.bend as Wire

# What checking a file gives: its program, or why the check failed and the files it read.
type Check is Data:
  Passed{program: Lint.Program}
  Failed{message: String, read: List<&2, String>}

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

# The sources read so far, last first, each with its nodes last first. A node record adds to the latest source; a
# source record starts one.
def Program.add(is_node: Bool, fields: List<&2, String>, sources: List<&2, Lint.Source>) -> Maybe<&2, List<&2, Lint.Source>>:
  match is_node fields sources:
    case True{} _ Con{Lint.Source{+path, namespace, text, nodes}, rest}:
      do Maybe<&2, List<&2, Lint.Source>>:
        n : Lint.Node <- Node.read(path, fields)
        return Lint.Source{path, namespace, text, n <> nodes} <> rest
    case False{} Con{path, Con{namespace, Con{text, Nil{}}}} _:
      Some{Lint.Source{path, namespace, text, []} <> sources}
    case _ _ _:
      None{}

# The sources in order, each with its nodes in order.
def Program.in_order(sources: List<&2, Lint.Source>, done: List<&2, Lint.Source>) -> List<&2, Lint.Source>:
  match sources:
    case Nil{}:
      done
    case Con{Lint.Source{path, namespace, text, nodes}, rest}:
      Program.in_order(rest, Lint.Source{path, namespace, text, List.reverse(&2, Lint.Node, nodes)} <> done)

# The program of an answer's records: a source record, then its nodes, for each source.
def Program.read(records: List<&2, List<&2, String>>, sources: List<&2, Lint.Source>) -> Maybe<&2, Lint.Program>:
  match records:
    case Nil{}:
      Some{Lint.Program{Program.in_order(sources, [])}}
    case Con{Con{+tag, fields}, rest}:
      do Maybe<&2, Lint.Program>:
        added : List<&2, Lint.Source> <- Program.add(String.eq(tag, "node"), fields, sources)
        Program.read(rest, added)
    case Con{Nil{}, rest}:
      None{}

def Check.malformed(-A: Type) -> IO(A):
  IO.die(A, 1, "bend-lint: the checker's answer is malformed")

def Check.read(program: Maybe<&2, Lint.Program>) -> IO(Check):
  match program:
    case Some{p}:
      IO.pure(Check, Passed{p})
    case None{}:
      Check.malformed(Check)

# The files a failed check read: the paths of its `read` records, in order.
def Check.reads(records: List<&2, List<&2, String>>, out: List<&2, String>) -> List<&2, String>:
  match records:
    case Nil{}:
      List.reverse(&2, String, out)
    case Con{Con{tag, Con{path, Nil{}}}, rest}:
      Check.reads(rest, path <> out)
    case Con{r, rest}:
      Check.reads(rest, out)

def Check.failed(fail: Bool, message: String, read: List<&2, String>) -> IO(Check):
  match fail:
    case True{}:
      IO.pure(Check, Failed{message, read})
    case False{}:
      Check.malformed(Check)

def Check.ended(last: Maybe<&2, List<&2, String>>, records: List<&2, List<&2, String>>) -> IO(Check):
  match last:
    case Some{Con{+tag, Con{message, Nil{}}}}:
      Check.failed(String.eq(tag, "fail"), message, Check.reads(records, []))
    case _:
      Check.read(Program.read(records, []))

# What an answer says: the program; or, ending in a `fail` record, the files the check read (its `read` records) and
# why it failed.
def Check.of(+records: List<&2, List<&2, String>>) -> IO(Check):
  Check.ended(List.last(&2, List<&2, String>, records), records)

# Checks the file at `path`.
def Check.run(path: String) -> IO(Check):
  IO.bind(List<&2, List<&2, String>>, Check, Wire.ask(["check", path]), records => Check.of(records))

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

# The uses of each key, last first.
def Uses.push(got: Map<&2, List<&2, Lint.Node>> & List<&2, Lint.Node>, key: String, node: Lint.Node) ->
  Map<&2, List<&2, Lint.Node>>:
  match got:
    case Tuple{m, old}:
      Map.set(&2, List<&2, Lint.Node>, m, key, node <> old)

def Uses.add(m: Map<&2, List<&2, Lint.Node>>, key: Maybe<&2, String>, node: Lint.Node) -> Map<&2, List<&2, Lint.Node>>:
  match key:
    case None{}:
      m
    case Some{+k}:
      Uses.push(Map.get(List<&2, Lint.Node>, [], m, k), k, node)

def Uses.of(nodes: List<&2, Lint.Node>, m: Map<&2, List<&2, Lint.Node>>) -> Map<&2, List<&2, Lint.Node>>:
  match nodes:
    case Nil{}:
      m
    case Con{+n, rest}:
      Uses.of(rest, Uses.add(m, Key.used(n), n))

def Uses.found(got: Map<&2, List<&2, Lint.Node>> & List<&2, Lint.Node>) -> List<&2, Lint.Node>:
  match got:
    case Tuple{m, found}:
      List.reverse(&2, Lint.Node, found)

# The uses of `key`, in order.
def Uses.get(+uses: Map<&2, List<&2, Lint.Node>>, key: String) -> List<&2, Lint.Node>:
  Uses.found(Map.get(List<&2, Lint.Node>, [], uses, key))

# Imports
# =======

# The namespace of the file at `path`, as the check names it: "" for Base, or a file the check did not parse.
def Imports.namespace(sources: List<&2, Lint.Source>, +path: String) -> String:
  match sources:
    case Nil{}:
      ""
    case Con{Lint.Source{+p, namespace, text, nodes}, rest}:
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
      Maybe.map(&2, String, Lint.Declaration, k => Lint.Declaration{n, Uses.get(uses, k)}, Key.declared(n))

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

# The program from one of its files, built once for every file rule that runs on that file: references from it alone.
def Here.of(program: Lint.Program, source: Lint.Source) -> Lint.Here:
  match program source:
    case Lint.Program{+sources} Lint.Source{path, namespace, text, +nodes}:
      Lint.Here{
        Lint.Program{sources},
        Lint.Source{path, namespace, text, nodes},
        Declarations.of(sources, nodes, Uses.of(nodes, Map.new(&2, List<&2, Lint.Node>)))
      }

# Whether a file is the program's own: not of a hub package.
def Source.own(source: Lint.Source) -> Bool:
  match source:
    case Lint.Source{path, namespace, text, nodes}:
      Bool.not(String.starts_with(namespace, "0x"))

# The program's own files, hub packages aside.
def Program.own(sources: List<&2, Lint.Source>) -> List<&2, Lint.Source>:
  List.filter(~Lint.Source, ~Source.own, sources)

# The nodes of every file, in order.
def Program.nodes(sources: List<&2, Lint.Source>, out: List<&2, List<&2, Lint.Node>>) -> List<&2, Lint.Node>:
  match sources:
    case Nil{}:
      List.concat(&2, Lint.Node, List.reverse(&2, List<&2, Lint.Node>, out))
    case Con{Lint.Source{path, namespace, text, nodes}, rest}:
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
      List.concat(&2, Lint.Declaration, List.reverse(&2, List<&2, Lint.Declaration>, out))
    case Con{Lint.Source{path, namespace, text, nodes}, rest}:
      Whole.declarations(rest, sources, uses, Declarations.of(sources, nodes, uses) <> out)

def Whole.from(+sources: List<&2, Lint.Source>) -> Lint.Whole:
  Lint.Whole{
    Lint.Program{sources},
    Whole.declarations(sources, sources, Uses.of(Program.nodes(sources, []), Map.new(&2, List<&2, Lint.Node>)), [])
  }

# The whole program, built once for every program rule: references from all its own files.
def Whole.of(program: Lint.Program) -> Lint.Whole:
  match program:
    case Lint.Program{sources}:
      Whole.from(Program.own(sources))
