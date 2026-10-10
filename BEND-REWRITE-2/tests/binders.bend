# tests/binders: a rule for facts.test.ts. It shows the type each binder declares, in one round, with its quantity:
# `name: type (quantity)`.
import Base
import ../lint.bend as Lint

# The spans, names (with quantities) and types of the binders that have facts, last first.
type Binders is Data:
  Binders{spans: List<&2, Lint.Span>, names: List<&2, String>, types: List<&2, Lint.TypeRef>}

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

def keep(node: Maybe<&2, Lint.Node>, q: Lint.Quantity, t: Lint.TypeRef, acc: Binders) -> Binders:
  match node acc:
    case Some{Lint.Node{id, p, o, syntax, name, b, nq, Some{span}, target}} Binders{spans, names, types}:
      Binders{span <> spans, (name ++ " (" ++ quantity(q) ++ ")") <> names, t <> types}
    case _ _:
      acc

def binders(facts: List<&2, Lint.Fact>, +here: Lint.Here, acc: Binders) -> Binders:
  match facts acc:
    case Nil{} Binders{spans, names, types}:
      Binders{
        List.reverse(&2, Lint.Span, spans),
        List.reverse(&2, String, names),
        List.reverse(&2, Lint.TypeRef, types)
      }
    case Con{Lint.Fact{n, Lint.OfBinder{}, q, t}, rest} _:
      binders(rest, here, keep(Lint.Here.node(here, n), q, t, acc))
    case Con{f, rest} _:
      binders(rest, here, acc)

def zip(spans: List<&2, Lint.Span>, names: List<&2, String>, shown: List<&2, String>, out: List<&2, Lint.Finding>) ->
  List<&2, Lint.Finding>:
  match spans names shown:
    case Con{s, ss} Con{n, ns} Con{t, ts}:
      zip(ss, ns, ts, Lint.Finding{Lint.Hint{}, s, n ++ ": " ++ t} <> out)
    case _ _ _:
      List.reverse(&2, Lint.Finding, out)

def described(b: Binders) -> Lint.Ask(List<&2, Lint.Finding>):
  match b:
    case Binders{spans, names, types}:
      do Lint.Ask<List<&2, Lint.Finding>>:
        shown : List<&2, String> <- Lint.show_all(types)
        return zip(spans, names, shown, [])

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  described(binders(Lint.Here.facts(here), here, Binders{[], [], []}))

def rule() -> Lint.Rule:
  Lint.FileRule{"tests/binders", Lint.Needs{True{}}, run}
