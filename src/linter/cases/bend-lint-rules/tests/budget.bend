import Base
import ../../../lint.bend as Lint
import ../../../tests.bend as Tests

def rule() -> Lint.Rule:
  Tests.budget()
