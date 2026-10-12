# The program a check gives, and each file's declarations with their uses.
import Base
import ../shared/utils.bend as Utils
import ./lint.bend as Lint

# Why a check failed: Bend's message, and where, if Bend says: the span, and the text of its file.
type Failure is Data:
  Failure{message: String, at: Maybe<&2, Lint.Span>, text: String}

# What checking a file gives: its program, and the check's number on the server; or why the check failed, the files it
# read, and, if it parsed them, the program they make, without facts.
type Check is Data:
  Passed{program: Lint.Program, check: U32}
  Failed{failure: Failure, read: List<&2, String>, parsed: Maybe<&2, Lint.Program>}

# Declarations
# ============

# The key that ties a use to what it uses: "g" and a global name, or "l", a top-level declaration's id and a binder.
def Key.global(name: String) -> String:
  "g" ++ name

def Key.binder(owner: U32, binder: U32) -> String:
  "l" ++ U32.show(owner) ++ ":" ++ U32.show(binder)

# Whether a syntax declares a global name (Some{True{}}), a binder of its top-level declaration (Some{False{}}), or
# nothing (an import declares an alias, which Imports below handles).
def Syntax.declares(syntax: Lint.Syntax) -> Maybe<&2, Bool>:
  match syntax:
    case Lint.Definition{}:
      Some{True{}}
    case Lint.Datatype{}:
      Some{True{}}
    case Lint.Constructor{}:
      Some{True{}}
    case Lint.Law{}:
      Some{True{}}
    case Lint.Parameter{}:
      Some{False{}}
    case Lint.Field{}:
      Some{False{}}
    case Lint.Binding{}:
      Some{False{}}
    case Lint.Lambda{}:
      Some{False{}}
    case Lint.Forall{}:
      Some{False{}}
    case Lint.PatternVariable{}:
      Some{False{}}
    case _:
      None{}

def Key.declared.of(
  global: Maybe<&2, Bool>,
  owner: U32,
  binder: Maybe<&2, U32>,
  anonymous: Bool,
  target: String
) -> Maybe<&2, String>:
  match global binder anonymous:
    case Some{True{}} _ _:
      Some{Key.global(target)}
    case Some{False{}} Some{b} False{}:
      Some{Key.binder(owner, b)}
    case _ _ _:
      None{}

# The key of what a node declares, if it declares a global or a named binder.
def Key.declared(node: Lint.Node) -> Maybe<&2, String>:
  match node:
    case Lint.Node{id, parent, owner, syntax, name, binder, quantity, span, target}:
      Key.declared.of(Syntax.declares(syntax), owner, binder, String.eq(name, "_"), target)

# The key of what a node uses, if it uses a global or a binder.
def Key.used(node: Lint.Node) -> Maybe<&2, String>:
  match node:
    case Lint.Node{id, parent, owner, Lint.Variable{}, name, Some{binder}, quantity, span, target}:
      Some{Key.binder(owner, binder)}
    case _:
      Maybe.map(&2, String, String, Key.global, Lint.Node.used(node))

def Uses.add(
  m: Map<&2, List<&2, Lint.Node>>,
  key: Maybe<&2, String>,
  node: Lint.Node
) -> Map<&2, List<&2, Lint.Node>>:
  match key:
    case None{}:
      m
    case Some{k}:
      Utils.Group.add(Lint.Node, m, k, node)

def Uses.of(
  nodes: List<&2, Lint.Node>,
  m: Map<&2, List<&2, Lint.Node>>
) -> Map<&2, List<&2, Lint.Node>>:
  match nodes:
    case Nil{}:
      m
    case Con{+n, rest}:
      Uses.of(rest, Uses.add(m, Key.used(n), n))

# Imports
# =======

# The namespace of the file at `path`, as the check names it: "" for Base, or a file the check did not parse.
def Imports.namespace(
  sources: List<&2, Lint.Source>,
  found: Maybe<&2, String>,
  +path: String
) -> String:
  match sources found:
    case _ Some{namespace}:
      namespace
    case Nil{} None{}:
      ""
    case Con{Lint.Source{p, namespace, text, nodes, facts}, rest} None{}:
      Imports.namespace(rest, Utils.when(String, String.eq(p, path), namespace), path)

