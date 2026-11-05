# bend-lint: expect-file layout/directive_order@warning -- the stack is out of order
import Base
# bend-lint: disable-next layout/case -- a reason not-expected-because: it varies
# bend-lint: disable-next language/decreasing_call -- a reason not-expected-because: it varies
def one() -> U32:
  1
