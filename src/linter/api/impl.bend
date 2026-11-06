import Base
import ../../shared.bend as Shared
import ./spec.bend as Spec

# The nodes written with an alias's prefix (`U.two`, a fill `def U.law(x):`), by alias; and those that use Base: a
# global name with no namespace that the file does not declare (last first).
type Imported is Data:
  Imported{aliases: Map<&2, List<&2, Spec.Node>>, base: List<&2, Spec.Node>}

# The program's files (one of them is what an import loads), the uses of global names in the files the declarations
# are read in, by name, the uses of the declaration's binders, by binder (each last first), and what uses its file's
# imports.
type Uses is Data:
  Uses{
    sources: List<&2, Spec.Source>,
    globals: Map<&2, List<&2, Spec.Node>>,
    binders: Shared.Tables.Table<List<&2, Spec.Node>>,
    imported: Imported
  }

type Answer is Data:
  Shown{text: String}
  Equal{same: Bool}
  Normalized{handle: U32}

def Spec.Imported():
  Imported

def Spec.Uses():
  Uses

def Spec.Answer():
  Answer

def Spec.Answer.shown(text):
  Shown{text}

def Spec.Answer.equal(same):
  Equal{same}

def Spec.Answer.normalized(handle):
  Normalized{handle}

# Program
# =======

# The global name a node of this kind declares or uses, if any (an import's is the file it loads).
def Syntax.target(syntax: Spec.Syntax) -> Maybe<&2, String>:
  match syntax:
    case Spec.Import{t}:
      Some{t}
    case Spec.Definition{t, u}:
      Some{t}
    case Spec.Datatype{t}:
      Some{t}
    case Spec.Constructor{t}:
      Some{t}
    case Spec.Law{t}:
      Some{t}
    case Spec.Reference{t}:
      Some{t}
    case Spec.TypeApplication{t}:
      Some{t}
    case Spec.Construction{t}:
      Some{t}
    case Spec.Literal{t}:
      Some{t}
    case Spec.Elimination{t}:
      Some{t}
    case Spec.PatternConstructor{t}:
      Some{t}
    case _:
      None{}

# The global name a node of this kind uses, if it uses one.
def Syntax.used(syntax: Spec.Syntax) -> Maybe<&2, String>:
  match syntax:
    case Spec.Reference{t}:
      Some{t}
    case Spec.Construction{t}:
      Some{t}
    case Spec.TypeApplication{t}:
      Some{t}
    case Spec.PatternConstructor{t}:
      Some{t}
    case Spec.Elimination{t}:
      Some{t}
    case Spec.Literal{t}:
      Some{t}
    case _:
      None{}

# The binder a node of this kind declares, or, for a variable, uses.
def Syntax.binder(syntax: Spec.Syntax) -> Maybe<&2, U32>:
  match syntax:
    case Spec.Parameter{b, q}:
      Some{b}
    case Spec.Field{b, q}:
      Some{b}
    case Spec.Variable{b}:
      Some{b}
    case Spec.Binding{b, q}:
      Some{b}
    case Spec.Forall{b, q}:
      Some{b}
    case Spec.Lambda{b, q}:
      Some{b}
    case Spec.PatternVariable{b, q}:
      Some{b}
    case _:
      None{}

def Spec.Syntax.declares(syntax):
  match syntax:
    case Spec.Definition{t, u}:
      Some{True{}}
    case Spec.Datatype{t}:
      Some{True{}}
    case Spec.Constructor{t}:
      Some{True{}}
    case Spec.Law{t}:
      Some{True{}}
    case Spec.Parameter{b, q}:
      Some{False{}}
    case Spec.Field{b, q}:
      Some{False{}}
    case Spec.Binding{b, q}:
      Some{False{}}
    case Spec.Lambda{b, q}:
      Some{False{}}
    case Spec.Forall{b, q}:
      Some{False{}}
    case Spec.PatternVariable{b, q}:
      Some{False{}}
    case _:
      None{}

