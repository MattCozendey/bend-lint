# What a rule sees. A rule file imports this file; a rules program imports cli.bend too, and calls it with its rules.
#
# Design
# - The rules program is an ordinary Bend program. seam.ts builds it once and keeps the build. The C lane is the
#   target; the JS lane must work too.
# - Bend's checker is TS for now: seam.ts makes each check's program of what Bend's parser and checker give, and answers
#   the questions rules ask about its types, over local TCP (see Seam in cli.bend). When the checker is Bend, glue in Bend makes
#   the same program, and the questions become calls.
# - A file is a tree of syntax nodes. A rule walks it, and reads what a node is from the node and the nodes above it.
# - Rules are pure, so they run in parallel. The runner answers every rule's questions of a round in one batch.
# - A check is read once and shared by every rule. Facts and declarations are collected only if a rule needs them.
# - A rule requests a fix as typed operations; the linter plans them and decides their safety. Until Bend's checker
#   is Bend, only a fix that writes comments over comments is safe (`--fix`).
import Base
import ../shared/lists.bend as Lists
import ../shared/names.bend as Names
import ../shared/strings.bend as Strings
import ../shared/tables.bend as Tables

# Program
# =======
type Quantity is Data:
  Erased{}
  Once{}
  Many{}
  Template{}

# Where something is: its file, and offsets in code points.
type Span is Data:
  Span{path: String, beg: U32, end: U32}

# What a syntax node is, as Bend's parser reads it: a declaration, a part of one, a term, or a pattern; with what only
# nodes of its kind have: the global name it declares or uses (`target`, as the check names it; an import's is the path
# of the file it loads), the binder it declares or a variable uses (numbered per top-level declaration), and its
# quantity as written (a `~` parameter's is Template). An import's written path is an ImportPath under it; `import
# Base` writes none. A Definition is `unsafe` if Bend's checker trusts its body (`@unsafe def f`, or `def f?`).
type Syntax is Data:
  Import{target: String}
  ImportPath{}
  Definition{target: String, unsafe: Bool}
  Datatype{target: String}
  Constructor{target: String}
  Law{target: String}
  Parameter{binder: U32, quantity: Quantity}
  Field{binder: U32, quantity: Quantity}
  Returns{}
  Body{}
  Variable{binder: U32}
  Reference{target: String}
  Substitution{}
  Let{}
  Binding{binder: U32, quantity: Quantity}
  Sort{}
  QuantityType{}
  QuantityLiteral{quantity: Quantity}
  QuantityMinimum{}
  Forall{binder: U32, quantity: Quantity}
  Lambda{binder: U32, quantity: Maybe<&2, Quantity>}
  Application{}
  TypeApplication{target: String}
  Construction{target: String}
  Literal{target: String}
  Elimination{target: String}
  Absurd{}
  Equality{}
  Reflexivity{}
  Rewrite{}
  Hole{}
  Annotation{}
  Match{}
  Case{}
  Destructure{quantity: Quantity}
  PatternVariable{binder: U32, quantity: Quantity}
  PatternConstructor{target: String}

# A type the checker holds: a handle, good in the check it came from. Rules ask about it (show, same, normal). Two types
# are the same only over the binders their scopes share: `A` of one def is not `A` of another.
type TypeRef is Data:
  TypeRef{check: U32, handle: U32}

# What a fact says of its node: the type its term has, or the type its binder declares (a parameter, field, pattern
# variable, lambda, forall or let binding).
type Role is Data:
  OfTerm{}
  OfBinder{}

# What the checker found for a node of the source: what the fact says of it, the quantity (how often the term is
# demanded, or the binder's), for a binder of a parameter, lambda, let or case, how often its body uses it (the most of
# its checked copies; none for a parameter a match takes apart), and the type. A fact is never wrong, but a node can
# have none: a term the checker rewrote into another (a scrutinee used again, a call a template took) is not typed as
# itself. A node has one fact per distinct type: pattern compilation can check one term in several branches, under
# different refinements.
type Fact is Data:
  Fact{role: Role, quantity: Quantity, used: Maybe<&2, Quantity>, checked: TypeRef}

# A syntax node: what it is, its name as written, where the file writes it (none for what the parser adds), the nodes
# under it, in order, and the checker's facts on it, if a rule needs them. An application's nodes are its function,
# then its arguments; a block's, its binders, then their values, then the rest of the block.
type Node is Data:
  Node{
    syntax: Syntax,
    name: String,
    span: Maybe<&2, Span>,
    kids: List<&2, Node>,
    facts: List<&2, Fact>
  }

