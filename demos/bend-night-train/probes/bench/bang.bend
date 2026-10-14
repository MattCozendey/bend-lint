# Does `!` reach the device on this host?  A uniform F32 tree, nothing
# list-shaped: 4^NT_DEPTH leaves, each spinning NT_SPIN times on one float.
#
#   ./tools/bend probes/bench/bang.bend -o probes/bench/bang
#   NT_DEPTH=8 NT_BANG=0 /usr/bin/time -f "%e wall %U cpu" ./probes/bench/bang \
#     --threads 32
#   NT_DEPTH=8 NT_BANG=1 /usr/bin/time -f "%e wall %U cpu" ./probes/bench/bang \
#     --threads 32
#
# On this host (RTX 4090 Laptop, driver 580.178.04) the two are not the same
# shape of run.  `NT_BANG=1` reports about 0.01 s of host CPU at every thread
# count -- the device holds the recursion, so the host has nothing to do --
# while `NT_BANG=0` reports 0.20 s of CPU and scales with `--threads`.  Same
# value printed either way.  That is the device-lane signature, and it is what
# makes the rasteriser's own `NT_BANG=1` (where the two are indistinguishable)
# a negative result rather than a claim that the lane is broken.  The
# rasteriser's leaf is divergent; this one is uniform.  See docs/benchmarks.md.
import Base


def Main.env.u32.maybe(m: Maybe<&2, U32>, +dflt: U32) -> IO(U32):
  match m:
    case None{}:
      IO.pure(U32, dflt)
    case Some{v}:
      IO.pure(U32, v)


def Main.env.u32.pick(r: Result<&1, &1, U32 & String, String>, +dflt: U32)
  -> IO(U32):
  match r:
    case Fail{e}:
      IO.pure(U32, dflt)
    case Done{value}:
      Main.env.u32.maybe(U32.read(value), dflt)


def Main.env.u32(name: String, +dflt: U32) -> IO(U32):
  do IO<U32>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    Main.env.u32.pick(r, dflt)


# The shrinking argument leads: a self-call may only be accepted if every
# argument before the one that shrinks is passed on unchanged, and a computed
# float is not "unchanged".
def Main.spin(+n: Nat, +x: F32) -> F32:
  match n:
    case 0n:
      x
    case 1n+k:
      Main.spin(k, (x * 1.000001 + 0.000001 : F32))


def Main.tree(+depth: Nat, +x: F32, +n: Nat) -> F32:
  match depth:
    case 0n:
      Main.spin(n, x)
    case 1n+k:
      a b c d =
        Main.tree(k, x, n)
        Main.tree(k, x, n)
        Main.tree(k, x, n)
        Main.tree(k, x, n)
      ((((a + b) + c) + d : F32))


def Main.tree.bang(+depth: Nat, +x: F32, +n: Nat) -> F32:
  Main.tree!(depth, x, n)


def Main.pick(bang: Bool, +depth: Nat, +x: F32, +n: Nat) -> F32:
  match bang:
    case True{}:
      Main.tree.bang(depth, x, n)
    case False{}:
      Main.tree(depth, x, n)


def Main.run() -> IO(Unit):
  do IO<Unit>:
    depth : U32 <- Main.env.u32("NT_DEPTH", 8)
    spin : U32 <- Main.env.u32("NT_SPIN", 2000)
    bang : U32 <- Main.env.u32("NT_BANG", 0)
    IO.print(F32.show(Main.pick(U32.is_eq(bang, 1), U32.to_nat(depth), 1.0,
      U32.to_nat(spin))) ++ "\n")


def main() -> IO(Unit):
  Main.run()
