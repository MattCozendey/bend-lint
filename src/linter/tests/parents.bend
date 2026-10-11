# tests/parents: a rule for run.test.ts. It looks up each node's parent by id, and says whether every lookup found it.
import Base
import ../lint.bend as Lint

def hit(want: U32, got: Maybe<&2, Lint.Node>) -> U32:
  match got:
    case Some{Lint.Node{id, p, o, s, n, b, q, sp, t}}:
      Bool.pick(U32, U32.is_eq(id, want), 1, 0)
    case None{}:
      Bool.pick(U32, U32.is_eq(want, 0), 1, 0)

def missed(nodes: List<&2, Lint.Node>, +here: Lint.Here, n: U32) -> U32:
  match nodes:
    case Nil{}:
      n
    case Con{Lint.Node{id, +parent, o, s, name, b, q, sp, t}, rest}:
      missed(rest, here, (n + 1 - hit(parent, Lint.Here.node(here, parent)): U32))

def said(missing: U32) -> String:
  Bool.pick(String, U32.is_eq(missing, 0), "every parent is found", "a parent is missing")

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(
    [
      Lint.Finding{
        Lint.Hint{},
        Lint.Span{Lint.Here.path(here), 0, 0},
        said(missed(Lint.Here.nodes(here), here, 0)),
        []
      }
    ]
  )

def rule() -> Lint.Rule:
  Lint.Rule{"tests/parents", Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
