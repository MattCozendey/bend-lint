# What a rule sees. A rule file imports this file, and defines `rule()`.
#
# Design
# - The rules run in an ordinary Bend program that seam.ts writes from bend-lint.json, builds once and keeps. The C
#   lane is the target; the JS lane must work too.
# - Bend's checker is TS for now: seam.ts makes each check's program of what Bend's parser and checker give, and answers
#   the questions rules ask about its types, over local TCP (see Seam in cli.bend). When the checker is Bend, glue in
#   Bend makes the same program, and the questions become calls.
# - A file is a tree of syntax nodes. A rule walks it, and reads what a node is from the node and the nodes above it.
# - Rules are pure, so they run in parallel. The runner answers every rule's questions of a round in one batch.
# - A check is read once and shared by every rule. Facts and declarations are collected only if a rule needs them.
# - A rule requests a fix as typed operations, and the linter plans them. Until Bend's checker is Bend, no fix is
#   proven to keep the program: `--fix-dangerously` makes them all, and `--fix` makes none.
import Base
import ../../shared.bend as Shared

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

# A node above another: the node, and the place among its nodes (from 0) of the one on the way down.
type Above is Data:
  Above{node: Node, at: U32}

type Severity is Data:
  Error{}
  Warning{}
  Information{}
  Hint{}

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
# package).
type Fix is Data:
  Fix{title: String, operations: List<&2, Operation>}

type Finding is Data:
  Finding{severity: Severity, span: Span, message: String, fixes: List<&2, Fix>}

type Found is Data:
  Found{rule: String, finding: Finding}

type Value is Data:
  Num{n: U32}
  Flag{on: Bool}
  Chars{text: String}

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
    binders: Shared.Tables.Table<List<&2, Node>>,
    imported: Imported
  }

# A runtime parameter of a definition: its name, and its type as one name ("" if it is not one name).
type Param is Data:
  Param{name: String, ty: String}

# A definition of the program: its name as the check names it, its runtime parameters, whether it forks, the
# definitions it calls by name, and the type it returns, as one name ("" if it is not one name).
type Def is Data:
  Def{
    target: String,
    params: List<&2, Param>,
    forks: Bool,
    calls: List<&2, String>,
    returns: String
  }

# What a file rule sees: the program, from one of its files; that file's declarations, with their uses in it, if a rule
# needs them; and the rule's options, each declared one with its value.
type Here is Data:
  Here{
    program: Program,
    source: Source,
    declarations: List<&2, Declaration>,
    options: List<&2, Shared.Names.Named<Value>>
  }

# What a program rule sees: the program (its files, hub packages aside); every declaration of its files, with their
# uses in all of them, if a rule needs them; and the rule's options.
type Whole is Data:
  Whole{
    program: Program,
    declarations: List<&2, Declaration>,
    options: List<&2, Shared.Names.Named<Value>>
  }

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

# A rule: what it needs, the options it declares, and how it runs. Its id is its path in bend-lint-rules/, without
# .bend, as bend-lint.json names it.
type Rule is Type:
  Rule{needs: Needs, options: List<&2, Declared>, run: Run}

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
        visit.go(
          ~C,
          ~A,
          ~f,
          kids,
          c,
          path,
          Some{node},
          0,
          Shared.Lists.onto(&2, A, f(c, path, node), out)
        )
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

def Severity.names() -> List<&2, Shared.Names.Named<Severity>>:
  Shared.Names.table(~Severity, ~Severity.show, [Error{}, Warning{}, Information{}, Hint{}])

# A computation that may ask the checker, in `do Lint.Ask<A>:` blocks. Continuation-passing, so binding needs no
# recursion. A run may ask only cli.bend's `budget()` rounds, so ask for everything at once (show_all).
def Ask(-A: Type) -> Type:
  @-R: Type -> @k: (A -> Step<R>) -> Step<R>

def Ask.pure(-A: Type, x: A) -> Ask(A):
  R => k => k(x)

def Ask.bind(-A: Type, -B: Type, m: Ask(A), f: A -> Ask(B)) -> Ask(B):
  R => k => m(R, x => f(x, R, k))

# Whether a node of this kind declares a global name (Some{True{}}), a binder of its top-level declaration
# (Some{False{}}), or nothing (an import declares an alias, which Declarations below handles).
law Syntax.declares:
  for syntax: Syntax
  Maybe<&2, Bool>

# "" for a node of a kind that names nothing.
law Node.target:
  for node: Node
  String

law Node.kids:
  for node: Node
  List<&2, Node>

# "" for no node, as are the next two.
law Node.name:
  for node: Maybe<&2, Node>
  String

law Node.span:
  for node: Maybe<&2, Node>
  Maybe<&2, Span>

law Span.text:
  for source: String
  for span: Maybe<&2, Span>
  String

