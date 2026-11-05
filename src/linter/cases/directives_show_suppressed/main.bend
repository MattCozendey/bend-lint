import Base
# bend-lint: disable-next tests/written -- kept on purpose not-expected-because: it is not always found
def v() -> U32:
  1
def w() -> U32: # bend-lint: disable-line tests/written -- also kept not-expected-because: it is not always found
  1