def Node.syntax(node: Spec.Node) -> Spec.Syntax:
  match node:
    case Spec.Node{syntax, name, span, kids, facts}:
      syntax

def Spec.Node.target(node):
  match node:
    case Spec.Node{syntax, name, span, kids, facts}:
      Maybe.default(&2, String, Syntax.target(syntax), "")

def Spec.Node.kids(node):
  match node:
    case Spec.Node{syntax, name, span, kids, facts}:
      kids

def Spec.Node.name(node):
  match node:
    case Some{Spec.Node{syntax, name, span, kids, facts}}:
      name
    case None{}:
      ""

def Spec.Node.span(node):
  match node:
    case Some{Spec.Node{syntax, name, span, kids, facts}}:
      span
    case None{}:
      None{}

def Spec.Span.text(source, span):
  match span:
    case Some{Spec.Span{path, beg, end}}:
      Shared.Strings.slice(source, beg, end)
    case None{}:
      ""

def Spec.Name.namespace(name):
  Shared.Strings.before(name, ':')

def Spec.Node.is_bare(node):
  match node:
    case Spec.Node{
      Spec.Parameter{b, q},
      n,
      s,
      Con{Spec.Node{Spec.QuantityType{}, kn, ks, kk, kf}, rest},
      f
    }:
      True{}
    case _:
      False{}

def Node.scrutinees.go(nodes: List<&2, Spec.Node>, out: List<&2, Spec.Node>) -> List<&2, Spec.Node>:
  match nodes:
    case Con{Spec.Node{Spec.Case{}, n, s, k, f}, rest}:
      List.reverse(&2, Spec.Node, out)
    case Con{node, rest}:
      Node.scrutinees.go(rest, node <> out)
    case Nil{}:
      List.reverse(&2, Spec.Node, out)

def Spec.Node.scrutinees(node):
  Node.scrutinees.go(Spec.Node.kids(node), [])

def Spec.Node.bound(nodes, out):
  match nodes:
    case Nil{}:
      out
    case Con{Spec.Node{Spec.PatternVariable{b, q}, n, s, k, f}, rest}:
      Spec.Node.bound(rest, b <> out)
    case Con{Spec.Node{Spec.PatternConstructor{t}, n, s, kids, f}, rest}:
      Spec.Node.bound(rest, Spec.Node.bound(kids, out))
    case Con{node, rest}:
      Spec.Node.bound(rest, out)

# Walking
# =======
def Spec.top(path, node):
  match path:
    case Nil{}:
      node
    case Con{Spec.Above{n, at}, Nil{}}:
      n
    case Con{a, rest}:
      Spec.top(rest, node)

def calls(called: String, owner: Spec.Node) -> Bool:
  match owner:
    case Spec.Node{Spec.Definition{declared, u}, n, s, k, f}:
      String.eq(called, declared)
    case _:
      False{}

def Spec.is_recursive(path, node):
  match node:
    case Spec.Node{
      Spec.Application{},
      n,
      s,
      Con{Spec.Node{Spec.Reference{called}, rn, rs, rk, rf}, args},
      f
    }:
      calls(called, Spec.top(path, node))
    case _:
      False{}

def Spec.is_pair(kids):
  match kids:
    case Con{Spec.Node{Spec.Reference{t}, n, s, k, f}, rest}:
      String.eq(t, "Pair")
    case _:
      False{}

