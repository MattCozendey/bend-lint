import Base
import ../../accelerated.bend as A
import ../shared/config.bend as Config
import ./replay.bend as Replay

def run(valid: Bool, +digits: U32) -> IO(Unit):
  match valid:
    case False{}:
      IO.die(Unit, 2, "PI_DIGITS must be a positive integer.")
    case True{}:
      do IO<Unit>:
        start : Nat <- IO.now()
        +places : Nat = U32.to_nat((digits - 1 : U32))
        +total : Nat = A.count!(places)
        replay : Replay.Replay = Replay.make!(places, total)
        motion : Replay.Replay = Replay.motion!((total > 2048n), places, total)
        end : Nat <- IO.now()
        IO.print_err("COMPUTE_MS " ++ Nat.show((end - start)))
        IO.print("CUBES " ++ U32.show(digits) ++ " " ++ Nat.show(total))
        Replay.print(replay)
        IO.print("MOTION")
        Replay.print(motion)

def main() -> IO(Unit):
  do IO<Unit>:
    +digits : U32 <- Config.read("PI_DIGITS", 3)
    run((digits >= 1 : U32), digits)
