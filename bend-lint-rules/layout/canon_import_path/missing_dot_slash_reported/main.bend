import Base
# bend-lint: expect-next layout/canon_import_path@warning -- x.bend lacks ./
import x.bend as X
# bend-lint: expect-next layout/canon_import_path@warning -- sub/y.bend lacks ./
import sub/y.bend as Y

def main() -> U32:
  1
