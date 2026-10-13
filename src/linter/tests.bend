# Rules for the linter's own tests (run.test.ts and facts.test.ts). Each def below `# Rules` gives one; testing.ts
# builds a program of it.
import Base
import ../shared/lists.bend as Lists
import ./lint.bend as Lint

# Types
# =====

# What a rule shows of the nodes it keeps, last first: where each is, what it says of it, and the type it asks about.
type Kept is Data:
  Kept{spans: List<&2, Lint.Span>, said: List<&2, String>, types: List<&2, Lint.TypeRef>}

# Functions
# =========
def quantity(q: Lint.Quantity) -> String:
  match q:
    case Lint.Erased{}:
      "erased"
    case Lint.Once{}:
      "once"
    case Lint.Many{}:
      "many"
    case Lint.Template{}:
      "template"

def Kept.add(span: Lint.Span, said: String, t: Lint.TypeRef, kept: Kept) -> Kept:
  match kept:
    case Kept{spans, saids, types}:
      Kept{span <> spans, said <> saids, t <> types}

# What a rule says of a node, by its fact (see the rules below), if it shows the fact.
type Shows is Data:
  Types{}
  Binders{}
  Terms{}

def term(syntax: Lint.Syntax) -> Maybe<&2, String>:
  match syntax:
    case Lint.Application{}:
      Some{"call"}
    case Lint.Construction{t}:
      Some{"construction"}
    case Lint.Literal{t}:
      Some{"literal"}
    case _:
      None{}

def shown(shows: Shows, +syntax: Lint.Syntax, name: String, fact: Lint.Fact) -> Maybe<&2, String>:
  match shows syntax fact:
    case Types{} Lint.Variable{b} Lint.Fact{Lint.OfTerm{}, q, u, t}:
      Some{"type: "}
    case Binders{} _ Lint.Fact{Lint.OfBinder{}, q, u, t}:
      Some{name ++ " (" ++ quantity(q) ++ "): "}
    case Terms{} _ Lint.Fact{Lint.OfTerm{}, q, u, t}:
      Maybe.map(&2, String, String, k => k ++ ": ", term(syntax))
    case _ _ _:
      None{}

def Kept.of(said: Maybe<&2, String>, span: Lint.Span, t: Lint.TypeRef, kept: Kept) -> Kept:
  match said:
    case Some{s}:
      Kept.add(span, s, t, kept)
    case None{}:
      kept

def Kept.facts(
  +shows: Shows,
  +syntax: Lint.Syntax,
  +name: String,
  +span: Lint.Span,
  facts: List<&2, Lint.Fact>,
  kept: Kept
) -> Kept:
  match facts:
    case Nil{}:
      kept
    case Con{Lint.Fact{r, q, u, +t}, rest}:
      Kept.facts(
        shows,
        syntax,
        name,
        span,
        rest,
        Kept.of(shown(shows, syntax, name, Lint.Fact{r, q, u, t}), span, t, kept)
      )

def Kept.node(+shows: Shows, +node: Lint.Node, kept: Kept) -> Kept:
  match node:
    case Lint.Node{syntax, name, Some{span}, kids, facts}:
      Kept.facts(shows, syntax, name, span, facts, kept)
    case _:
      kept

