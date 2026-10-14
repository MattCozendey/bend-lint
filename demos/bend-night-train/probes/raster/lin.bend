# Linearity probes for the rasteriser's inner loop.
#
# Three questions the fragment fold depends on:
#   1. is a variable consumed in one match branch still usable in another?
#   2. can a parameter be marked `+` and passed on after being read once?
#   3. does a destructuring let need every field named?
import Base

type F is Data:
  F{a: F32, b: F32}

type G is Data:
  G{p: F, q: F32}


def F.iw(f: F) -> F32:
  F{+a, b} = f
  a


# 1: `used` is consumed in the True branch, returned in the False branch.
def P1(flag: Bool, used: F) -> F32:
  match flag:
    case True{}:
      F.iw(used)
    case False{}:
      F.iw(used)


def P1.free(flag: Bool, used: F) -> F:
  match flag:
    case True{}:
      F{F.iw(used), 0.0}
    case False{}:
      used


# 3: only two of the fields are named.
def P3(g: G) -> F32:
  G{p, +q} = g
  q


def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(Nat.show(1n) ++ "\n")
