import Base
import ./util.bend as U
# bend-lint: expect-next no_unused/imports@warning -- V is never used
import ./util.bend as V

def three() -> U32:
  (U.two() + 1 : U32)
