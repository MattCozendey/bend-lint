# tests/terms: a rule for facts.test.ts. It shows the type of each call, construction and literal that has a fact, in
# one round: `call: type`, `construction: type`, `literal: type`.
import Base
import ../lint.bend as Lint

# The spans, kinds and types of the terms that have facts, last first.
type Terms is Data:
  Terms{spans: List<&2, Lint.Span>, kinds: List<&2, String>, types: List<&2, Lint.TypeRef>}

def kind(syntax: Lint.Syntax) -> Maybe<&2, String>:
  match syntax:
    case Lint.Application{}:
      Some{"call"}
    case Lint.Construction{}:
      Some{"construction"}
    case Lint.Literal{}:
      Some{"literal"}
    case _:
      None{}

def kept(k: Maybe<&2, String>, span: Lint.Span, t: Lint.TypeRef, acc: Terms) -> Terms:
  match k acc:
    case Some{x} Terms{spans, kinds, types}:
      Terms{span <> spans, x <> kinds, t <> types}
    case None{} _:
      acc

def keep(node: Lint.Node, t: Lint.TypeRef, acc: Terms) -> Terms:
  match node:
    case Lint.Node{id, p, o, syntax, name, b, q, Some{span}, target}:
      kept(kind(syntax), span, t, acc)
    case _:
      acc

def terms(facts: List<&2, Lint.Fact>, acc: Terms) -> Terms:
  match facts acc:
    case Nil{} Terms{spans, kinds, types}:
      Terms{
        List.reverse(&2, Lint.Span, spans),
        List.reverse(&2, String, kinds),
        List.reverse(&2, Lint.TypeRef, types)
      }
    case Con{Lint.Fact{n, Lint.OfTerm{}, q, t}, rest} _:
      terms(rest, keep(n, t, acc))
    case Con{f, rest} _:
      terms(rest, acc)

def zip(spans: List<&2, Lint.Span>, kinds: List<&2, String>, shown: List<&2, String>, out: List<&2, Lint.Finding>) ->
  List<&2, Lint.Finding>:
  match spans kinds shown:
    case Con{s, ss} Con{k, ks} Con{t, ts}:
      zip(ss, ks, ts, Lint.Finding{Lint.Hint{}, s, k ++ ": " ++ t} <> out)
    case _ _ _:
      List.reverse(&2, Lint.Finding, out)

def described(v: Terms) -> Lint.Ask(List<&2, Lint.Finding>):
  match v:
    case Terms{spans, kinds, types}:
      do Lint.Ask<List<&2, Lint.Finding>>:
        shown : List<&2, String> <- Lint.show_all(types)
        return zip(spans, kinds, shown, [])

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  described(terms(Lint.Here.facts(here), Terms{[], [], []}))

def rule() -> Lint.Rule:
  Lint.FileRule{"tests/terms", Lint.Needs{True{}}, run}
