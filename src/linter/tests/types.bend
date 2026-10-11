# tests/types: a rule for facts.test.ts. It shows the type of each variable use that has a fact, in one round, then
# says whether the first two are the same type, in a second.
import Base
import ../lint.bend as Lint
import ../shared.bend as Shared

# The spans and types of the variable uses that have facts, last first.
type Vars is Data:
  Vars{spans: List<&2, Lint.Span>, types: List<&2, Lint.TypeRef>}

def keep(node: Lint.Node, t: Lint.TypeRef, acc: Vars) -> Vars:
  match node acc:
    case Lint.Node{id, p, o, Lint.Variable{}, name, b, q, Some{span}, target} Vars{spans, types}:
      Vars{span <> spans, t <> types}
    case _ _:
      acc

def vars(facts: List<&2, Lint.Fact>, acc: Vars) -> Vars:
  match facts acc:
    case Nil{} Vars{spans, types}:
      Vars{List.reverse(&2, Lint.Span, spans), List.reverse(&2, Lint.TypeRef, types)}
    case Con{Lint.Fact{n, Lint.OfTerm{}, q, u, t}, rest} _:
      vars(rest, keep(n, t, acc))
    case Con{f, rest} _:
      vars(rest, acc)

def zip(
  spans: List<&2, Lint.Span>,
  shown: List<&2, String>,
  out: List<&2, Lint.Finding>
) -> List<&2, Lint.Finding>:
  match spans shown:
    case Con{s, ss} Con{t, ts}:
      zip(ss, ts, Lint.Finding{Lint.Hint{}, s, "type: " ++ t, []} <> out)
    case _ _:
      List.reverse(&2, Lint.Finding, out)

def same_note(same: Bool, span: Lint.Span) -> List<&2, Lint.Finding>:
  match same:
    case True{}:
      [Lint.Finding{Lint.Hint{}, span, "the first two are the same type", []}]
    case False{}:
      [Lint.Finding{Lint.Hint{}, span, "the first two are different types", []}]

def compared(
  +spans: List<&2, Lint.Span>,
  types: List<&2, Lint.TypeRef>,
  +shown: List<&2, String>
) -> Lint.Ask(List<&2, Lint.Finding>):
  match spans types:
    case Con{s, ss} Con{a, Con{b, rest}}:
      do Lint.Ask<List<&2, Lint.Finding>>:
        same: Bool <- Lint.same(a, b)
        return Shared.append(&2, Lint.Finding, zip(spans, shown, []), same_note(same, s))
    case _ _:
      Lint.done(zip(spans, shown, []))

def described(v: Vars) -> Lint.Ask(List<&2, Lint.Finding>):
  match v:
    case Vars{+spans, +types}:
      do Lint.Ask<List<&2, Lint.Finding>>:
        shown: List<&2, String> <- Lint.show_all(types)
        compared(spans, types, shown)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  described(vars(Lint.Here.facts(here), Vars{[], []}))

def rule() -> Lint.Rule:
  Lint.Rule{"tests/types", Lint.Needs{True{}, False{}}, [], Lint.OnFile{run}}