def is_live.go(path: List<&2, Spec.Above>, ok: Bool) -> Bool:
  match path ok:
    case _ False{}:
      False{}
    case Nil{} True{}:
      False{}
    case Con{Spec.Above{Spec.Node{Spec.Body{}, n, s, k, f}, at}, rest} True{}:
      True{}
    case Con{Spec.Above{Spec.Node{Spec.Annotation{}, n, s, k, f}, at}, rest} True{}:
      is_live.go(rest, U32.is_eq(at, 0))
    case Con{Spec.Above{Spec.Node{Spec.Application{}, n, s, k, f}, at}, rest} True{}:
      is_live.go(rest, Bool.not(Spec.is_pair(k)))
    case Con{Spec.Above{Spec.Node{Spec.Equality{}, n, s, k, f}, at}, rest} True{}:
      False{}
    case Con{Spec.Above{Spec.Node{Spec.Forall{b, q}, n, s, k, f}, at}, rest} True{}:
      False{}
    case Con{Spec.Above{Spec.Node{Spec.TypeApplication{t}, n, s, k, f}, at}, rest} True{}:
      False{}
    case Con{a, rest} True{}:
      is_live.go(rest, True{})

def Spec.is_live(path):
  is_live.go(path, True{})

def Spec.definitions(nodes, out):
  match nodes:
    case Nil{}:
      out
    case Con{Spec.Node{Spec.Definition{+t, u}, n, s, k, f}, rest}:
      Spec.definitions(
        rest,
        Map.set(
          &2,
          Maybe<&2, Spec.Node>,
          out,
          t,
          Some{Spec.Node{Spec.Definition{t, u}, n, s, k, f}}
        )
      )
    case Con{node, rest}:
      Spec.definitions(rest, out)

def parameter.go(
  nodes: List<&2, Spec.Node>,
  found: Maybe<&2, Nat>,
  +binder: U32,
  +at: Nat
) -> Maybe<&2, Nat>:
  match nodes found:
    case _ Some{n}:
      Some{n}
    case Nil{} None{}:
      None{}
    case Con{Spec.Node{Spec.Parameter{b, q}, n, s, k, f}, rest} None{}:
      parameter.go(rest, Shared.Lists.when(Nat, U32.is_eq(b, binder), at), binder, 1n+at)
    case Con{node, rest} None{}:
      parameter.go(rest, None{}, binder, at)

def Spec.parameter(nodes, binder):
  parameter.go(nodes, None{}, binder, 0n)

# Rules
# =====
def Spec.finding(severity, hit, span, text):
  match hit span:
    case True{} Some{s}:
      [Spec.Finding{severity, s, text, []}]
    case _ _:
      []

# Options
# =======
def Spec.Value.number(value):
  match value:
    case Some{Spec.Num{n}}:
      n
    case _:
      0

def Value.flag(value: Maybe<&2, Spec.Value>) -> Bool:
  match value:
    case Some{Spec.Flag{on}}:
      on
    case _:
      False{}

def Spec.Value.text(value):
  match value:
    case Some{Spec.Chars{text}}:
      text
    case _:
      ""

# Declarations
# ============
def Uses.global.add(
  used: Maybe<&2, String>,
  node: Spec.Node,
  m: Map<&2, List<&2, Spec.Node>>
) -> Map<&2, List<&2, Spec.Node>>:
  match used:
    case Some{t}:
      Shared.Names.Group.add(Spec.Node, m, t, node)
    case None{}:
      m

def Uses.global(
  +u: Unit,
  +node: Spec.Node,
  m: Map<&2, List<&2, Spec.Node>>
) -> Map<&2, List<&2, Spec.Node>>:
  Uses.global.add(Syntax.used(Node.syntax(node)), node, m)

def Uses.binder.add(
  +t: Shared.Tables.Table<List<&2, Spec.Node>>,
  +b: U32,
  node: Spec.Node
) -> Shared.Tables.Table<List<&2, Spec.Node>>:
  Shared.Tables.Table.set(
    List<&2, Spec.Node>,
    t,
    b,
    node
      <> Maybe.default(
        &2,
        List<&2, Spec.Node>,
        Shared.Tables.Table.get(List<&2, Spec.Node>, t, b),
        []
      )
  )

