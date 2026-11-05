# bend-lint: expect-next no_unused/imports@warning -- no name uses Base
import Base
import ./util.bend as U

def U.two_is_two():
  {==}