# A file the check parsed: its path, its namespace in the check ("" for the checked file), its text, and its nodes: its
# imports, then its declarations, each constructor under its type.
type Source is Data:
  Source{path: String, namespace: String, text: String, nodes: List<&2, Node>}

type Program is Data:
  Program{sources: List<&2, Source>}

# A name a node declares, and the nodes that use it, in order.
type Declaration is Data:
  Declaration{node: Node, references: List<&2, Node>}

# The global name a node of this kind declares or uses, if any (an import's is the file it loads).
def Syntax.target(syntax: Syntax) -> Maybe<&2, String>:
  match syntax:
    case Import{t}:
      Some{t}
    case Definition{t, u}:
      Some{t}
    case Datatype{t}:
      Some{t}
    case Constructor{t}:
      Some{t}
    case Law{t}:
      Some{t}
    case Reference{t}:
      Some{t}
    case TypeApplication{t}:
      Some{t}
    case Construction{t}:
      Some{t}
    case Literal{t}:
      Some{t}
    case Elimination{t}:
      Some{t}
    case PatternConstructor{t}:
      Some{t}
    case _:
      None{}

# The global name a node of this kind uses, if it uses one.
def Syntax.used(syntax: Syntax) -> Maybe<&2, String>:
  match syntax:
    case Reference{t}:
      Some{t}
    case Construction{t}:
      Some{t}
    case TypeApplication{t}:
      Some{t}
    case PatternConstructor{t}:
      Some{t}
    case Elimination{t}:
      Some{t}
    case Literal{t}:
      Some{t}
    case _:
      None{}

# The binder a node of this kind declares, or, for a variable, uses.
def Syntax.binder(syntax: Syntax) -> Maybe<&2, U32>:
  match syntax:
    case Parameter{b, q}:
      Some{b}
    case Field{b, q}:
      Some{b}
    case Variable{b}:
      Some{b}
    case Binding{b, q}:
      Some{b}
    case Forall{b, q}:
      Some{b}
    case Lambda{b, q}:
      Some{b}
    case PatternVariable{b, q}:
      Some{b}
    case _:
      None{}

# Whether a node of this kind declares a global name (Some{True{}}), a binder of its top-level declaration
# (Some{False{}}), or nothing (an import declares an alias, which Declarations below handles).
def Syntax.declares(syntax: Syntax) -> Maybe<&2, Bool>:
  match syntax:
    case Definition{t, u}:
      Some{True{}}
    case Datatype{t}:
      Some{True{}}
    case Constructor{t}:
      Some{True{}}
    case Law{t}:
      Some{True{}}
    case Parameter{b, q}:
      Some{False{}}
    case Field{b, q}:
      Some{False{}}
    case Binding{b, q}:
      Some{False{}}
    case Lambda{b, q}:
      Some{False{}}
    case Forall{b, q}:
      Some{False{}}
    case PatternVariable{b, q}:
      Some{False{}}
    case _:
      None{}

def Node.syntax(node: Node) -> Syntax:
  match node:
    case Node{syntax, name, span, kids, facts}:
      syntax

# "" for a node of a kind that names nothing.
def Node.target(node: Node) -> String:
  match node:
    case Node{syntax, name, span, kids, facts}:
      Maybe.default(&2, String, Syntax.target(syntax), "")

def Node.kids(node: Node) -> List<&2, Node>:
  match node:
    case Node{syntax, name, span, kids, facts}:
      kids

# "" for no node, as are the next two.
def Node.name(node: Maybe<&2, Node>) -> String:
  match node:
    case Some{Node{syntax, name, span, kids, facts}}:
      name
    case None{}:
      ""

def Node.span(node: Maybe<&2, Node>) -> Maybe<&2, Span>:
  match node:
    case Some{Node{syntax, name, span, kids, facts}}:
      span
    case None{}:
      None{}

def Span.text(source: String, span: Maybe<&2, Span>) -> String:
  match span:
    case Some{Span{path, beg, end}}:
      Strings.slice(source, beg, end)
    case None{}:
      ""

# The namespace of a global name: what comes before its first ":", or "" for Base and the checked file's own names.
def Name.namespace(name: String) -> String:
  Strings.before(name, ':')

