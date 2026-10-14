# These are structural guarantees. F32 conservation is checked numerically
# in tests, not claimed as a formal real-number proof.
import Base
import ./physics.bend as Physics

law initially_zero:
  for mass: F32
  {Physics.collisions(Physics.initial(mass)) == 0 : U32}

law stopped_is_unchanged:
  for +s: Physics.State
  {Physics.next_active(True{}, s) == s : Physics.State}

law impact_counts_once:
  for at_wall: Bool
  for +s: Physics.State
  for dt: F32
  {Physics.collisions(Physics.impact(at_wall, s, dt)) == (Physics.collisions(s) + 1 : U32) : U32}

