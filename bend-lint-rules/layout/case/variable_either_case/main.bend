import Base

def main() -> U32:
  Big : U32 = 1
  small : U32 = Big
  # bend-lint: expect-next layout/case@warning -- myY fits neither case
  myY : U32 = small
  myY
