# tests/rename: a rule for run.test.ts. It offers to rename each def and each parameter named foo to bar.
import Base
import ../lint.bend as Lint

def offer(foo: Bool, id: U32, span: Lint.Span) -> List<&2, Lint.Finding>:
  match foo:
    case True{}:
      [
        Lint.Finding{
          Lint.Hint{},
          span,
          "foo",
          [Lint.Fix{"Rename to bar", [Lint.Rename{id, "bar"}]}]
        }
      ]
    case False{}:
      []

def judge(node: Lint.Node) -> List<&2, Lint.Finding>:
  match node:
    case Lint.Node{
      id,
      parent,
      owner,
      Lint.Definition{},
      name,
      binder,
      quantity,
      Some{span},
      target
    }:
      offer(String.eq(name, "foo"), id, span)
    case Lint.Node{id, parent, owner, Lint.Parameter{}, name, binder, quantity, Some{span}, target}:
      offer(String.eq(name, "foo"), id, span)
    case _:
      []

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(Lint.findings(~Lint.Node, ~judge, Lint.Here.nodes(here)))

def rule() -> Lint.Rule:
  Lint.Rule{"tests/rename", Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
