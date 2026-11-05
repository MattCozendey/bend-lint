# bend-lint: expect-begin layout/directive_order@warning -- the first stack is out of order
import Base
# bend-lint: disable-next layout/case -- a reason not-expected-because: it varies
# bend-lint: disable-next language/decreasing_call -- a reason not-expected-because: it varies

# bend-lint: expect-end layout/directive_order@warning

# bend-lint: disable-next language/decreasing_call -- a reason not-expected-because: it varies
# bend-lint: disable-next layout/case -- a reason not-expected-because: it varies

# bend-lint: disable-next layout/case -- a reason not-expected-because: it varies

# bend-lint: disable-next language/decreasing_call -- a reason not-expected-because: it varies
def one() -> U32:
  1 # bend-lint: disable-line language/decreasing_call -- a reason not-expected-because: it varies
