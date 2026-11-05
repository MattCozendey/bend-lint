# bend-lint: expect-next layout/imports@warning -- Base is imported twice
import Base
import ./a.bend as A
import Base

def main() -> U32:
  1
