import Base
import ./sparse.bend as Life
import ../shared/grid.bend as G
import ../shared/config.bend as Config

def print_batch(replay: Life.Replay) -> IO(Life.Grid):
  match replay:
    case Life.End{g}:
      IO.pure(Life.Grid, g)
    case Life.Frame{g, next}:
      do IO<Life.Grid>:
        IO.print("S " ++ Life.text(g))
        print_batch(next)

def frames(fuel: Nat, +remaining: Nat, +depth: Nat, +size: U32, g: Life.Grid, elapsed: Nat) -> IO(Unit):
  match fuel:
    case 0n:
      do IO<Unit>:
        IO.print("S " ++ Life.text(g))
        IO.print_err("COMPUTE_MS " ++ Nat.show(elapsed))
    case 1n+p:
      do IO<Unit>:
        +batch : Nat = Nat.min(remaining, 32n)
        start : Nat <- IO.now()
        replay : Life.Replay = Life.record!(batch, depth, size, g)
        end : Nat <- IO.now()
        following : Life.Grid <- print_batch(replay)
        frames(p, (remaining - batch), depth, size, following, (elapsed + end - start))

def mode(show_frames: Bool, +steps: Nat, +depth: Nat, size: U32, g: Life.Grid) -> IO(Unit):
  match show_frames:
    case True{}:
      frames(((steps + 31n) / 32n), steps, depth, size, g, 0n)
    case False{}:
      do IO<Unit>:
        start : Nat <- IO.now()
        final : Life.Grid = Life.run!(steps, depth, size, g)
        end : Nat <- IO.now()
        IO.print_err("COMPUTE_MS " ++ Nat.show((end - start)))
        IO.print(G.text(Life.expand(depth, final)))

def main() -> IO(Unit):
  do IO<Unit>:
    +size : U32 <- Config.read("LIFE_SIZE", 128)
    +steps : U32 <- Config.read("LIFE_STEPS", 120)
    +depth : U32 <- Config.read("TREE_DEPTH", 9)
    kind : U32 <- Config.read("LIFE_PATTERN", 0)
    seed : U32 <- Config.read("LIFE_SEED", 42)
    dump : U32 <- Config.read("DUMP", 1)
    g : Life.Grid = Life.initial(U32.to_nat(depth), kind, size, seed, 0)
    IO.print("LIFE_SPARSE " ++ U32.show(size) ++ " " ++ U32.show(steps))
    mode(U32.is_eq(dump, 1), U32.to_nat(steps), U32.to_nat(depth), size, g)
