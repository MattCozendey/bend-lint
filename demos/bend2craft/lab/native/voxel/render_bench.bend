import Base
import ../../../world/world.bend as World
import ../../../native/voxel.bend as Voxel

def fold_hash(+hash: U32, +value: U32) -> U32:
  U32.mul(U32.xor(hash, value), 16777619)

def render_many(remaining: Nat, +grid: Voxel.VoxelGrid, +yaw: F32, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      +image_hash = Voxel.fingerprint(Voxel.render_grid(grid, yaw))
      render_many(p, grid, yaw, fold_hash(hash, image_hash))

def iterations() -> Nat:
  16n

def run() -> IO(Unit):
  do IO<Unit>:
    +grid : Voxel.VoxelGrid = Voxel.grid_from_chunk(World.chunk(1337n, 0n, 0n))
    started : Nat <- IO.now()
    +digest : U32 = render_many(iterations(), grid, 0.0, 2166136261)
    consumed : Unit <- IO.print("consume=render:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print("phase=render iterations=" ++ Nat.show(iterations()) ++ " elapsed_ms="
      ++ Nat.show(Nat.sub(finished, started)) ++ " digest=" ++ U32.show(digest))

def main() -> IO(Unit):
  run()
