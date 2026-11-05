# bend-lint: expect-next layout/imports@warning -- a.bend and Base are imported twice
import Base
import ./a.bend as A
import ./a.bend as Again
import Base

def Again.same(x):
  {==}

def main() -> U32:
  (Again.one() + A.one() : U32)
