# A law about F32 that cannot be proven, or even stated.
#
# Every F32 operation is a `law` with no body in Base, so the checker has no
# equation to rewrite with.  docs/laws.md quotes the error this produces.
import Base

law f32_add_zero:
  for x: F32
  {F32.add(x, 0.0) == x : F32}

def f32_add_zero(x):
  {==}
