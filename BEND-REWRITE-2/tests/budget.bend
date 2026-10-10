# tests/budget: a rule for facts.test.ts. It asks one question per round, more rounds than the runner allows.
import Base
import ../lint.bend as Lint

# `n` rounds of one question each, about `t`.
def asking(n: Nat, +t: Lint.TypeRef) -> Lint.Ask(List<&2, Lint.Finding>):
  match n:
    case 0n:
      Lint.done([])
    case 1n+k:
      Lint.Ask.bind(String, List<&2, Lint.Finding>, Lint.show(t), shown => asking(k, t))

def first(facts: List<&2, Lint.Fact>) -> Lint.Ask(List<&2, Lint.Finding>):
  match facts:
    case Con{Lint.Fact{n, r, q, t}, rest}:
      asking(100n, t)
    case Nil{}:
      Lint.done([])

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  first(Lint.Here.facts(here))

def rule() -> Lint.Rule:
  Lint.FileRule{"tests/budget", Lint.Needs{True{}}, [], run}
