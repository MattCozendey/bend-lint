# bend-lint, in Bend: what a rule sees. A rule file imports this file; a rules program imports cli.bend too, and calls
# it with its rules (main.bend is the default one).
#
# Design
# - Only Bend rules. The target is the C lane; the JS lane must work too.
# - The rules program is an ordinary Bend program: `bend main.bend -o lint` builds it once. No restart, no rule cache.
# - Bend's checker is TS for now. server.ts runs the program and answers its questions about Bend files over local
#   TCP (wire.bend). When the checker is Bend, the server goes, and these questions become calls.
# - Rules are pure, so they run in parallel. A rule asks the checker about types through Ask (`do Lint.Ask<A>:`);
#   the runner answers every rule's questions of a round in one batch.
# - A rule reads the program once per check, shared by every rule: a flat list of syntax nodes per file, parents
#   first; the file's declarations with their uses, built once; and, if it needs them, the checker's facts on the
#   source's terms, each tied to its node.
# - Findings come first. A fix will be a list of typed operations that the rule requests; the linter plans them and
#   decides their safety. Until Bend's checker is Bend, every fix is Dangerous.
#
# Files: lint.bend (this), shared.bend (what more than one file uses), wire.bend (the server), program.bend (the
# program a check gives, and its declarations), directives.bend (bend-lint: comments), cli.bend (running and output).
import Base
import ./shared.bend as Shared

# Program
# =======

# What a syntax node is: a declaration, a part of one, a term, or a pattern, as Bend's parser reads it. An import's
# written path is an ImportPath under it; `import Base` writes none.
type Syntax is Data:
  Import{}
  ImportPath{}
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

# A type the checker holds: a handle, good in the check it came from. Rules ask about it (show, same, normal). Two
# types are the same only over the binders their scopes share: `A` of one def is not `A` of another.
type TypeRef is Data:
  TypeRef{check: U32, id: U32}

# What a fact says of its node: the type its term has, or the type its binder declares (a parameter, field, pattern
# variable, lambda, forall or let binding).
type Role is Data:
  OfTerm{}
  OfBinder{}

# What the checker found for a node of the source: the node, what the fact says of it, the quantity (how
# often the term is demanded, or the binder's), and the type. A fact is never wrong, but a node can have none: a term
# the checker rewrote into another (a scrutinee used again, a call a template took) is not typed as itself. A node
# has one fact per distinct type: pattern compilation can check one term in several branches, under different
# refinements. Only for a rule that needs facts.
type Fact is Data:
  Fact{node: Node, role: Role, quantity: Quantity, checked: TypeRef}

# A file the check parsed: its path, its namespace in the check, its text, its nodes (parents first), and the
# checker's facts on its terms, if a rule needs them.
type Source is Data:
  Source{path: String, namespace: String, text: String, nodes: List<&2, Node>, facts: List<&2, Fact>}

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

# Where each finding starts, in order.
def Found.offsets(founds: List<&2, Found>, out: List<&2, U32>) -> List<&2, U32>:
  match founds:
    case Nil{}:
      List.reverse(&2, U32, out)
    case Con{Found{rule, Finding{severity, Span{path, beg, end}, message}}, rest}:
      Found.offsets(rest, beg <> out)

# A file's nodes by id: `first` is its first node's.
type Index is Data:
  Index{first: U32, nodes: Shared.Indexed<Node>}

# Options
# =======

# An option's value: a whole number, a flag, or text.
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

# What a file rule sees: the program, from one of its files; that file's declarations, with their uses in it; its
# nodes by id; and the rule's options, each declared one with its value.
type Here is Data:
  Here{
    program: Program,
    source: Source,
    declarations: List<&2, Declaration>,
    index: Index,
    options: List<&2, Shared.Named<Value>>
  }

# What a program rule sees: the program (its files, hub packages aside); every declaration of its files, with their
# uses in all of them; and the rule's options.
type Whole is Data:
  Whole{program: Program, declarations: List<&2, Declaration>, options: List<&2, Shared.Named<Value>>}

# Asking the checker
# ==================

# A question to the checker about types: how a type is shown (as the file it came from spells it), whether two types
# are the same (as the checker compares them), and a type's normal form.
type Question is Data:
  Show{of: TypeRef}
  Same{a: TypeRef, b: TypeRef}
  Normal{of: TypeRef}

type Answer is Data:
  Shown{text: String}
  Equal{same: Bool}
  Normalized{to: TypeRef}

# A run so far: finished, or waiting for the answers to its questions, in order.
type Step<-R: Type> is Type:
  Finished{value: R}
  Pending{questions: List<&2, Question>, then: List<&2, Answer> -> Step<R>}

# A computation that may ask the checker: `do Lint.Ask<A>:` blocks build it. It is given what to do with its value,
# and gives a Step, so binding it needs no recursion; the runner answers the questions in rounds.
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