def zip(
  spans: List<&2, Lint.Span>,
  said: List<&2, String>,
  shown: List<&2, String>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match spans said shown:
    case Con{s, ss} Con{x, xs} Con{t, ts}:
      zip(ss, xs, ts, Lint.Finding{Lint.Hint{}, s, x ++ t, []} <> out)
    case _ _ _:
      List.reverse(&2, Lint.Finding, out)

def same_note(same: Bool, span: Lint.Span) -> List<&2, Lint.Finding>:
  match same:
    case True{}:
      [Lint.Finding{Lint.Hint{}, span, "the first two are the same type", []}]
    case False{}:
      [Lint.Finding{Lint.Hint{}, span, "the first two are different types", []}]

def compared(
  compare: Bool,
  spans: List<&2, Lint.Span>,
  types: List<&2, Lint.TypeRef>,
  found: List<&2, Lint.Finding>
) -> Lint.Ask(List<&2, Lint.Finding>):
  match compare spans types:
    case True{} Con{s, ss} Con{a, Con{b, rest}}:
      do Lint.Ask<List<&2, Lint.Finding>>:
        same: Bool <- Lint.same(a, b)
        return Lists.append(&2, Lint.Finding, found, same_note(same, s))
    case _ _ _:
      Lint.done(found)

# Each kept node's finding, with its type shown, in one round; with `compare`, then whether the first two types are the
# same, in a second.
def described(compare: Bool, k: Kept) -> Lint.Ask(List<&2, Lint.Finding>):
  match k:
    case Kept{spans, said, types}:
      +ordered = List.reverse(&2, Lint.TypeRef, types)
      +at = List.reverse(&2, Lint.Span, spans)
      do Lint.Ask<List<&2, Lint.Finding>>:
        shown: List<&2, String> <- Lint.show_all(ordered)
        compared(compare, at, ordered, zip(at, List.reverse(&2, String, said), shown, []))

def showing(shows: Shows, compare: Bool, here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  described(
    compare,
    Lint.fold(~Shows, ~Kept, ~Kept.node, shows, Lint.Here.nodes(here), Kept{[], [], []})
  )

def used.of(
  name: String,
  span: Maybe<&2, Lint.Span>,
  facts: List<&2, Lint.Fact>
) -> List<&2, Lint.Finding>:
  match span facts:
    case Some{s} Con{Lint.Fact{Lint.OfBinder{}, q, Some{u}, t}, rest}:
      [Lint.Finding{Lint.Hint{}, s, name ++ ": used " ++ quantity(u), []}]
    case Some{s} Con{f, rest}:
      used.of(name, Some{s}, rest)
    case _ _:
      []

def used(+u: Unit, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, Lint.Finding>:
  match node:
    case Lint.Node{syntax, name, span, kids, facts}:
      used.of(name, span, facts)

def asking(n: Nat, +t: Lint.TypeRef) -> Lint.Ask(List<&2, Lint.Finding>):
  match n:
    case 0n:
      Lint.done([])
    case 1n+k:
      Lint.Ask.bind(String, List<&2, Lint.Finding>, Lint.show(t), shown => asking(k, t))

def budget.of(t: Maybe<&2, Lint.TypeRef>) -> Lint.Ask(List<&2, Lint.Finding>):
  match t:
    case Some{x}:
      asking(100n, x)
    case None{}:
      Lint.done([])

def budget.first(k: Kept) -> Lint.Ask(List<&2, Lint.Finding>):
  match k:
    case Kept{spans, said, types}:
      budget.of(List.last(&2, Lint.TypeRef, types))

def written.said(syntax: Lint.Syntax, name: String) -> Maybe<&2, String>:
  match syntax:
    case Lint.Reference{t}:
      Some{"reference " ++ name}
    case Lint.Application{}:
      Some{"call"}
    case Lint.Lambda{b, q}:
      Some{"lambda " ++ name}
    case _:
      None{}

def written(+u: Unit, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, Lint.Finding>:
  match node:
    case Lint.Node{syntax, name, Some{span}, kids, facts}:
      Maybe.default(
        &2,
        List<&2, Lint.Finding>,
        Maybe.map(
          &2,
          String,
          List<&2, Lint.Finding>,
          s => [Lint.Finding{Lint.Hint{}, span, s, []}],
          written.said(syntax, name)
        ),
        []
      )
    case _:
      []

def renamed(+u: Unit, +path: List<&2, Lint.Above>, +node: Lint.Node) -> List<&2, Lint.Finding>:
  match node:
    case Lint.Node{Lint.Definition{t, unsafe}, "foo", Some{span}, kids, facts}:
      [
        Lint.Finding{
          Lint.Hint{},
          span,
          "foo",
          [Lint.Fix{"Rename to bar", [Lint.Rename{span, "bar"}]}]
        }
      ]
    case Lint.Node{Lint.Parameter{b, q}, "foo", Some{span}, kids, facts}:
      [
        Lint.Finding{
          Lint.Hint{},
          span,
          "foo",
          [Lint.Fix{"Rename to bar", [Lint.Rename{span, "bar"}]}]
        }
      ]
    case _:
      []

def marks(
  sources: List<&2, Lint.Source>,
  +count: Maybe<&2, U32>,
  +fix: List<&2, Lint.Fix>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match sources:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Source{+path, namespace, text, nodes}, rest}:
      marks(
        rest,
        count,
        fix,
        Lists.onto(
          &2,
          Lint.Finding,
          Lint.Finding{
            Lint.Hint{},
            Lint.Span{path, 0, 1},
            "at 0",
            fix
          }
            <> Lists.push(
              Lint.Finding,
              Maybe.map(
                &2,
                U32,
                Lint.Finding,
                +n => Lint.Finding{
                  Lint.Hint{},
                  Lint.Span{path, n, (n + 1: U32)},
                  "at the count",
                  []
                },
                count
              ),
              []
            ),
          out
        )
      )

def inserts(
  sources: List<&2, Lint.Source>,
  out: List<&2, Lint.Operation>
) -> List<&2, Lint.Operation>:
  match sources:
    case Nil{}:
      out
    case Con{Lint.Source{path, namespace, text, nodes}, rest}:
      inserts(rest, Lint.Replace{Lint.Span{path, 0, 0}, "# fixed\n"} <> out)

# In each file of a check, a mark at offset 0, and one at the number of files the check read.
def counted(+whole: Lint.Whole) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(
    marks(
      Lint.Whole.sources(whole),
      Some{U32.from_nat(Lists.length(&2, Lint.Source, Lint.Whole.sources(whole)))},
      [],
      []
    )
  )

# Rules
# =====

# tests/types: the type of each variable use that has a fact, in one round, then whether the first two are the same
# type, in a second.
def types() -> Lint.Rule:
  Lint.Rule{
    "tests/types",
    Lint.Needs{True{}, False{}},
    [],
    Lint.OnFile{here => showing(Types{}, True{}, here)}
  }

# tests/binders: the type each binder declares, with its quantity: `name (quantity): type`.
def binders() -> Lint.Rule:
  Lint.Rule{
    "tests/binders",
    Lint.Needs{True{}, False{}},
    [],
    Lint.OnFile{here => showing(Binders{}, False{}, here)}
  }

# tests/terms: the type of each call, construction and literal that has a fact: `call: type`.
def terms() -> Lint.Rule:
  Lint.Rule{
    "tests/terms",
    Lint.Needs{True{}, False{}},
    [],
    Lint.OnFile{here => showing(Terms{}, False{}, here)}
  }

# tests/uses: how often the body of each binder the checker closed uses it: `name: used quantity`.
def uses() -> Lint.Rule:
  Lint.Rule{
    "tests/uses",
    Lint.Needs{True{}, False{}},
    [],
    Lint.OnFile{
      here => Lint.done(Lint.visit(~Unit, ~Lint.Finding, ~used, Unit{}, Lint.Here.nodes(here)))
    }
  }

# tests/budget: one question per round, more rounds than the runner allows.
def budget() -> Lint.Rule:
  Lint.Rule{
    "tests/budget",
    Lint.Needs{True{}, False{}},
    [],
    Lint.OnFile{
      here => budget.first(
        Lint.fold(~Shows, ~Kept, ~Kept.node, Types{}, Lint.Here.nodes(here), Kept{[], [], []})
      )
    }
  }

# tests/file: one mark at the start of each linted file.
def file() -> Lint.Rule:
  Lint.Rule{
    "tests/file",
    Lint.Needs{False{}, False{}},
    [],
    Lint.OnFile{
      here => Lint.done(
        [Lint.Finding{Lint.Hint{}, Lint.Span{Lint.Here.path(here), 0, 0}, "linted", []}]
      )
    }
  }

# tests/written: each reference, call and lambda that the file writes.
def written.rule() -> Lint.Rule:
  Lint.Rule{
    "tests/written",
    Lint.Needs{False{}, False{}},
    [],
    Lint.OnFile{
      here => Lint.done(Lint.visit(~Unit, ~Lint.Finding, ~written, Unit{}, Lint.Here.nodes(here)))
    }
  }

# tests/rename: offers to rename each def and each parameter named foo to bar.
def rename() -> Lint.Rule:
  Lint.Rule{
    "tests/rename",
    Lint.Needs{False{}, False{}},
    [],
    Lint.OnFile{
      here => Lint.done(Lint.visit(~Unit, ~Lint.Finding, ~renamed, Unit{}, Lint.Here.nodes(here)))
    }
  }

# tests/every: a program rule merged as every-entry: in each file of a check, a mark at offset 0, and one at the number
# of files the check read.
def every() -> Lint.Rule:
  Lint.Rule{"tests/every", Lint.Needs{False{}, False{}}, [], Lint.OnProgram{True{}, counted}}

# tests/some: the same, merged as some-entry.
def some() -> Lint.Rule:
  Lint.Rule{"tests/some", Lint.Needs{False{}, False{}}, [], Lint.OnProgram{False{}, counted}}

# tests/across: a program rule: in each file of a check, a mark at offset 0, with a fix that writes a comment line at
# the start of every file.
def across() -> Lint.Rule:
  Lint.Rule{
    "tests/across",
    Lint.Needs{False{}, False{}},
    [],
    Lint.OnProgram{
      False{},
      whole => Lint.done(
        marks(
          Lint.Whole.sources(whole),
          None{},
          [Lint.Fix{"Mark every file", inserts(Lint.Whole.sources(whole), [])}],
          []
        )
      )
    }
  }
