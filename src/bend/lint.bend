# The contract between bend-lint and a rule written in Bend. A rule file
# imports this file and defines:
#
#   def id() -> String:          # namespace/name, the code of its findings
#   def facts() -> Lint.Want:    # Lint.NoFacts{}, or the facts it needs
#   def options() -> List<&2, Lint.Declared>:  # only if it has options
#   def entries() -> Lint.Entries:  # only if it says how entries count
#   def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
#   def main() -> IO(Unit):
#     Lint.serve(run)
#
# A rule with facts reads them one at a time, with fold_facts or
# next_fact. Offsets count characters (code points) from the start of a
# file. The rule's options come from bend-lint.json, checked against
# options(); read them with option_number, option_flag and option_text.
import Base

# A type with its scope, and a node of a checked body: indexes into
# bend-lint's tables for one run. Only the effects below read them.
type Term is Data:
  Term{id: U32}

type Node is Data:
  Node{id: U32}

type Source is Data:
  Source{path: String, text: String, root: Bool}

# An option's value: a whole number (a U32), a boolean, or text.
type Value is Data:
  Num{value: U32}
  Flag{value: Bool}
  Text{value: String}

type Option is Data:
  Option{key: String, value: Value}

# What an option accepts: a whole number from minimum to maximum, a
# boolean, text (one of choices, or any text if there are none), or what
# one of the specs accepts.
type Spec is Data:
  NumberOption{minimum: U32, maximum: U32}
  FlagOption{}
  TextOption{choices: List<&2, String>}
  AnyOption{specs: List<&2, Spec>}

type Declared is Data:
  Declared{key: String, default: Value, spec: Spec}

# File: facts of the file the run is for. Program: of every file the check
# read, never Base.
type Scope is Data:
  File{}
  Program{}

# The facts a rule needs. A fact must match each list; an empty list
# matches all. kinds: the term's kind, annotations stripped (Var, Ref, App,
# ...). defs: the def whose body holds the term (a template's instances
# count as the template). names: the name a Var or Ref points to.
# instances: True{} adds the facts of template instances (generic~0); only
# with Program{}.
type Want is Data:
  NoFacts{}
  Want{scope: Scope, kinds: List<&2, String>, defs: List<&2, String>, names: List<&2, String>, instances: Bool}

# How a rule of scope Program{} counts what the checks of several entries
# find: SomeEntry{} (the default) keeps a finding one of them makes,
# EveryEntry{} only one they all make.
type Entries is Data:
  SomeEntry{}
  EveryEntry{}

type Span is Data:
  Span{path: String, beg: U32, end: U32}

type DeclarationKind is Data:
  Import{}
  Definition{}
  Datatype{}
  Constructor{}
  Parameter{}
  Variable{}
  Field{}

type Reference is Data:
  Reference{owner: String, span: Span}

type Declaration is Data:
  Declaration{kind: DeclarationKind, name: String, owner: Maybe<&2, String>, span: Span, references: List<&2, Reference>}

type Severity is Data:
  Error{}
  Warning{}
  Information{}
  Hint{}

# Safe keeps behavior; Suggested may change it; Dangerous may break code.
type Applicability is Data:
  Safe{}
  Suggested{}
  Dangerous{}

type Edit is Data:
  Edit{span: Span, text: String}

type Fix is Data:
  Fix{title: String, applicability: Applicability, edits: List<&2, Edit>}

# How many times a term may be used.
type Quantity is Data:
  Erased{}
  Once{}
  Many{}

type Use is Data:
  Use{name: String, quantity: Quantity}

# What the checker found for a node: the def whose body holds it, whether
# that def is a template instance, how many times the term is demanded,
# the type it was checked as, and the source it checked, annotations
# included (the node itself may have no span).
type Fact is Data:
  Fact{node: Node, owner: String, inst: Bool, quantity: Quantity, term: Term, span: Maybe<&2, Span>}

# A finding. about: the fact it is about, if any; its scope shows as the
# finding's context.
type Diag is Data:
  Diag{severity: Severity, message: String, span: Maybe<&2, Span>, fixes: List<&2, Fix>, about: Maybe<&2, Fact>}

# A finding of an earlier rule, with that rule's id.
type Found is Data:
  Found{code: String, diag: Diag}

# root: the file the run is for. sources: every file the check read.
# prior: what earlier rules found in the files the run reaches.
type Input is Data:
  Input{root: Source, sources: List<&2, Source>, options: List<&2, Option>, prior: List<&2, Found>}

# A node: its kind, annotations kept (Ann, Var, App, ...), the name a Var
# or Ref points to (else ""), its span, and its children, in bend's order.
type Shape is Data:
  Shape{kind: String, name: String, span: Maybe<&2, Span>, children: List<&2, Node>}