# Whether a parameter is written bare (`def f(x)`, filling a law): its quantity is the law's, which its node does not
# give.
def Node.bare(node: Node) -> Bool:
  match node:
    case Node{Parameter{b, q}, n, s, Con{Node{QuantityType{}, kn, ks, kk, kf}, rest}, f}:
      True{}
    case _:
      False{}

def Node.scrutinees.go(nodes: List<&2, Node>, out: List<&2, Node>) -> List<&2, Node>:
  match nodes:
    case Con{Node{Case{}, n, s, k, f}, rest}:
      List.reverse(&2, Node, out)
    case Con{node, rest}:
      Node.scrutinees.go(rest, node <> out)
    case Nil{}:
      List.reverse(&2, Node, out)

# The scrutinees of a match, in order: its nodes before its first case.
def Node.scrutinees(node: Node) -> List<&2, Node>:
  Node.scrutinees.go(Node.kids(node), [])

# The binders of the pattern variables in `nodes`, patterns, and under them, onto `out`.
def Node.bound(nodes: List<&2, Node>, out: List<&2, U32>) -> List<&2, U32>:
  match nodes:
    case Nil{}:
      out
    case Con{Node{PatternVariable{b, q}, n, s, k, f}, rest}:
      Node.bound(rest, b <> out)
    case Con{Node{PatternConstructor{t}, n, s, kids, f}, rest}:
      Node.bound(rest, Node.bound(kids, out))
    case Con{node, rest}:
      Node.bound(rest, out)

# Walking
# =======

# A node above another: the node, and the place among its nodes (from 0) of the one on the way down.
type Above is Data:
  Above{node: Node, at: U32}

def Above.of(parent: Maybe<&2, Node>, at: U32, up: List<&2, Above>) -> List<&2, Above>:
  match parent:
    case Some{p}:
      Above{p, at} <> up
    case None{}:
      up

def visit.go(
  ~C: Data,
  ~A: Data,
  ~f: @+c: C -> @+path: List<&2, Above> -> @+node: Node -> List<&2, A>,
  nodes: List<&2, Node>,
  +c: C,
  +up: List<&2, Above>,
  +parent: Maybe<&2, Node>,
  +at: U32,
  out: List<&2, A>
) -> List<&2, A>:
  match nodes:
    case Nil{}:
      out
    case Con{Node{syntax, name, span, +kids, facts}, rest}:
      +node = {Node{syntax, name, span, kids, facts}: Node}
      +path = Above.of(parent, at, up)
      visit.go(
        ~C,
        ~A,
        ~f,
        rest,
        c,
        up,
        parent,
        (at + 1: U32),
        visit.go(~C, ~A, ~f, kids, c, path, Some{node}, 0, Lists.onto(&2, A, f(c, path, node), out))
      )

# `f(c, path, node)` for each node of `nodes` and under them, parents first, in order: `path` holds the nodes above the
# node, innermost first.
def visit(
  ~C: Data,
  ~A: Data,
  ~f: @+c: C -> @+path: List<&2, Above> -> @+node: Node -> List<&2, A>,
  c: C,
  nodes: List<&2, Node>
) -> List<&2, A>:
  List.reverse(&2, A, visit.go(~C, ~A, ~f, nodes, c, [], None{}, 0, []))

# `f(c, node, s)` for each node of `nodes` and under them, parents first, in order, from `s`.
def fold(
  ~C: Data,
  ~S: Data,
  ~f: @+c: C -> @+node: Node -> S -> S,
  +c: C,
  nodes: List<&2, Node>,
  s: S
) -> S:
  match nodes:
    case Nil{}:
      s
    case Con{Node{syntax, name, span, +kids, facts}, rest}:
      fold(
        ~C,
        ~S,
        ~f,
        c,
        rest,
        fold(~C, ~S, ~f, c, kids, f(c, Node{syntax, name, span, kids, facts}, s))
      )

# The top-level declaration a node is in: the outermost node above it, or the node itself.
def top(path: List<&2, Above>, node: Node) -> Node:
  match path:
    case Nil{}:
      node
    case Con{Above{n, at}, Nil{}}:
      n
    case Con{a, rest}:
      top(rest, node)

def calls(called: String, owner: Node) -> Bool:
  match owner:
    case Node{Definition{declared, u}, n, s, k, f}:
      String.eq(called, declared)
    case _:
      False{}

