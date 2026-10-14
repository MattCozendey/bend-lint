import Base
import ../../../world/world.bend as World
import ../../../native/voxel.bend as Voxel
import ./voxel_probe_parallel.bend as Parallel

def fold_hash(+hash: U32, +value: U32) -> U32:
  U32.mul(U32.xor(hash, value), 16777619)

# `frame` is the pinned single-thread path: the bulk World.chunk array, the
# nested y/z/x grid, the 2^depth image and the fingerprint. `frame_par` is the
# same frame through the banged entry point, so the two differ only in the fork.
def frame_many(remaining: Nat, +depth: Nat, +eye: Voxel.Vec, +yaw: F32, +pitch: F32,
  +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      +image_hash = Voxel.fingerprint(
        Voxel.render_size_at(World.chunk(1337n, 0n, 0n), eye, yaw, pitch, depth))
      frame_many(p, depth, eye, yaw, pitch, fold_hash(hash, image_hash))

def frame_par_many(remaining: Nat, +depth: Nat, +eye: Voxel.Vec, +yaw: F32, +pitch: F32,
  +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      +image_hash = Voxel.fingerprint(
        Parallel.render_size_at_parallel(World.chunk(1337n, 0n, 0n), eye, yaw, pitch, depth))
      frame_par_many(p, depth, eye, yaw, pitch, fold_hash(hash, image_hash))

# The control for the shared reads: the same quadtree, the same per-pixel rays
# and the same fingerprint fold, with the DDA left out. The ray is folded into
# the color so it cannot be dropped as dead code, so what this control omits is
# exactly the trace and the reusable reads of the shared grid.
def ray_abs_x(+ray: Voxel.Vec) -> F32:
  Voxel.Vec{x, _, _} = ray
  F32.abs(x)

def sky_pixel(+camera: Voxel.Camera, +x: U32, +y: U32, +half: F32, +focal: F32) -> U32:
  +ray = Voxel.Camera.ray_for(camera, x, y, half, focal)
  Voxel.sky_color(U32.add(y, F32.to_u32(ray_abs_x(ray))))

def sky_image(+depth: Nat, +camera: Voxel.Camera, +half: F32, +focal: F32,
  +x: U32, +y: U32) -> Image:
  match depth:
    case 0n:
      Pix{sky_pixel(camera, x, y, half, focal)}
    case 1n+p:
      +step = U32.shln(1, p)
      tl tr bl br = sky_image(p, camera, half, focal, x, y)
        sky_image(p, camera, half, focal, (x + step : U32), y)
        sky_image(p, camera, half, focal, x, (y + step : U32))
        sky_image(p, camera, half, focal, (x + step : U32), (y + step : U32))
      Qua{tl, tr, bl, br}

def sky_root(+depth: Nat, +camera: Voxel.Camera, +half: F32, +focal: F32,
  +x: U32, +y: U32) -> Image:
  sky_image(depth, camera, half, focal, x, y)

def sky_frame(+depth: Nat, +camera: Voxel.Camera) -> U32:
  +half = Voxel.projection_half(depth)
  +image : Image = sky_root!(depth, camera, half, F32.mul(1.5, half), 0, 0)
  Voxel.fingerprint(image)

def sky_many(remaining: Nat, +depth: Nat, +camera: Voxel.Camera, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      sky_many(p, depth, camera, fold_hash(hash, sky_frame(depth, camera)))

def small_iterations() -> Nat:
  16n

def large_iterations() -> Nat:
  8n

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
      ++ Nat.show(iterations) ++ " elapsed_ms="
      ++ Nat.show(Nat.sub(finished, started)) ++ " digest=" ++ U32.show(digest))

def run_frame_par(depth: Nat, size: U32, +iterations: Nat) -> IO(Unit):
  do IO<Unit>:
    +eye : Voxel.Vec = Voxel.Vec{8.0, 14.0, 0.5}
    +yaw : F32 = 0.0
    +pitch : F32 = 0.30
    started : Nat <- IO.now()
    +digest : U32 = frame_par_many(iterations, depth, eye, yaw, pitch, 2166136261)
    consumed : Unit <- IO.print("consume=frame_par:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print("phase=frame_par size=" ++ U32.show(size) ++ " iterations="
      ++ Nat.show(iterations) ++ " elapsed_ms="
      ++ Nat.show(Nat.sub(finished, started)) ++ " digest=" ++ U32.show(digest))

def run_sky(depth: Nat, size: U32, +iterations: Nat) -> IO(Unit):
  do IO<Unit>:
    +camera : Voxel.Camera = Voxel.Camera.look(Voxel.Vec{8.0, 14.0, 0.5}, 0.0, 0.30)
    started : Nat <- IO.now()
    +digest : U32 = sky_many(iterations, depth, camera, 2166136261)
    consumed : Unit <- IO.print("consume=sky:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print("phase=sky size=" ++ U32.show(size) ++ " iterations="
      ++ Nat.show(iterations) ++ " elapsed_ms="
      ++ Nat.show(Nat.sub(finished, started)) ++ " digest=" ++ U32.show(digest))

def main() -> IO(Unit):
  do IO<Unit>:
    single32 : Unit <- run_frame(5n, 32, small_iterations())
    par32 : Unit <- run_frame_par(5n, 32, small_iterations())
    sky32 : Unit <- run_sky(5n, 32, small_iterations())
    single64 : Unit <- run_frame(6n, 64, small_iterations())
    par64 : Unit <- run_frame_par(6n, 64, small_iterations())
    sky64 : Unit <- run_sky(6n, 64, small_iterations())
    single128 : Unit <- run_frame(7n, 128, large_iterations())
    par128 : Unit <- run_frame_par(7n, 128, large_iterations())
    sky128 : Unit <- run_sky(7n, 128, large_iterations())
    IO.print("parallel_frame_bench=pass")
