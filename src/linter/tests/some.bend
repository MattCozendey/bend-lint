# tests/some: a program rule for run.test.ts, merged as some-entry. It finds what tests/every finds.
import Base
import ../lint.bend as Lint
import ./every.bend as Every

def rule() -> Lint.Rule:
  Lint.Rule{"tests/some", Lint.Needs{False{}, False{}}, [], Lint.OnProgram{False{}, Every.run}}