# The global names a file's own top-level declarations declare, as a set.
def Imports.own(nodes: List<&2, Lint.Node>, out: Map<&2, Unit>) -> Map<&2, Unit>:
  match nodes:
    case Nil{}:
      out
    case Con{Lint.Node{id, 0, owner, syntax, name, binder, quantity, span, target}, rest}:
      Imports.own(rest, Map.set(&2, Unit, out, target, Unit{}))
    case Con{n, rest}:
      Imports.own(rest, out)

# What uses a file's imports, found in one pass over its nodes: the nodes written with an alias's prefix (`U.two`, a
# fill `def U.law(x):`), by alias; and those that use Base: a global name with no namespace that the file does not
# declare (last first).
type ImportUses is Data:
  ImportUses{aliases: Map<&2, List<&2, Lint.Node>>, base: List<&2, Lint.Node>}

def Imports.not_own(got: Map<&2, Unit> & Bool) -> Bool:
  match got:
    case Tuple{m, has}:
      Bool.not(has)

def Imports.base_name(bare: Bool, own: Map<&2, Unit>, name: String) -> Bool:
  match bare:
    case True{}:
      Imports.not_own(Map.has(&2, Unit, own, name))
    case False{}:
      False{}

def Imports.base_uses(own: Map<&2, Unit>, used: Maybe<&2, String>) -> Bool:
  match used:
    case Some{+name}:
      Imports.base_name(String.is_empty(Lint.Name.namespace(name)), own, name)
    case None{}:
      False{}

# `aliases` with `node`, under `prefix`, the part of its name before the first `.`, if any.
def Imports.alias(
  prefix: String,
  node: Lint.Node,
  aliases: Map<&2, List<&2, Lint.Node>>
) -> Map<&2, List<&2, Lint.Node>>:
  match prefix:
    case SNil{}:
      aliases
    case SCon{h, t}:
      Utils.Group.add(Lint.Node, aliases, SCon{h, t}, node)

def Imports.base(hit: Bool, node: Lint.Node, base: List<&2, Lint.Node>) -> List<&2, Lint.Node>:
  match hit:
    case True{}:
      node <> base
    case False{}:
      base

def Imports.add(own: Map<&2, Unit>, node: Lint.Node, uses: ImportUses) -> ImportUses:
  match node uses:
    case Lint.Node{
      id,
      parent,
      owner,
      syntax,
      +name,
      binder,
      quantity,
      span,
      target
    } ImportUses{aliases, base}:
      +n = {Lint.Node{id, parent, owner, syntax, name, binder, quantity, span, target}: Lint.Node}
      ImportUses{
        Imports.alias(Utils.before(name, '.'), n, aliases),
        Imports.base(Imports.base_uses(own, Lint.Node.used(n)), n, base)
      }

def Imports.scan(nodes: List<&2, Lint.Node>, +own: Map<&2, Unit>, uses: ImportUses) -> ImportUses:
  match nodes:
    case Nil{}:
      uses
    case Con{n, rest}:
      Imports.scan(rest, own, Imports.add(own, n, uses))

def Imports.uses_of(+nodes: List<&2, Lint.Node>) -> ImportUses:
  Imports.scan(
    nodes,
    Imports.own(nodes, Map.new(&2, Unit)),
    ImportUses{Map.new(&2, List<&2, Lint.Node>), []}
  )

# The uses of an import, in order: of Base (`base`), or of the alias `alias`.
def Imports.of(base: Bool, alias: String, imports: ImportUses) -> List<&2, Lint.Node>:
  match base imports:
    case True{} ImportUses{aliases, uses}:
      List.reverse(&2, Lint.Node, uses)
    case False{} ImportUses{aliases, uses}:
      Utils.Group.get(Lint.Node, aliases, alias)

