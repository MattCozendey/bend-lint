import Base
import ./util.bend as U
import ./c.bend as C

def b() -> U32:
  (U.u() + C.c() : U32)