def Uses.binder(
  +u: Unit,
  +node: Spec.Node,
  t: Shared.Tables.Table<List<&2, Spec.Node>>
) -> Shared.Tables.Table<List<&2, Spec.Node>>:
  match node:
    case Spec.Node{Spec.Variable{b}, n, s, k, f}:
      Uses.binder.add(t, b, node)
    case _:
      t

def Imported.own.add(target: Maybe<&2, String>, out: Set()) -> Set():
  match target:
    case Some{t}:
      Set.add(out, t)
    case None{}:
      out

# The global names a file's own top-level declarations declare, as a set.
def Imported.own(nodes: List<&2, Spec.Node>, out: Set()) -> Set():
  match nodes:
    case Nil{}:
      out
    case Con{Spec.Node{syntax, n, s, k, f}, rest}:
      Imported.own(rest, Imported.own.add(Syntax.target(syntax), out))

def Imported.is_base(own: Set(), used: Maybe<&2, String>) -> Bool:
  match used:
    case Some{+name}:
      String.is_empty(Spec.Name.namespace(name)) && Bool.not(Shared.Sets.has(own, name))
    case None{}:
      False{}

def Imported.alias(
  prefix: String,
  node: Spec.Node,
  aliases: Map<&2, List<&2, Spec.Node>>
) -> Map<&2, List<&2, Spec.Node>>:
  match prefix:
    case SNil{}:
      aliases
    case SCon{h, t}:
      Shared.Names.Group.add(Spec.Node, aliases, SCon{h, t}, node)

def Imported.add(+own: Set(), +node: Spec.Node, uses: Imported) -> Imported:
  match node uses:
    case Spec.Node{syntax, name, s, k, f} Imported{aliases, base}:
      Imported{
        Imported.alias(Shared.Strings.before(name, '.'), node, aliases),
        Shared.Lists.push(
          Spec.Node,
          Shared.Lists.when(Spec.Node, Imported.is_base(own, Syntax.used(syntax)), node),
          base
        )
      }

def Imported.of(+nodes: List<&2, Spec.Node>) -> Imported:
  Spec.fold(
    ~Set(),
    ~Imported,
    ~Imported.add,
    Imported.own(nodes, Set.new()),
    nodes,
    Imported{Map.new(&2, List<&2, Spec.Node>), []}
  )

# The namespace of the file at `path`, as the check names it (`found`, once found): "" for Base, or a file the check
# did not parse.
def Declarations.namespace(
  sources: List<&2, Spec.Source>,
  +path: String,
  found: Maybe<&2, String>
) -> String:
  match sources found:
    case _ Some{namespace}:
      namespace
    case Nil{} None{}:
      ""
    case Con{Spec.Source{p, namespace, text, nodes}, rest} None{}:
      Declarations.namespace(rest, path, Shared.Lists.when(String, String.eq(p, path), namespace))

# The uses of an import, in order: of Base (`base`), or of its alias.
def Declarations.imported(base: Bool, alias: String, imported: Imported) -> List<&2, Spec.Node>:
  match base imported:
    case True{} Imported{aliases, uses}:
      List.reverse(&2, Spec.Node, uses)
    case False{} Imported{aliases, uses}:
      Shared.Names.Group.get(Spec.Node, aliases, alias)

def Declarations.bound(
  binder: Maybe<&2, U32>,
  binders: Shared.Tables.Table<List<&2, Spec.Node>>
) -> List<&2, Spec.Node>:
  match binder:
    case Some{b}:
      List.reverse(
        &2,
        Spec.Node,
        Maybe.default(
          &2,
          List<&2, Spec.Node>,
          Shared.Tables.Table.get(List<&2, Spec.Node>, binders, b),
          []
        )
      )
    case None{}:
      []

