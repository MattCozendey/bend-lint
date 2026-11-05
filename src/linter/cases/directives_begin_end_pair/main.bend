import Base
# bend-lint: disable-begin tests/written -- region not-expected-because: it is not always found
def v() -> U32:
  1
# bend-lint: disable-end tests/written
def w() -> U32:
  1
# bend-lint: disable-end tests/written
# bend-lint: disable-begin tests/written -- never closed not-expected-because: it is not always found
# bend-lint: expect-next tests/written@warning -- b
# bend-lint: disable-next tests/written -- a not-expected-because: it is not always found
