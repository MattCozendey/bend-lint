# A deliberately false law: the checker must refuse it.
#
# Shape.frame.at(3n) is an 8x8 frame, i.e. one tile of 64 pixels, but the law
# claims 16.  This is the negative test for the proof gate; docs/laws.md shows
# the exact error.
import Base
import ../../src/shape.bend as Shape

law frame8:
  {Shape.pixels(Shape.frame.at(3n)) == 16n : Nat}

def frame8():
  {==}