# Whether a node is an application of the definition it is in, below `path`: a step of a loop, as Bend repeats work by
# recursion.
def recursive(path: List<&2, Above>, +node: Node) -> Bool:
  match node:
    case Node{Application{}, n, s, Con{Node{Reference{called}, rn, rs, rk, rf}, args}, f}:
      calls(called, top(path, node))
    case _:
      False{}

# Whether an application's function is Pair: it builds a pair type (`A & B`), whose parts are types.
def pair(kids: List<&2, Node>) -> Bool:
  match kids:
    case Con{Node{Reference{t}, n, s, k, f}, rest}:
      String.eq(t, "Pair")
    case _:
      False{}

def live.go(path: List<&2, Above>, ok: Bool) -> Bool:
  match path ok:
    case _ False{}:
      False{}
    case Nil{} True{}:
      False{}
    case Con{Above{Node{Body{}, n, s, k, f}, at}, rest} True{}:
      True{}
    case Con{Above{Node{Annotation{}, n, s, k, f}, at}, rest} True{}:
      live.go(rest, U32.is_eq(at, 0))
    case Con{Above{Node{Application{}, n, s, k, f}, at}, rest} True{}:
      live.go(rest, Bool.not(pair(k)))
    case Con{Above{Node{Equality{}, n, s, k, f}, at}, rest} True{}:
      False{}
    case Con{Above{Node{Forall{b, q}, n, s, k, f}, at}, rest} True{}:
      False{}
    case Con{Above{Node{TypeApplication{t}, n, s, k, f}, at}, rest} True{}:
      False{}
    case Con{a, rest} True{}:
      live.go(rest, True{})

# Whether a node below `path` is in live code: a definition's body, outside types: an annotation's type, an equality, a
# function or pair type, a type's arguments. Types and equations are dead: the checker sees them, the program does not
# run them.
def live(path: List<&2, Above>) -> Bool:
  live.go(path, True{})

# The definitions of `nodes`, by the name the check gives them: read one with `Names.find`. Of two with one name, the
# later is kept.
def definitions(nodes: List<&2, Node>, out: Map<&2, Maybe<&2, Node>>) -> Map<&2, Maybe<&2, Node>>:
  match nodes:
    case Nil{}:
      out
    case Con{Node{Definition{+t, u}, n, s, k, f}, rest}:
      definitions(
        rest,
        Map.set(&2, Maybe<&2, Node>, out, t, Some{Node{Definition{t, u}, n, s, k, f}})
      )
    case Con{node, rest}:
      definitions(rest, out)

def parameter.go(
  nodes: List<&2, Node>,
  found: Maybe<&2, Nat>,
  +binder: U32,
  +at: Nat
) -> Maybe<&2, Nat>:
  match nodes found:
    case _ Some{n}:
      Some{n}
    case Nil{} None{}:
      None{}
    case Con{Node{Parameter{b, q}, n, s, k, f}, rest} None{}:
      parameter.go(rest, Lists.when(Nat, U32.is_eq(b, binder), at), binder, 1n+at)
    case Con{node, rest} None{}:
      parameter.go(rest, None{}, binder, at)

# Where the parameter that declares `binder` is among `nodes`, a definition's, counting from 0.
def parameter(nodes: List<&2, Node>, binder: U32) -> Maybe<&2, Nat>:
  parameter.go(nodes, None{}, binder, 0n)

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

def Severity.names() -> List<&2, Names.Named<Severity>>:
  Names.named(~Severity, ~Severity.show, [Error{}, Warning{}, Information{}, Hint{}])

# An edit a fix asks for: replace a span's text; rename what the declaration written at `at` declares, with each of its
# uses; or rename only its uses, to point them at a name the program declares already (to drop a duplicate import,
# say). A rename changes an import's alias, the first part of each use (`U` of `U.two`), and any other name's last part.
# The linter finds the uses, and drops the fix if the text does not write the name where one of them is. It drops a
# Rename of a global name (a def, type, constructor or law), as files the check did not read can use it, and one whose
# new name is taken where the declaration is.
type Operation is Data:
  Replace{span: Span, text: String}
  Rename{at: Span, to: String}
  RenameUses{at: Span, to: String}

# A way to fix a finding: what it does, and its operations, in any of the program's own files (not Base, nor a hub
# package). The linter decides whether a fix is safe (`--fix`): see the design notes above.
type Fix is Data:
  Fix{title: String, operations: List<&2, Operation>}

type Finding is Data:
  Finding{severity: Severity, span: Span, message: String, fixes: List<&2, Fix>}

