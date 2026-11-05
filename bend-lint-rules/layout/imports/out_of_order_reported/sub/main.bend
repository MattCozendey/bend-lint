# bend-lint: expect-next layout/imports@warning -- Base is not first, and paths are out of order
import ./c.bend as C
import ../b.bend as B
import Base
import ../a.bend as A

def main() -> U32:
  1