def Declarations.declared(
  declares: Maybe<&2, Bool>,
  +node: Spec.Node,
  uses: Uses
) -> List<&2, Spec.Declaration>:
  match declares node uses:
    case Some{True{}} _ Uses{sources, globals, binders, imported}:
      [Spec.Declaration{node, Shared.Names.Group.get(Spec.Node, globals, Spec.Node.target(node))}]
    case Some{False{}} Spec.Node{syntax, name, s, k, f} Uses{sources, globals, binders, imported}:
      Bool.pick(
        List<&2, Spec.Declaration>,
        String.eq(name, "_"),
        [],
        [Spec.Declaration{node, Declarations.bound(Syntax.binder(syntax), binders)}]
      )
    case _ _ _:
      []

# A node's declaration, if it declares a name, with its uses, onto `out`.
def Declarations.node(
  +uses: Uses,
  +node: Spec.Node,
  out: List<&2, Spec.Declaration>
) -> List<&2, Spec.Declaration>:
  match uses node:
    case Uses{sources, globals, binders, imported} Spec.Node{Spec.Import{t}, name, s, k, f}:
      Spec.Declaration{
        node,
        Declarations.imported(
          String.is_empty(Declarations.namespace(sources, t, None{})),
          name,
          imported
        )
      }
        <> out
    case _ _:
      Shared.Lists.onto(
        &2,
        Spec.Declaration,
        Declarations.declared(Spec.Syntax.declares(Node.syntax(node)), node, uses),
        out
      )

def Declarations.tops(
  nodes: List<&2, Spec.Node>,
  +sources: List<&2, Spec.Source>,
  +globals: Map<&2, List<&2, Spec.Node>>,
  +imported: Imported,
  out: List<&2, Spec.Declaration>
) -> List<&2, Spec.Declaration>:
  match nodes:
    case Nil{}:
      out
    case Con{+top, rest}:
      Declarations.tops(
        rest,
        sources,
        globals,
        imported,
        Spec.fold(
          ~Uses,
          ~List<&2, Spec.Declaration>,
          ~Declarations.node,
          Uses{
            sources,
            globals,
            Spec.fold(
              ~Unit,
              ~Shared.Tables.Table<List<&2, Spec.Node>>,
              ~Uses.binder,
              Unit{},
              [top],
              Shared.Tables.TLeaf{None{}}
            ),
            imported
          },
          [top],
          out
        )
      )

def Declarations.files(
  files: List<&2, Spec.Source>,
  +sources: List<&2, Spec.Source>,
  +globals: Map<&2, List<&2, Spec.Node>>,
  out: List<&2, Spec.Declaration>
) -> List<&2, Spec.Declaration>:
  match files:
    case Nil{}:
      out
    case Con{Spec.Source{path, namespace, text, +nodes}, rest}:
      Declarations.files(
        rest,
        sources,
        globals,
        Declarations.tops(nodes, sources, globals, Imported.of(nodes), out)
      )

def Declarations.globals(
  files: List<&2, Spec.Source>,
  m: Map<&2, List<&2, Spec.Node>>
) -> Map<&2, List<&2, Spec.Node>>:
  match files:
    case Nil{}:
      m
    case Con{Spec.Source{path, namespace, text, nodes}, rest}:
      Declarations.globals(
        rest,
        Spec.fold(~Unit, ~Map<&2, List<&2, Spec.Node>>, ~Uses.global, Unit{}, nodes, m)
      )

# The declarations of `files`, in order, with their uses in `files`; `sources` are the program's files.
def Declarations.of(
  +files: List<&2, Spec.Source>,
  sources: List<&2, Spec.Source>
) -> List<&2, Spec.Declaration>:
  List.reverse(
    &2,
    Spec.Declaration,
    Declarations.files(
      files,
      sources,
      Declarations.globals(files, Map.new(&2, List<&2, Spec.Node>)),
      []
    )
  )

def Declarations.when(
  declare: Bool,
  files: List<&2, Spec.Source>,
  sources: List<&2, Spec.Source>
) -> List<&2, Spec.Declaration>:
  match declare:
    case True{}:
      Declarations.of(files, sources)
    case False{}:
      []