# Findings, with nothing to ask.
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

def Answer.type(+fallback: TypeRef, answers: List<&2, Answer>) -> TypeRef:
  match answers:
    case Con{Normalized{to}, rest}:
      to
    case _:
      fallback

# How a type is shown, as the file it came from spells it.
def show(t: TypeRef) -> Ask(String):
  Ask.bind(List<&2, Answer>, String, ask([Show{t}]), answers => Ask.pure(String, Answer.text(answers)))

# Whether two types are the same, as the checker compares them.
def same(a: TypeRef, b: TypeRef) -> Ask(Bool):
  Ask.bind(List<&2, Answer>, Bool, ask([Same{a, b}]), answers => Ask.pure(Bool, Answer.same(answers)))

# A type's normal form.
def normal(+t: TypeRef) -> Ask(TypeRef):
  Ask.bind(List<&2, Answer>, TypeRef, ask([Normal{t}]), answers => Ask.pure(TypeRef, Answer.type(t, answers)))

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

# What a rule needs collected for it: the checker's facts, which cost time and memory.
type Needs is Data:
  Needs{facts: Bool}

# Which of a program rule's findings stay when several entries check the named file: those some check finds, or those
# every check finds. If an entry that reads the named file fails its check, an every rule does not run.
type Entries is Data:
  SomeEntry{}
  EveryEntry{}

# A rule: its id (`namespace/.../name`), and what it finds. A file rule runs once per linted file, and may report only
# in it. A program rule runs once per check, and may report in any file; what it finds in a file that is not linted
# is dropped.
type Rule is Type:
  FileRule{id: String, needs: Needs, options: List<&2, Declared>, run: @+here: Here -> Ask(List<&2, Finding>)}
  ProgramRule{
    id: String,
    entries: Entries,
    needs: Needs,
    options: List<&2, Declared>,
    run: @+whole: Whole -> Ask(List<&2, Finding>)
  }

# The path of the file a rule runs on.
def Here.path(here: Here) -> String:
  match here:
    case Here{program, Source{path, namespace, text, nodes, facts}, declarations, index, options}:
      path

# The namespace of the file a rule runs on, in its check: "" for the checked file.
def Here.namespace(here: Here) -> String:
  match here:
    case Here{program, Source{path, namespace, text, nodes, facts}, declarations, index, options}:
      namespace

# The text of the file a rule runs on, as on disk.
def Here.text(here: Here) -> String:
  match here:
    case Here{program, Source{path, namespace, text, nodes, facts}, declarations, index, options}:
      text

# The nodes of the file a rule runs on, parents first.
def Here.nodes(here: Here) -> List<&2, Node>:
  match here:
    case Here{program, Source{path, namespace, text, nodes, facts}, declarations, index, options}:
      nodes

# The checker's facts on the terms of the file a rule runs on, if the rule needs them.
def Here.facts(here: Here) -> List<&2, Fact>:
  match here:
    case Here{program, Source{path, namespace, text, nodes, facts}, declarations, index, options}:
      facts

def Here.declarations(here: Here) -> List<&2, Declaration>:
  match here:
    case Here{program, source, declarations, index, options}:
      declarations

# The node with id `id`, of the file a rule runs on: a node's parent, say.
def Here.node(here: Here, +id: U32) -> Maybe<&2, Node>:
  match here:
    case Here{program, source, declarations, Index{+first, nodes}, options}:
      Shared.Indexed.get(Node, nodes, (id - first : U32))

# The value of the rule's option `name`: the config's, or its default.
def Here.option(here: Here, +name: String) -> Maybe<&2, Value>:
  match here:
    case Here{program, source, declarations, index, options}:
      Shared.lookup(Value, name, options)

def Whole.declarations(whole: Whole) -> List<&2, Declaration>:
  match whole:
    case Whole{program, declarations, options}:
      declarations

def Whole.sources(whole: Whole) -> List<&2, Source>:
  match whole:
    case Whole{Program{sources}, declarations, options}:
      sources

# The value of the rule's option `name`: the config's, or its default.
def Whole.option(whole: Whole, +name: String) -> Maybe<&2, Value>:
  match whole:
    case Whole{program, declarations, options}:
      Shared.lookup(Value, name, options)

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

def findings.go(~A: Data, ~f: A -> List<&2, Finding>, xs: List<&2, A>, out: List<&2, Finding>) -> List<&2, Finding>:
  match xs:
    case Nil{}:
      List.reverse(&2, Finding, out)
    case Con{x, rest}:
      findings.go(~A, ~f, rest, Shared.onto(&2, Finding, f(x), out))

# The findings `f(x)` gives for each `x` of `xs`, in order.
def findings(~A: Data, ~f: A -> List<&2, Finding>, xs: List<&2, A>) -> List<&2, Finding>:
  findings.go(~A, ~f, xs, [])
