import Base
# bend-lint: expect-next tests/written@warning -- met
def v() -> U32:
  1
# bend-lint: expect-next tests/written@error -- wrong severity
def w() -> U32:
  1