# The namespace of a global name: what comes before its first ":", or "" for Base and the checked file's own names.
law Name.namespace:
  for name: String
  String

# Whether a parameter is written bare (`def f(x)`, filling a law): its quantity is the law's, which its node does not
# give.
law Node.is_bare:
  for node: Node
  Bool

# The scrutinees of a match, in order: its nodes before its first case.
law Node.scrutinees:
  for node: Node
  List<&2, Node>

# The binders of the pattern variables in `nodes`, patterns, and under them, onto `out`.
law Node.bound:
  for nodes: List<&2, Node>
  for out: List<&2, U32>
  List<&2, U32>

# The top-level declaration a node is in: the outermost node above it, or the node itself.
law top:
  for path: List<&2, Above>
  for node: Node
  Node

# Whether a node is an application of the definition it is in, below `path`: a step of a loop, as Bend repeats work by
# recursion.
law is_recursive:
  for path: List<&2, Above>
  for +node: Node
  Bool

# Whether an application's function is Pair: it builds a pair type (`A & B`), whose parts are types.
law is_pair:
  for kids: List<&2, Node>
  Bool

# Whether a node below `path` is in live code: a definition's body, outside types: an annotation's type, an equality, a
# function or pair type, a type's arguments. Types and equations are dead: the checker sees them, the program does not
# run them.
law is_live:
  for path: List<&2, Above>
  Bool

# The definitions of `nodes`, by the name the check gives them: read one with `Shared.Names.find`. Of two with one name, the
# later is kept.
law definitions:
  for nodes: List<&2, Node>
  for out: Map<&2, Maybe<&2, Node>>
  Map<&2, Maybe<&2, Node>>

# Where the parameter that declares `binder` is among `nodes`, a definition's, counting from 0.
law parameter:
  for nodes: List<&2, Node>
  for binder: U32
  Maybe<&2, Nat>

# A finding at `span`, if `hit` and `span` is known.
law finding:
  for severity: Severity
  for hit: Bool
  for span: Maybe<&2, Span>
  for text: String
  List<&2, Finding>

# An option's value as a number, a flag or text; a value of another kind, or none, gives 0, False, "".
law Value.number:
  for value: Maybe<&2, Value>
  U32

law Value.text:
  for value: Maybe<&2, Value>
  String

# The program's own files: not hub packages.
law Program.own:
  for sources: List<&2, Source>
  List<&2, Source>

# The type the first of `nodes` writes, as one name, or "" for another form (an application, a list).
law type_name:
  for nodes: List<&2, Node>
  String

# Whether a parallel let (two binders, at least) is among `nodes` or under them, or `found`.
law forks:
  for nodes: List<&2, Node>
  for found: Bool
  Bool

law Def.forks:
  for info: Maybe<&2, Def>
  Bool

# The definitions of the program's files, by the name the check gives them, onto `out`: read one with `Shared.Names.find`.
law Program.defs:
  for sources: List<&2, Source>
  for out: Map<&2, Maybe<&2, Def>>
  Map<&2, Maybe<&2, Def>>

# `seeds`, and the definitions of the program (`defs`, of `sources`) that call one of them, directly or through others.
# A definition calls only those above it, unless it is @unsafe, and the check gives a file's imports before it, so the
# first pass, in order, finds nearly all. Each pass but the last adds one at least, so as many passes as there are
# definitions find them all.
law Program.callers:
  for sources: List<&2, Source>
  for +defs: Map<&2, Maybe<&2, Def>>
  for seeds: Set()
  Set()

# The program from one of its files, built once for every file rule that runs on that file: its declarations, if a rule
# needs them (`declare`). The runner gives each rule its options.
law Here.of:
  for program: Program
  for +source: Source
  for declare: Bool
  Here

# The whole program, built once for every program rule: the declarations of its own files, if a rule needs them
# (`declare`).
law Whole.of:
  for program: Program
  for declare: Bool
  Whole

law Here.path:
  for here: Here
  String

# "" for the checked file.
law Here.namespace:
  for here: Here
  String

law Here.text:
  for here: Here
  String

# The file's nodes: its imports, then its declarations.
law Here.nodes:
  for here: Here
  List<&2, Node>

# Every file of the check, hub packages too.
law Here.sources:
  for here: Here
  List<&2, Source>

law Here.declarations:
  for here: Here
  List<&2, Declaration>

# The config's value, or the default.
law Here.option:
  for here: Here
  for name: String
  Maybe<&2, Value>

law Whole.declarations:
  for whole: Whole
  List<&2, Declaration>

law done:
  for findings: List<&2, Finding>
  Ask(List<&2, Finding>)

# How each type of `types` is shown, in order, asked in one round.
law show_all:
  for types: List<&2, TypeRef>
  Ask(List<&2, String>)
