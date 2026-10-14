import Base
import ../../../world/world.bend as World
import ./render_probe.bend as Probe

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, message)

def verify(+base: U32, +neighbor: U32, +edited: U32) -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(base, 903042448), "base render fingerprint changed")
    Unit <- check(U32.is_ne(base, neighbor), "neighbor chunk rendered identically")
    Unit <- check(U32.is_ne(base, edited), "edited surface block did not change the image")
    IO.print("size=16x16 base=" ++ U32.show(base) ++ " neighbor="
      ++ U32.show(neighbor) ++ " edited=" ++ U32.show(edited))

def main() -> IO(Unit):
  verify(
    Probe.fingerprint(Probe.overhead(World.chunk(1337n, 0n, 0n))),
    Probe.fingerprint(Probe.overhead(World.chunk(1337n, 1n, 0n))),
    Probe.fingerprint(Probe.overhead(Array.set(U32, World.chunk(1337n, 0n, 0n),
      Probe.chunk_index(0, 0, U32.from_nat(Nat.sub(World.max_y(), 1n))), 10)))
  )

#|size=16x16 base=903042448 neighbor=3474066668 edited=2978264110
