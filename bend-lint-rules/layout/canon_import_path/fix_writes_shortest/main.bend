import Base
# bend-lint: expect-next layout/canon_import_path@warning -- x.bend lacks ./
import x.bend as X

def main() -> U32:
  X.one()
