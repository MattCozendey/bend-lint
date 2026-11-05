import Base

type Box is Data:
  Box{}

# bend-lint: expect-next layout/case@warning -- fromU32 is not snake_case
def Box.fromU32(n: U32) -> Box:
  Box{}

def main() -> Box:
  Box.fromU32(1)