# A finding at a span, with no fix, about no fact.
def diag(severity: Severity, message: String, span: Span) -> Diag:
  Diag{severity, message, Some{span}, [], None{}}

def input() -> IO(Input):
  import "./effects.js"

def report(diags: List<&2, Diag>) -> IO(Unit):
  import "./effects.js"

# The next fact the rule asked for, or None{} when none are left.
def next_fact() -> IO(Maybe<&2, Fact>):
  import "./effects.js"

# One step of fold_facts: stop at None{}, else run step and go on.
def fold_next(~A: Type, ~step: A -> @+f: Fact -> IO(A), m: Maybe<&2, Fact>, acc: A, again: A -> IO(A)) -> IO(A):
  match m:
    case None{}:
      IO.pure(A, acc)
    case Some{f}:
      IO.bind(A, A, step(acc, f), again)

# Runs step on each fact the rule asked for, in order, from acc; step is
# a def, given as ~name, that takes its fact as +f. Facts come one at a
# time, so a big file does not build one big list.
@unsafe
def fold_facts(~A: Type, ~step: A -> @+f: Fact -> IO(A), acc: A) -> IO(A):
  do IO<A>:
    m : Maybe<&2, Fact> <- next_fact()
    fold_next(~A, ~step, m, acc, a => fold_facts(~A, ~step, a))

# Whether `text` declares what the linted file declares, compared as
# parsed, not checked: a formatter's guard.
def same_declarations(text: String) -> IO(Bool):
  import "./effects.js"

# Whether the run was aborted; a long rule can stop early.
def aborted() -> IO(Bool):
  import "./effects.js"

# The text under a span, in the file on disk.
def text(span: Span) -> IO(String):
  import "./effects.js"

def declarations() -> IO(List<&2, Declaration>):
  import "./effects.js"

# A def's checked body, if it has one.
def body(name: String) -> IO(Maybe<&2, Node>):
  import "./effects.js"

def shape(n: Node) -> IO(Shape):
  import "./effects.js"

# The node and every node under it, parents first.
def nodes(n: Node) -> IO(List<&2, Node>):
  import "./effects.js"

def parent(n: Node) -> IO(Maybe<&2, Node>):
  import "./effects.js"

# The node without its annotations.
def strip(n: Node) -> IO(Node):
  import "./effects.js"

# The node's fact, if the rule asked for it.
def fact(n: Node) -> IO(Maybe<&2, Fact>):
  import "./effects.js"

# The type of the binder a Var fact refers to.
def binder(f: Fact) -> IO(Maybe<&2, Term>):
  import "./effects.js"

# The variables the fact's term uses, each with how many times.
def uses(f: Fact) -> IO(List<&2, Use>):
  import "./effects.js"

# Whether two types are equal, as the checker compares them in the scope
# of the first.
def same(a: Term, b: Term) -> IO(Bool):
  import "./effects.js"

def show(t: Term) -> IO(String):
  import "./effects.js"

# The normal form of a type, in its scope.
def normal(t: Term) -> IO(Term):
  import "./effects.js"

def pick(hit: Bool, v: Value, later: Maybe<&2, Value>) -> Maybe<&2, Value>:
  match hit:
    case True{}:
      Some{v}
    case False{}:
      later

# An option's value; for an AnyOption, match on it.
def find(opts: List<&2, Option>, +key: String) -> Maybe<&2, Value>:
  match opts:
    case Nil{}:
      None{}
    case Con{Option{k, v}, rest}:
      pick(String.eq(k, key), v, find(rest, key))

def number_of(m: Maybe<&2, Value>) -> U32:
  match m:
    case Some{Num{n}}:
      n
    case Some{Flag{b}}:
      0
    case Some{Text{t}}:
      0
    case None{}:
      0

# A declared option's value; options() makes sure it is there.
def option_number(opts: List<&2, Option>, key: String) -> U32:
  number_of(find(opts, key))

def flag_of(m: Maybe<&2, Value>) -> Bool:
  match m:
    case Some{Flag{b}}:
      b
    case Some{Num{n}}:
      False{}
    case Some{Text{t}}:
      False{}
    case None{}:
      False{}

def option_flag(opts: List<&2, Option>, key: String) -> Bool:
  flag_of(find(opts, key))

def text_of(m: Maybe<&2, Value>) -> String:
  match m:
    case Some{Text{t}}:
      t
    case Some{Num{n}}:
      ""
    case Some{Flag{b}}:
      ""
    case None{}:
      ""

def option_text(opts: List<&2, Option>, key: String) -> String:
  text_of(find(opts, key))

def serve(run: Input -> IO(List<&2, Diag>)) -> IO(Unit):
  IO.bind(Input, Unit, input(), i => IO.bind(List<&2, Diag>, Unit, run(i), report))
