import Base
import ../../../world/world.bend as World
import ../../../native/voxel.bend as Voxel

def fold_hash(+hash: U32, +value: U32) -> U32:
  U32.mul(U32.xor(hash, value), 16777619)

# The timed unit is a whole frame: the bulk World.chunk array, the nested y/z/x
# grid built from it, the 2^depth image at an arbitrary eye, and the fingerprint.
def frame_many(remaining: Nat, +depth: Nat, +eye: Voxel.Vec, +yaw: F32, +pitch: F32,
  +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      +image_hash = Voxel.fingerprint(
        Voxel.render_size_at(World.chunk(1337n, 0n, 0n), eye, yaw, pitch, depth))
      frame_many(p, depth, eye, yaw, pitch, fold_hash(hash, image_hash))

# The prebuilt-grid path the earlier render_bench harness measured, kept as the
# control for "the camera change did not move the 32x32 render cost".
def render_only_many(remaining: Nat, +grid: Voxel.VoxelGrid, +camera: Voxel.Camera,
  +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      render_only_many(p, grid, camera,
        fold_hash(hash, Voxel.fingerprint(Voxel.render_view(grid, camera))))

# The fixed cost the image phase does not pay: one bulk chunk plus the nested
# grid. grid_at consumes the grid, so neither step can be dropped as dead.
def bootstrap_many(remaining: Nat, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      +grid : Voxel.VoxelGrid = Voxel.grid_from_chunk(World.chunk(1337n, 0n, 0n))
      bootstrap_many(p, fold_hash(hash, Voxel.grid_at(grid, 8, 8, 8)))

def bootstrap_iterations() -> Nat:
  16n

def render_only_iterations() -> Nat:
  16n

def small_iterations() -> Nat:
  16n

def large_iterations() -> Nat:
  8n

def run_bootstrap() -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 = bootstrap_many(bootstrap_iterations(), 2166136261)
    consumed : Unit <- IO.print("consume=bootstrap:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print("phase=bootstrap iterations=" ++ Nat.show(bootstrap_iterations())
      ++ " elapsed_ms=" ++ Nat.show(Nat.sub(finished, started))
      ++ " digest=" ++ U32.show(digest))

def run_render_only(+grid: Voxel.VoxelGrid) -> IO(Unit):
  do IO<Unit>:
    +camera : Voxel.Camera = Voxel.Camera.at(0.0)
    started : Nat <- IO.now()
    +digest : U32 = render_only_many(render_only_iterations(), grid, camera, 2166136261)
    consumed : Unit <- IO.print("consume=render:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print("phase=render_only size=32 iterations="
      ++ Nat.show(render_only_iterations()) ++ " elapsed_ms="
      ++ Nat.show(Nat.sub(finished, started)) ++ " digest=" ++ U32.show(digest))

def run_frame(depth: Nat, size: U32, +iterations: Nat) -> IO(Unit):
  do IO<Unit>:
    +eye : Voxel.Vec = Voxel.Vec{8.0, 14.0, 0.5}
    +yaw : F32 = 0.0
    +pitch : F32 = 0.30
    started : Nat <- IO.now()
    +digest : U32 = frame_many(iterations, depth, eye, yaw, pitch, 2166136261)
    consumed : Unit <- IO.print("consume=frame:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print("phase=frame size=" ++ U32.show(size) ++ " iterations="
      ++ Nat.show(iterations) ++ " elapsed_ms=" ++ Nat.show(Nat.sub(finished, started))
      ++ " digest=" ++ U32.show(digest))

def main() -> IO(Unit):
  do IO<Unit>:
    +grid : Voxel.VoxelGrid = Voxel.grid_from_chunk(World.chunk(1337n, 0n, 0n))
    bootstrap : Unit <- run_bootstrap()
    render_only : Unit <- run_render_only(grid)
    frame32 : Unit <- run_frame(5n, 32, small_iterations())
    frame64 : Unit <- run_frame(6n, 64, small_iterations())
    frame128 : Unit <- run_frame(7n, 128, large_iterations())
    IO.print("frame_bench=pass")