type Found is Data:
  Found{rule: String, finding: Finding}

# A finding at `span`, if `hit` and `span` is known.
def finding(
  severity: Severity,
  hit: Bool,
  span: Maybe<&2, Span>,
  text: String
) -> List<&2, Finding>:
  match hit span:
    case True{} Some{s}:
      [Finding{severity, s, text, []}]
    case _ _:
      []

# Options
# =======
type Value is Data:
  Num{n: U32}
  Flag{on: Bool}
  Text{text: String}

# What an option accepts: a whole number in a range, a flag, text (one of `choices`, unless there are none), or what
# one of `specs` accepts.
type Spec is Data:
  NumberOption{min: U32, max: U32}
  FlagOption{}
  TextOption{choices: List<&2, String>}
  AnyOption{specs: List<&2, Spec>}

# An option a rule declares: its name, its value when the config gives none, and what it accepts. The config gives
# values as `"rule/id": {"name": value}`; a name the rule does not declare, or a value it does not accept, is an error.
type Declared is Data:
  Declared{name: String, default: Value, spec: Spec}

# An option's value as a number, a flag or text; a value of another kind, or none, gives 0, False, "".
def Value.number(value: Maybe<&2, Value>) -> U32:
  match value:
    case Some{Num{n}}:
      n
    case _:
      0

def Value.flag(value: Maybe<&2, Value>) -> Bool:
  match value:
    case Some{Flag{on}}:
      on
    case _:
      False{}

def Value.text(value: Maybe<&2, Value>) -> String:
  match value:
    case Some{Text{text}}:
      text
    case _:
      ""

# Declarations
# ============

# What uses a file's imports: the nodes written with an alias's prefix (`U.two`, a fill `def U.law(x):`), by alias; and
# those that use Base: a global name with no namespace that the file does not declare (last first).
type Imported is Data:
  Imported{aliases: Map<&2, List<&2, Node>>, base: List<&2, Node>}

# What the declarations of a top-level declaration are read with: the program's files (one of them is what an import
# loads), the uses of global names in the files the declarations are read in, by name, the uses of the declaration's
# binders, by binder (each last first), and what uses its file's imports.
type Uses is Data:
  Uses{
    sources: List<&2, Source>,
    globals: Map<&2, List<&2, Node>>,
    binders: Tables.Table<List<&2, Node>>,
    imported: Imported
  }

def Uses.global.add(
  used: Maybe<&2, String>,
  node: Node,
  m: Map<&2, List<&2, Node>>
) -> Map<&2, List<&2, Node>>:
  match used:
    case Some{t}:
      Names.Group.add(Node, m, t, node)
    case None{}:
      m

def Uses.global(+u: Unit, +node: Node, m: Map<&2, List<&2, Node>>) -> Map<&2, List<&2, Node>>:
  Uses.global.add(Syntax.used(Node.syntax(node)), node, m)

def Uses.binder.add(
  +t: Tables.Table<List<&2, Node>>,
  +b: U32,
  node: Node
) -> Tables.Table<List<&2, Node>>:
  Tables.Table.set(
    List<&2, Node>,
    t,
    b,
    node <> Maybe.default(&2, List<&2, Node>, Tables.Table.read(List<&2, Node>, t, b), [])
  )

def Uses.binder(
  +u: Unit,
  +node: Node,
  t: Tables.Table<List<&2, Node>>
) -> Tables.Table<List<&2, Node>>:
  match node:
    case Node{Variable{b}, n, s, k, f}:
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
def Imported.own(nodes: List<&2, Node>, out: Set()) -> Set():
  match nodes:
    case Nil{}:
      out
    case Con{Node{syntax, n, s, k, f}, rest}:
      Imported.own(rest, Imported.own.add(Syntax.target(syntax), out))

def Imported.base(own: Set(), used: Maybe<&2, String>) -> Bool:
  match used:
    case Some{+name}:
      String.is_empty(Name.namespace(name)) && Bool.not(Pair.snd(Set(), Bool, Set.has(own, name)))
    case None{}:
      False{}

def Imported.alias(
  prefix: String,
  node: Node,
  aliases: Map<&2, List<&2, Node>>
) -> Map<&2, List<&2, Node>>:
  match prefix:
    case SNil{}:
      aliases
    case SCon{h, t}:
      Names.Group.add(Node, aliases, SCon{h, t}, node)