def Source.is_own(source: Spec.Source) -> Bool:
  match source:
    case Spec.Source{path, namespace, text, nodes}:
      Bool.not(String.starts_with(namespace, "0x"))

def Spec.Program.own(sources):
  List.filter(~Spec.Source, ~Source.is_own, sources)

# Definitions
# ===========
def Spec.type_name(nodes):
  match nodes:
    case Con{Spec.Node{Spec.Reference{t}, n, s, k, f}, rest}:
      t
    case _:
      ""

# Whether a parameter of this quantity is there at run time.
def Quantity.is_runtime(quantity: Spec.Quantity) -> Bool:
  match quantity:
    case Spec.Erased{}:
      False{}
    case Spec.Template{}:
      False{}
    case _:
      True{}

# The runtime parameters among a definition's nodes, in order, onto `out`.
def Def.params(nodes: List<&2, Spec.Node>, out: List<&2, Spec.Param>) -> List<&2, Spec.Param>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Spec.Param, out)
    case Con{Spec.Node{Spec.Parameter{b, q}, n, s, kids, f}, rest}:
      Def.params(
        rest,
        Shared.Lists.push(
          Spec.Param,
          Shared.Lists.when(
            Spec.Param,
            Quantity.is_runtime(q),
            Spec.Param{n, Spec.type_name(kids)}
          ),
          out
        )
      )
    case Con{node, rest}:
      Def.params(rest, out)

def Spec.forks(nodes, found):
  match nodes found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{
      Spec.Node{
        Spec.Destructure{q},
        n,
        s,
        Con{
          Spec.Node{Spec.PatternVariable{a, aq}, an, as, ak, af},
          Con{Spec.Node{Spec.PatternVariable{b, bq}, bn, bs, bk, bf}, more}
        },
        f
      },
      rest
    } False{}:
      True{}
    case Con{Spec.Node{syntax, n, s, kids, f}, rest} False{}:
      Spec.forks(rest, Spec.forks(kids, False{}))

# The definition an application below `path` calls by name.
def Def.called.visit(+u: Unit, +path: List<&2, Spec.Above>, +node: Spec.Node) -> List<&2, String>:
  match node:
    case Spec.Node{
      Spec.Application{},
      n,
      s,
      Con{Spec.Node{Spec.Reference{t}, rn, rs, rk, rf}, args},
      f
    }:
      [t]
    case _:
      []

# The type a definition's nodes say it returns, as one name, or "".
def Def.returned(nodes: List<&2, Spec.Node>) -> String:
  match nodes:
    case Nil{}:
      ""
    case Con{Spec.Node{Spec.Returns{}, n, s, kids, f}, rest}:
      Spec.type_name(kids)
    case Con{node, rest}:
      Def.returned(rest)

def Spec.Def.forks(info):
  match info:
    case Some{Spec.Def{t, params, forks, calls, r}}:
      forks
    case None{}:
      False{}

# The definitions among a file's nodes, by the name the check gives them, onto `out`.
def Program.defs.file(
  nodes: List<&2, Spec.Node>,
  out: Map<&2, Maybe<&2, Spec.Def>>
) -> Map<&2, Maybe<&2, Spec.Def>>:
  match nodes:
    case Nil{}:
      out
    case Con{Spec.Node{Spec.Definition{+t, u}, n, s, +kids, f}, rest}:
      Program.defs.file(
        rest,
        Map.set(
          &2,
          Maybe<&2, Spec.Def>,
          out,
          t,
          Some{
            Spec.Def{
              t,
              Def.params(kids, []),
              Spec.forks(kids, False{}),
              Spec.visit(~Unit, ~String, ~Def.called.visit, Unit{}, kids),
              Def.returned(kids)
            }
          }
        )
      )
    case Con{node, rest}:
      Program.defs.file(rest, out)

