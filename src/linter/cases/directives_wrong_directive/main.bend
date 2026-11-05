import Base
# bend-lint: nonsense
# bend-lint: disable-next tests/written
# bend-lint: disable-next tests/written@warning -- a disable pins nothing not-expected-because: it is not always found
# bend-lint: disable-next tests/written -- a reason, but not why it is no expect
# bend-lint: disable-next tests/written -- a reason -- with dashes not-expected-because:
# bend-lint: expect-next tests/written -- an expect pins one
# bend-lint: disable-line tests/written -- not after code not-expected-because: it is not always found
# bend-lint: disable-next bend-lint/directive -- reserved not-expected-because: it is not always found
# bend-lint: disable-next no-such/rule -- unknown not-expected-because: it is not always found
# bend-lint: expect-next tests/written@fatal -- not a severity
def text() -> String:
  "# bend-lint: disable-file tests/written -- in a string, not a comment"
