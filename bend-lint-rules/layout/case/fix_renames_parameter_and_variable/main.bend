import Base

# bend-lint: expect-next layout/case@warning -- my_box is a type
type my_box is Data:
  MyBox{}

# bend-lint: expect-next layout/case@warning -- inputVal is not snake_case
def twice(+inputVal: U32) -> U32:
  # bend-lint: expect-next layout/case@warning -- outVal is not snake_case
  outVal : U32 = (inputVal + inputVal : U32)
  outVal

def main() -> U32:
  twice(1)