def Spec.Program.defs(sources, out):
  match sources:
    case Nil{}:
      out
    case Con{Spec.Source{path, namespace, text, nodes}, rest}:
      Spec.Program.defs(rest, Program.defs.file(nodes, out))

def Program.callers.if(found: Bool, t: String, callers: Set()) -> Set():
  match found:
    case True{}:
      Set.add(callers, t)
    case False{}:
      callers

# `callers` with the definition `info`, if it calls one of them.
def Program.callers.step(info: Maybe<&2, Spec.Def>, +callers: Set()) -> Set():
  match info:
    case Some{Spec.Def{+t, ps, forks, calls, r}}:
      Program.callers.if(
        Shared.Sets.has_any(calls, callers, Shared.Sets.has(callers, t)),
        t,
        callers
      )
    case None{}:
      callers

# `callers` after a step for each definition among a file's nodes, in order.
def Program.callers.file(
  nodes: List<&2, Spec.Node>,
  +defs: Map<&2, Maybe<&2, Spec.Def>>,
  callers: Set()
) -> Set():
  match nodes:
    case Nil{}:
      callers
    case Con{Spec.Node{Spec.Definition{t, u}, n, s, k, f}, rest}:
      Program.callers.file(
        rest,
        defs,
        Program.callers.step(Shared.Names.find(Spec.Def, defs, t), callers)
      )
    case Con{node, rest}:
      Program.callers.file(rest, defs, callers)

def Program.callers.pass(
  sources: List<&2, Spec.Source>,
  +defs: Map<&2, Maybe<&2, Spec.Def>>,
  callers: Set()
) -> Set():
  match sources:
    case Nil{}:
      callers
    case Con{Spec.Source{path, namespace, text, nodes}, rest}:
      Program.callers.pass(rest, defs, Program.callers.file(nodes, defs, callers))

# Passes over the program until one adds nothing (`same`), or `fuel` runs out.
def Program.callers.go(
  fuel: Nat,
  same: Bool,
  +sources: List<&2, Spec.Source>,
  +defs: Map<&2, Maybe<&2, Spec.Def>>,
  +callers: Set()
) -> Set():
  match fuel same:
    case _ True{}:
      callers
    case 0n False{}:
      callers
    case 1n+f False{}:
      +next = Program.callers.pass(sources, defs, callers)
      Program.callers.go(f, Nat.is_eq(Set.size(callers), Set.size(next)), sources, defs, next)

def Spec.Program.callers(sources, defs, seeds):
  Program.callers.go(Map.size(&2, Maybe<&2, Spec.Def>, defs), False{}, sources, defs, seeds)

def Spec.Here.of(program, source, declare):
  match program:
    case Spec.Program{+sources}:
      Spec.Here{Spec.Program{sources}, source, Declarations.when(declare, [source], sources), []}

def Spec.Whole.of(program, declare):
  match program:
    case Spec.Program{sources}:
      +own = Spec.Program.own(sources)
      Spec.Whole{Spec.Program{own}, Declarations.when(declare, own, own), []}

def Spec.Here.path(here):
  match here:
    case Spec.Here{program, Spec.Source{path, namespace, text, nodes}, declarations, options}:
      path

def Spec.Here.namespace(here):
  match here:
    case Spec.Here{program, Spec.Source{path, namespace, text, nodes}, declarations, options}:
      namespace

def Spec.Here.text(here):
  match here:
    case Spec.Here{program, Spec.Source{path, namespace, text, nodes}, declarations, options}:
      text

def Spec.Here.nodes(here):
  match here:
    case Spec.Here{program, Spec.Source{path, namespace, text, nodes}, declarations, options}:
      nodes

def Spec.Here.sources(here):
  match here:
    case Spec.Here{Spec.Program{sources}, source, declarations, options}:
      sources

def Spec.Here.declarations(here):
  match here:
    case Spec.Here{program, source, declarations, options}:
      declarations

