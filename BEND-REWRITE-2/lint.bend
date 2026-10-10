# bend-lint, in Bend: what a rule sees. A rule file imports this file; a rules program imports cli.bend too, and calls
# it with its rules (main.bend is the default one).
#
# Design
# - Only Bend rules. The target is the C lane; the JS lane must work too.
# - The rules program is an ordinary Bend program: `bend main.bend -o lint` builds it once. No restart, no rule cache.
# - Bend's checker is TS for now. server.ts runs the program and answers its questions about Bend files over local
#   TCP (wire.bend). When the checker is Bend, the server goes, and these questions become calls.
# - Rules are pure, so they run in parallel. Questions to the checker will go through an Ask monad, answered in
#   batches.
# - A rule reads the program once per check, shared by every rule: a flat list of syntax nodes per file, parents
#   first, and the file's declarations with their uses, built once.
# - Findings come first. A fix will be a list of typed operations that the rule requests; the linter plans them and
#   decides their safety. Until Bend's checker is Bend, every fix is Dangerous.
#
# Files: lint.bend (this), shared.bend (what more than one file uses), wire.bend (the server), program.bend (the
# program a check gives, and its declarations), directives.bend (bend-lint: comments), cli.bend (running and output).
import Base
import ./shared.bend as Shared

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

# Where something is: its file, and offsets in code points.
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

# A name a node declares, and the nodes that use it, in order.
type Declaration is Data:
  Declaration{node: Node, references: List<&2, Node>}

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

# The namespace of a global name: what comes before its first ":", or "" for Base and the checked file's own names.
def Name.namespace(name: String) -> String:
  Shared.before(name, ':')

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

# What a rule finds: how severe, where, and what to do about it.
type Finding is Data:
  Finding{severity: Severity, span: Span, message: String}

# A finding, with the id of the rule that found it.
type Found is Data:
  Found{rule: String, finding: Finding}

# What a file rule sees: the program, from one of its files, and that file's declarations, with their uses in it.
type Here is Data:
  Here{program: Program, source: Source, declarations: List<&2, Declaration>}

# What a program rule sees: the program (its files, hub packages aside), and every declaration of its files, with their
# uses in all of them.
type Whole is Data:
  Whole{program: Program, declarations: List<&2, Declaration>}

# A rule: its id (`namespace/.../name`), and what it finds. A file rule runs once per linted file, and may report only
# in it. A program rule runs once per check, and may report in any file; what it finds in a file that is not linted
# is dropped.
type Rule is Type:
  FileRule{id: String, run: @+here: Here -> List<&2, Finding>}
  ProgramRule{id: String, run: @+whole: Whole -> List<&2, Finding>}

# The nodes of the file a rule runs on, parents first.
def Here.nodes(here: Here) -> List<&2, Node>:
  match here:
    case Here{program, Source{path, namespace, text, nodes}, declarations}:
      nodes

def Here.declarations(here: Here) -> List<&2, Declaration>:
  match here:
    case Here{program, source, declarations}:
      declarations

def Whole.declarations(whole: Whole) -> List<&2, Declaration>:
  match whole:
    case Whole{program, declarations}:
      declarations

def Whole.sources(whole: Whole) -> List<&2, Source>:
  match whole:
    case Whole{Program{sources}, declarations}:
      sources

def findings.go(~A: Data, ~f: A -> List<&2, Finding>, xs: List<&2, A>, out: List<&2, Finding>) -> List<&2, Finding>:
  match xs:
    case Nil{}:
      List.reverse(&2, Finding, out)
    case Con{x, rest}:
      findings.go(~A, ~f, rest, Shared.onto(Finding, f(x), out))

# The findings `f(x)` gives for each `x` of `xs`, in order.
def findings(~A: Data, ~f: A -> List<&2, Finding>, xs: List<&2, A>) -> List<&2, Finding>:
  findings.go(~A, ~f, xs, [])
