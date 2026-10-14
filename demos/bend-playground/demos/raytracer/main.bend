import Base
import ./ray.bend as Ray
import ./grid-path.bend as Path
import ../shared/grid.bend as G
import ../shared/config.bend as Config

def render(scene: U32, depth: Nat, width: U32, height: U32, bounces: Nat, samples: U32, +seed: U32) -> G.Grid:
  match scene:
    case 0:
      Ray.render(depth, 0, width, height, bounces)
    case 1:
      Path.render(depth, 0, width, height, bounces, False{}, seed, samples, seed)
    case _:
      Path.render(depth, 0, width, height, bounces, True{}, seed, samples, seed)

def main() -> IO(Unit):
  do IO<Unit>:
    +width : U32 <- Config.read("RAY_WIDTH", 512)
    +height : U32 <- Config.read("RAY_HEIGHT", 320)
    depth : U32 <- Config.read("TREE_DEPTH", 18)
    bounces : U32 <- Config.read("RAY_BOUNCES", 3)
    scene : U32 <- Config.read("RAY_SCENE", 0)
    samples : U32 <- Config.read("RAY_SAMPLES", 16)
    seed : U32 <- Config.read("RAY_SEED", 42)
    +dump : U32 <- Config.read("DUMP", 1)
    start : Nat <- IO.now()
    +pixels : G.Grid = render!(scene, U32.to_nat(depth), width, height, U32.to_nat(bounces), samples, seed)
    end : Nat <- IO.now()
    IO.print_err("COMPUTE_MS " ++ Nat.show((end - start)))
    IO.print("RAY " ++ U32.show(width) ++ " " ++ U32.show(height) ++ " " ++ U32.show(G.checksum(pixels)))
    IO.print(Bool.pick(String, U32.is_eq(dump, 1), G.text(pixels), ""))