def Imported.add(+own: Set(), +node: Node, uses: Imported) -> Imported:
  match node uses:
    case Node{syntax, name, s, k, f} Imported{aliases, base}:
      Imported{
        Imported.alias(Strings.before(name, '.'), node, aliases),
        Lists.push(Node, Lists.when(Node, Imported.base(own, Syntax.used(syntax)), node), base)
      }

def Imported.of(+nodes: List<&2, Node>) -> Imported:
  fold(
    ~Set(),
    ~Imported,
    ~Imported.add,
    Imported.own(nodes, Set.new()),
    nodes,
    Imported{Map.new(&2, List<&2, Node>), []}
  )

# The namespace of the file at `path`, as the check names it (`found`, once found): "" for Base, or a file the check
# did not parse.
def Declarations.namespace(
  sources: List<&2, Source>,
  +path: String,
  found: Maybe<&2, String>
) -> String:
  match sources found:
    case _ Some{namespace}:
      namespace
    case Nil{} None{}:
      ""
    case Con{Source{p, namespace, text, nodes}, rest} None{}:
      Declarations.namespace(rest, path, Lists.when(String, String.eq(p, path), namespace))

# The uses of an import, in order: of Base (`base`), or of its alias.
def Declarations.imported(base: Bool, alias: String, imported: Imported) -> List<&2, Node>:
  match base imported:
    case True{} Imported{aliases, uses}:
      List.reverse(&2, Node, uses)
    case False{} Imported{aliases, uses}:
      Names.Group.get(Node, aliases, alias)

def Declarations.bound(
  binder: Maybe<&2, U32>,
  binders: Tables.Table<List<&2, Node>>
) -> List<&2, Node>:
  match binder:
    case Some{b}:
      List.reverse(
        &2,
        Node,
        Maybe.default(&2, List<&2, Node>, Tables.Table.read(List<&2, Node>, binders, b), [])
      )
    case None{}:
      []

def Declarations.declared(
  declares: Maybe<&2, Bool>,
  +node: Node,
  uses: Uses
) -> List<&2, Declaration>:
  match declares node uses:
    case Some{True{}} _ Uses{sources, globals, binders, imported}:
      [Declaration{node, Names.Group.get(Node, globals, Node.target(node))}]
    case Some{False{}} Node{syntax, name, s, k, f} Uses{sources, globals, binders, imported}:
      Bool.pick(
        List<&2, Declaration>,
        String.eq(name, "_"),
        [],
        [Declaration{node, Declarations.bound(Syntax.binder(syntax), binders)}]
      )
    case _ _ _:
      []

# A node's declaration, if it declares a name, with its uses, onto `out`.
def Declarations.node(
  +uses: Uses,
  +node: Node,
  out: List<&2, Declaration>
) -> List<&2, Declaration>:
  match uses node:
    case Uses{sources, globals, binders, imported} Node{Import{t}, name, s, k, f}:
      Declaration{
        node,
        Declarations.imported(
          String.is_empty(Declarations.namespace(sources, t, None{})),
          name,
          imported
        )
      }
        <> out
    case _ _:
      Lists.onto(
        &2,
        Declaration,
        Declarations.declared(Syntax.declares(Node.syntax(node)), node, uses),
        out
      )

def Declarations.tops(
  nodes: List<&2, Node>,
  +sources: List<&2, Source>,
  +globals: Map<&2, List<&2, Node>>,
  +imported: Imported,
  out: List<&2, Declaration>
) -> List<&2, Declaration>:
  match nodes:
    case Nil{}:
      out
    case Con{+top, rest}:
      Declarations.tops(
        rest,
        sources,
        globals,
        imported,
        fold(
          ~Uses,
          ~List<&2, Declaration>,
          ~Declarations.node,
          Uses{
            sources,
            globals,
            fold(
              ~Unit,
              ~Tables.Table<List<&2, Node>>,
              ~Uses.binder,
              Unit{},
              [top],
              Tables.TLeaf{None{}}
            ),
            imported
          },
          [top],
          out
        )
      )

def Declarations.files(
  files: List<&2, Source>,
  +sources: List<&2, Source>,
  +globals: Map<&2, List<&2, Node>>,
  out: List<&2, Declaration>
) -> List<&2, Declaration>:
  match files:
    case Nil{}:
      out
    case Con{Source{path, namespace, text, +nodes}, rest}:
      Declarations.files(
        rest,
        sources,
        globals,
        Declarations.tops(nodes, sources, globals, Imported.of(nodes), out)
      )

