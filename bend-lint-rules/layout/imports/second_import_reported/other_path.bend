# bend-lint: expect-next layout/imports@warning -- a.bend is imported twice, through another path
import Base
import ./a.bend as A
import a.bend as Again

def main() -> U32:
  1
