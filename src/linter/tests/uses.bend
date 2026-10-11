# tests/uses: a rule for facts.test.ts. It shows how often the body of each binder the checker closed uses it:
# `name: used quantity`.
import Base
import ../lint.bend as Lint
import ./binders.bend as Binders

def used(facts: List<&2, Lint.Fact>, out: List<&2, Lint.Finding>) -> List<&2, Lint.Finding>:
  match facts:
    case Nil{}:
      List.reverse(&2, Lint.Finding, out)
    case Con{Lint.Fact{Lint.Node{id, p, o, syntax, name, b, q, Some{span}, target}, Lint.OfBinder{}, nq, Some{u}, t}, rest}:
      used(rest, Lint.Finding{Lint.Hint{}, span, name ++ ": used " ++ Binders.quantity(u), []} <> out)
    case Con{f, rest}:
      used(rest, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(used(Lint.Here.facts(here), []))

def rule() -> Lint.Rule:
  Lint.Rule{"tests/uses", Lint.Needs{True{}, False{}}, [], Lint.OnFile{run}}