def Declarations.globals(
  files: List<&2, Source>,
  m: Map<&2, List<&2, Node>>
) -> Map<&2, List<&2, Node>>:
  match files:
    case Nil{}:
      m
    case Con{Source{path, namespace, text, nodes}, rest}:
      Declarations.globals(
        rest,
        fold(~Unit, ~Map<&2, List<&2, Node>>, ~Uses.global, Unit{}, nodes, m)
      )

# The declarations of `files`, in order, with their uses in `files`; `sources` are the program's files.
def Declarations.of(+files: List<&2, Source>, sources: List<&2, Source>) -> List<&2, Declaration>:
  List.reverse(
    &2,
    Declaration,
    Declarations.files(files, sources, Declarations.globals(files, Map.new(&2, List<&2, Node>)), [])
  )

def Declarations.when(
  declare: Bool,
  files: List<&2, Source>,
  sources: List<&2, Source>
) -> List<&2, Declaration>:
  match declare:
    case True{}:
      Declarations.of(files, sources)
    case False{}:
      []

def Source.own(source: Source) -> Bool:
  match source:
    case Source{path, namespace, text, nodes}:
      Bool.not(String.starts_with(namespace, "0x"))

# The program's own files: not hub packages.
def Program.own(sources: List<&2, Source>) -> List<&2, Source>:
  List.filter(~Source, ~Source.own, sources)

# What a file rule sees: the program, from one of its files; that file's declarations, with their uses in it, if a rule
# needs them; and the rule's options, each declared one with its value.
type Here is Data:
  Here{
    program: Program,
    source: Source,
    declarations: List<&2, Declaration>,
    options: List<&2, Names.Named<Value>>
  }

# What a program rule sees: the program (its files, hub packages aside); every declaration of its files, with their
# uses in all of them, if a rule needs them; and the rule's options.
type Whole is Data:
  Whole{
    program: Program,
    declarations: List<&2, Declaration>,
    options: List<&2, Names.Named<Value>>
  }

# The program from one of its files, built once for every file rule that runs on that file: its declarations, if a rule
# needs them (`declare`). The runner gives each rule its options.
def Here.of(program: Program, +source: Source, declare: Bool) -> Here:
  match program:
    case Program{+sources}:
      Here{Program{sources}, source, Declarations.when(declare, [source], sources), []}

# The whole program, built once for every program rule: the declarations of its own files, if a rule needs them
# (`declare`).
def Whole.of(program: Program, declare: Bool) -> Whole:
  match program:
    case Program{sources}:
      +own = Program.own(sources)
      Whole{Program{own}, Declarations.when(declare, own, own), []}

def Here.path(here: Here) -> String:
  match here:
    case Here{program, Source{path, namespace, text, nodes}, declarations, options}:
      path

# "" for the checked file.
def Here.namespace(here: Here) -> String:
  match here:
    case Here{program, Source{path, namespace, text, nodes}, declarations, options}:
      namespace

def Here.text(here: Here) -> String:
  match here:
    case Here{program, Source{path, namespace, text, nodes}, declarations, options}:
      text

# The file's nodes: its imports, then its declarations.
def Here.nodes(here: Here) -> List<&2, Node>:
  match here:
    case Here{program, Source{path, namespace, text, nodes}, declarations, options}:
      nodes

# Every file of the check, hub packages aside.
def Here.sources(here: Here) -> List<&2, Source>:
  match here:
    case Here{Program{sources}, source, declarations, options}:
      sources

def Here.declarations(here: Here) -> List<&2, Declaration>:
  match here:
    case Here{program, source, declarations, options}:
      declarations

# The config's value, or the default.
def Here.option(here: Here, name: String) -> Maybe<&2, Value>:
  match here:
    case Here{program, source, declarations, options}:
      Names.lookup(Value, name, options)

def Whole.declarations(whole: Whole) -> List<&2, Declaration>:
  match whole:
    case Whole{program, declarations, options}:
      declarations

def Whole.sources(whole: Whole) -> List<&2, Source>:
  match whole:
    case Whole{Program{sources}, declarations, options}:
      sources

def Whole.option(whole: Whole, name: String) -> Maybe<&2, Value>:
  match whole:
    case Whole{program, declarations, options}:
      Names.lookup(Value, name, options)

# Asking the checker
# ==================