def Spec.Here.option(here, name):
  match here:
    case Spec.Here{program, source, declarations, options}:
      Shared.Names.lookup(Spec.Value, name, options)

def Spec.Whole.declarations(whole):
  match whole:
    case Spec.Whole{program, declarations, options}:
      declarations

def Whole.sources(whole: Spec.Whole) -> List<&2, Spec.Source>:
  match whole:
    case Spec.Whole{Spec.Program{sources}, declarations, options}:
      sources

def Whole.option(whole: Spec.Whole, name: String) -> Maybe<&2, Spec.Value>:
  match whole:
    case Spec.Whole{program, declarations, options}:
      Shared.Names.lookup(Spec.Value, name, options)

# Asking the checker
# ==================
def ask.step(
  -R: Type,
  questions: List<&2, Spec.Question>,
  k: List<&2, Answer> -> Spec.Step<R>
) -> Spec.Step<R>:
  match questions:
    case Nil{}:
      k([])
    case Con{q, rest}:
      Spec.Pending{Con{q, rest}, k}

# The answers to `questions`, in order, asked in one round; none asked, no round.
def ask(questions: List<&2, Spec.Question>) -> Spec.Ask(List<&2, Answer>):
  R => k => ask.step(R, questions, k)

def Spec.done(findings):
  Spec.Ask.pure(List<&2, Spec.Finding>, findings)

def Answer.text(answers: List<&2, Answer>) -> String:
  match answers:
    case Con{Shown{text}, rest}:
      text
    case _:
      ""

def Answer.same(answers: List<&2, Answer>) -> Bool:
  match answers:
    case Con{Equal{same}, rest}:
      same
    case _:
      False{}

# `t` with the handle of its normal form, if the answers give one.
def Answer.type(t: Spec.TypeRef, answers: List<&2, Answer>) -> Spec.TypeRef:
  match t answers:
    case Spec.TypeRef{check, handle} Con{Normalized{h}, rest}:
      Spec.TypeRef{check, h}
    case _ _:
      t

def show(t: Spec.TypeRef) -> Spec.Ask(String):
  Spec.Ask.bind(
    List<&2, Answer>,
    String,
    ask([Spec.Show{t}]),
    answers => Spec.Ask.pure(String, Answer.text(answers))
  )

def same(a: Spec.TypeRef, b: Spec.TypeRef) -> Spec.Ask(Bool):
  Spec.Ask.bind(
    List<&2, Answer>,
    Bool,
    ask([Spec.Same{a, b}]),
    answers => Spec.Ask.pure(Bool, Answer.same(answers))
  )

def normal(+t: Spec.TypeRef) -> Spec.Ask(Spec.TypeRef):
  Spec.Ask.bind(
    List<&2, Answer>,
    Spec.TypeRef,
    ask([Spec.Normal{t}]),
    answers => Spec.Ask.pure(Spec.TypeRef, Answer.type(t, answers))
  )

def Question.shows(
  types: List<&2, Spec.TypeRef>,
  out: List<&2, Spec.Question>
) -> List<&2, Spec.Question>:
  match types:
    case Nil{}:
      List.reverse(&2, Spec.Question, out)
    case Con{t, rest}:
      Question.shows(rest, Spec.Show{t} <> out)

def Answer.texts(answers: List<&2, Answer>, out: List<&2, String>) -> List<&2, String>:
  match answers:
    case Nil{}:
      List.reverse(&2, String, out)
    case Con{Shown{text}, rest}:
      Answer.texts(rest, text <> out)
    case Con{a, rest}:
      Answer.texts(rest, "" <> out)

def Spec.show_all(types):
  Spec.Ask.bind(
    List<&2, Answer>,
    List<&2, String>,
    ask(Question.shows(types, [])),
    answers => Spec.Ask.pure(List<&2, String>, Answer.texts(answers, []))
  )