# A node's declaration, if it declares a name, with its uses: `uses` indexes them, and `imports` the uses of the file's
# imports; `sources` says which import loads Base.
def Declarations.of.node(
  sources: List<&2, Lint.Source>,
  imports: ImportUses,
  uses: Map<&2, List<&2, Lint.Node>>,
  node: Lint.Node
) -> Maybe<&2, Lint.Declaration>:
  match node:
    case Lint.Node{id, parent, owner, Lint.Import{}, +name, binder, quantity, span, +target}:
      Some{
        Lint.Declaration{
          Lint.Node{id, parent, owner, Lint.Import{}, name, binder, quantity, span, target},
          Imports.of(String.is_empty(Imports.namespace(sources, None{}, target)), name, imports)
        }
      }
    case +n:
      Maybe.map(
        &2,
        String,
        Lint.Declaration,
        k => Lint.Declaration{n, Utils.Group.get(Lint.Node, uses, k)},
        Key.declared(n)
      )

def Declarations.of.go(
  rest: List<&2, Lint.Node>,
  +sources: List<&2, Lint.Source>,
  +imports: ImportUses,
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
        imports,
        uses,
        Utils.push(Lint.Declaration, Declarations.of.node(sources, imports, uses, n), out)
      )

# The declarations of a file's nodes, in order, with their uses that `uses` indexes.
def Declarations.of(
  sources: List<&2, Lint.Source>,
  +nodes: List<&2, Lint.Node>,
  uses: Map<&2, List<&2, Lint.Node>>
) -> List<&2, Lint.Declaration>:
  Declarations.of.go(nodes, sources, Imports.uses_of(nodes), uses, [])

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
    Utils.Table.of(Lint.Node, U32.from_nat(Utils.length(&2, Lint.Node, nodes)), nodes)
  }

# A file's declarations, with their uses in it, if a rule needs them (`declare`); else none.
def Declarations.when(
  declare: Bool,
  sources: List<&2, Lint.Source>,
  +nodes: List<&2, Lint.Node>
) -> List<&2, Lint.Declaration>:
  match declare:
    case True{}:
      Declarations.of(sources, nodes, Uses.of(nodes, Map.new(&2, List<&2, Lint.Node>)))
    case False{}:
      []

# The program from one of its files, built once for every file rule that runs on that file: references from it alone,
# if a rule needs declarations (`declare`). The runner gives each rule its options.
def Here.of(program: Lint.Program, source: Lint.Source, declare: Bool) -> Lint.Here:
  match program source:
    case Lint.Program{+sources} Lint.Source{path, namespace, text, +nodes, facts}:
      Lint.Here{
        Lint.Program{sources},
        Lint.Source{path, namespace, text, nodes, facts},
        Declarations.when(declare, sources, nodes),
        Index.of(nodes),
        []
      }

def Source.own(source: Lint.Source) -> Bool:
  match source:
    case Lint.Source{path, namespace, text, nodes, facts}:
      Bool.not(String.starts_with(namespace, "0x"))

def Program.own(sources: List<&2, Lint.Source>) -> List<&2, Lint.Source>:
  List.filter(~Lint.Source, ~Source.own, sources)

def Program.nodes(
  sources: List<&2, Lint.Source>,
  out: List<&2, List<&2, Lint.Node>>
) -> List<&2, Lint.Node>:
  match sources:
    case Nil{}:
      Utils.concat(&2, Lint.Node, List.reverse(&2, List<&2, Lint.Node>, out))
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
      Utils.concat(&2, Lint.Declaration, List.reverse(&2, List<&2, Lint.Declaration>, out))
    case Con{Lint.Source{path, namespace, text, nodes, facts}, rest}:
      Whole.declarations(rest, sources, uses, Declarations.of(sources, nodes, uses) <> out)

# The declarations of every file of `sources`, with their uses in all of them, if a rule needs them (`declare`).
def Whole.when(declare: Bool, +sources: List<&2, Lint.Source>) -> List<&2, Lint.Declaration>:
  match declare:
    case True{}:
      Whole.declarations(
        sources,
        sources,
        Uses.of(Program.nodes(sources, []), Map.new(&2, List<&2, Lint.Node>)),
        []
      )
    case False{}:
      []

def Whole.from(+sources: List<&2, Lint.Source>, declare: Bool) -> Lint.Whole:
  Lint.Whole{Lint.Program{sources}, Whole.when(declare, sources), []}

# The whole program, built once for every program rule: references from all its own files, if a rule needs
# declarations (`declare`).
def Whole.of(program: Lint.Program, declare: Bool) -> Lint.Whole:
  match program:
    case Lint.Program{sources}:
      Whole.from(Program.own(sources), declare)