# Show spells a type as its file does; Same compares as the checker does.
type Question is Data:
  Show{of: TypeRef}
  Same{a: TypeRef, b: TypeRef}
  Normal{of: TypeRef}

type Answer is Data:
  Shown{text: String}
  Equal{same: Bool}
  Normalized{handle: U32}

# A run so far: finished, or waiting for the answers to its questions, in order.
type Step<-R: Type> is Type:
  Finished{value: R}
  Pending{questions: List<&2, Question>, then: List<&2, Answer> -> Step<R>}

# A computation that may ask the checker, in `do Lint.Ask<A>:` blocks. Continuation-passing, so binding needs no
# recursion. A run may ask only cli.bend's `budget()` rounds, so ask for everything at once (show_all).
def Ask(-A: Type) -> Type:
  @-R: Type -> @k: (A -> Step<R>) -> Step<R>

def Ask.pure(-A: Type, x: A) -> Ask(A):
  R => k => k(x)

def Ask.bind(-A: Type, -B: Type, m: Ask(A), f: A -> Ask(B)) -> Ask(B):
  R => k => m(R, x => f(x, R, k))

def ask.step(-R: Type, questions: List<&2, Question>, k: List<&2, Answer> -> Step<R>) -> Step<R>:
  match questions:
    case Nil{}:
      k([])
    case Con{q, rest}:
      Pending{Con{q, rest}, k}

# The answers to `questions`, in order, asked in one round; none asked, no round.
def ask(questions: List<&2, Question>) -> Ask(List<&2, Answer>):
  R => k => ask.step(R, questions, k)

def done(findings: List<&2, Finding>) -> Ask(List<&2, Finding>):
  Ask.pure(List<&2, Finding>, findings)

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
def Answer.type(t: TypeRef, answers: List<&2, Answer>) -> TypeRef:
  match t answers:
    case TypeRef{check, handle} Con{Normalized{h}, rest}:
      TypeRef{check, h}
    case _ _:
      t

def show(t: TypeRef) -> Ask(String):
  Ask.bind(
    List<&2, Answer>,
    String,
    ask([Show{t}]),
    answers => Ask.pure(String, Answer.text(answers))
  )

def same(a: TypeRef, b: TypeRef) -> Ask(Bool):
  Ask.bind(
    List<&2, Answer>,
    Bool,
    ask([Same{a, b}]),
    answers => Ask.pure(Bool, Answer.same(answers))
  )

def normal(+t: TypeRef) -> Ask(TypeRef):
  Ask.bind(
    List<&2, Answer>,
    TypeRef,
    ask([Normal{t}]),
    answers => Ask.pure(TypeRef, Answer.type(t, answers))
  )

def Question.shows(types: List<&2, TypeRef>, out: List<&2, Question>) -> List<&2, Question>:
  match types:
    case Nil{}:
      List.reverse(&2, Question, out)
    case Con{t, rest}:
      Question.shows(rest, Show{t} <> out)

def Answer.texts(answers: List<&2, Answer>, out: List<&2, String>) -> List<&2, String>:
  match answers:
    case Nil{}:
      List.reverse(&2, String, out)
    case Con{Shown{text}, rest}:
      Answer.texts(rest, text <> out)
    case Con{a, rest}:
      Answer.texts(rest, "" <> out)

# How each type of `types` is shown, in order, asked in one round.
def show_all(types: List<&2, TypeRef>) -> Ask(List<&2, String>):
  Ask.bind(
    List<&2, Answer>,
    List<&2, String>,
    ask(Question.shows(types, [])),
    answers => Ask.pure(List<&2, String>, Answer.texts(answers, []))
  )

# What a rule needs collected for it, as each costs time and memory: the checker's facts, and the declarations with
# their uses. A rule that does not ask for them gets none.
type Needs is Data:
  Needs{facts: Bool, declarations: Bool}

# How a rule runs: once per linted file, reporting only in it; or once per check, on the whole program, reporting in any
# file (what it finds in a file that is not linted is dropped). When several entries check the named file, a program
# rule's finding stays if some check finds it, or, if `every`, if every check finds it; then, if an entry that reads the
# named file fails its check, the rule does not run.
type Run is Type:
  OnFile{run: @+here: Here -> Ask(List<&2, Finding>)}
  OnProgram{every: Bool, run: @+whole: Whole -> Ask(List<&2, Finding>)}

type Rule is Type:
  Rule{id: String, needs: Needs, options: List<&2, Declared>, run: Run}
