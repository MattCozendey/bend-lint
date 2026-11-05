import Base

# bend-lint: expect-next layout/case@warning -- fooBar is not snake_case
def add(fooBar: U32, foo_bar: U32) -> U32:
  (fooBar + foo_bar : U32)

def main() -> U32:
  add(1, 2)
