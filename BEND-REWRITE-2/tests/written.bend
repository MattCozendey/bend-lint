# tests/written: a rule for run.test.ts. It shows each reference, call and lambda that has a range: what a file writes.
import Base
import ../lint.bend as Lint

def shown(syntax: Lint.Syntax, +name: String) -> Maybe<&2, String>:
  match syntax:
    case Lint.Reference{}:
      Some{"reference " ++ name}
    case Lint.Application{}:
      Some{"call"}
    case Lint.Lambda{}:
      Some{"lambda " ++ name}
    case _:
      None{}

def finding(said: Maybe<&2, String>, span: Lint.Span) -> List<&2, Lint.Finding>:
  match said:
    case Some{s}:
      [Lint.Finding{Lint.Hint{}, span, s}]
    case None{}:
      []

def written(n: Lint.Node) -> List<&2, Lint.Finding>:
  match n:
    case Lint.Node{id, parent, owner, syntax, name, binder, quantity, Some{span}, target}:
      finding(shown(syntax, name), span)
    case _:
      []

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(Lint.findings(~Lint.Node, ~written, Lint.Here.nodes(here)))

def rule() -> Lint.Rule:
  Lint.FileRule{"tests/written", Lint.Needs{False{}}, [], run}
