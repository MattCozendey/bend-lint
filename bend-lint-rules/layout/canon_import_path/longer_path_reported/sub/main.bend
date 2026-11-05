import Base
# bend-lint: expect-next layout/canon_import_path@warning -- ./../x.bend is longer than ../x.bend
import ./../x.bend as X
# bend-lint: expect-next layout/canon_import_path@warning -- ../sub/y.bend is longer than ./y.bend
import ../sub/y.bend as Y

def main() -> U32:
  1
