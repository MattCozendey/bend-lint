import Base
import ../../../world/world.bend as World
import ../../../native/voxel.bend as Voxel
import ../../../native/face.bend as Face

def fold_hash(+hash: U32, +value: U32) -> U32:
  U32.mul(U32.xor(hash, value), 16777619)

# The timed unit is a whole frame, matching `lab/native/voxel/frame_bench.bend`:
# the bulk `World.chunk` array, the one-pass face extraction, the projection and
# tile bucketing, the 2^depth image, and the fingerprint. Nothing is prebuilt
# between frames, so the measurement is the same work a running client would do.
def frame_many(remaining: Nat, +depth: Nat, +eye: Voxel.Vec, +yaw: F32, +pitch: F32,
  +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      +image_hash = Voxel.fingerprint(
        Face.render_size_at(World.chunk(1337n, 0n, 0n), eye, yaw, pitch, depth))
      frame_many(p, depth, eye, yaw, pitch, fold_hash(hash, image_hash))

# The same frame through the ray renderer, timed in the same harness on the same
# machine, so the two columns of the report are directly comparable rather than
# quoted from another run.
def ray_many(remaining: Nat, +depth: Nat, +eye: Voxel.Vec, +yaw: F32, +pitch: F32,
  +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      +image_hash = Voxel.fingerprint(
        Voxel.render_size_at(World.chunk(1337n, 0n, 0n), eye, yaw, pitch, depth))
      ray_many(p, depth, eye, yaw, pitch, fold_hash(hash, image_hash))

# Face extraction, projection and tile bucketing without the image, so the fixed
# per-frame cost can be separated from the per-pixel cost. The digest folds every
# real candidate record in every bucket; the weighted candidate-count walk is a
# separate measurement rather than part of the prep phase.
def fold_bucket(bucket: List<&2, Face.Screen>, +hash: U32) -> U32:
  match bucket:
    case Nil{}:
      hash
    case +screen <> rest:
      fold_bucket(rest, fold_hash(hash, Face.s_depth_key(screen)))

def fold_row(+row: List<&2, List<&2, Face.Screen>>, +hash: U32) -> U32:
  match row:
    case Nil{}:
      hash
    case +bucket <> rest:
      fold_row(rest, fold_bucket(bucket, hash))

def fold_rows(+rows: List<&2, List<&2, List<&2, Face.Screen>>>, +hash: U32) -> U32:
  match rows:
    case Nil{}:
      hash
    case +row <> rest:
      fold_rows(rest, fold_row(row, hash))

def prep_digest(+tiles: Face.Tiles) -> U32:
  fold_rows(Face.tiles_rows(tiles), 2166136261)

def prep_many(remaining: Nat, +eye: Voxel.Vec, +yaw: F32, +pitch: F32, +depth: Nat,
  +size: U32, +view_half: F32, +focal: F32, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      +camera : Voxel.Camera = Voxel.Camera.look(eye, yaw, pitch)
      +tiles = Face.bucket_faces(Face.faces_from_chunk(World.chunk(1337n, 0n, 0n)),
        Face.cam_eye(camera), Face.cam_right(camera), Face.cam_up(camera),
        Face.cam_forward(camera), view_half, focal, size)
      prep_many(p, eye, yaw, pitch, depth, size, view_half, focal,
        fold_hash(hash, prep_digest(tiles)))

def small_iterations() -> Nat:
  16n

def large_iterations() -> Nat:
  8n

def run_frame(depth: Nat, size: U32, +iterations: Nat) -> IO(Unit):
  do IO<Unit>:
    +eye : Voxel.Vec = Voxel.Vec{8.0, 14.0, 0.5}
    +yaw : F32 = 0.7
    +pitch : F32 = 0.30
    started : Nat <- IO.now()
    +digest : U32 = frame_many(iterations, depth, eye, yaw, pitch, 2166136261)
    consumed : Unit <- IO.print("consume=frame:" ++ U32.show(digest))
    marked : Unit <- IO.pure(Unit, Unit{})
    finished : Nat <- IO.now()
    IO.print("phase=frame size=" ++ U32.show(size) ++ " iterations="
      ++ Nat.show(iterations) ++ " elapsed_ms="
      ++ Nat.show(Nat.sub(finished, started)) ++ " digest=" ++ U32.show(digest))

def run_ray(depth: Nat, size: U32, +iterations: Nat) -> IO(Unit):
  do IO<Unit>:
    +eye : Voxel.Vec = Voxel.Vec{8.0, 14.0, 0.5}
    +yaw : F32 = 0.7
    +pitch : F32 = 0.30
    started : Nat <- IO.now()
    +digest : U32 = ray_many(iterations, depth, eye, yaw, pitch, 2166136261)
    consumed : Unit <- IO.print("consume=ray:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print("phase=ray size=" ++ U32.show(size) ++ " iterations="
      ++ Nat.show(iterations) ++ " elapsed_ms="
      ++ Nat.show(Nat.sub(finished, started)) ++ " digest=" ++ U32.show(digest))

def run_prep(+size: U32, +depth: Nat, +iterations: Nat) -> IO(Unit):
  do IO<Unit>:
    +eye : Voxel.Vec = Voxel.Vec{8.0, 14.0, 0.5}
    +yaw : F32 = 0.7
    +pitch : F32 = 0.30
    +view_half : F32 = Voxel.projection_half(depth)
    +focal : F32 = F32.mul(1.5, view_half)
    started : Nat <- IO.now()
    +digest : U32 = prep_many(iterations, eye, yaw, pitch, depth, size, view_half, focal, 2166136261)
    consumed : Unit <- IO.print("consume=prep:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print("phase=prep size=" ++ U32.show(size) ++ " iterations="
      ++ Nat.show(iterations) ++ " elapsed_ms="
      ++ Nat.show(Nat.sub(finished, started)) ++ " digest=" ++ U32.show(digest))

def main() -> IO(Unit):
  do IO<Unit>:
    frame32 : Unit <- run_frame(5n, 32, small_iterations())
    frame64 : Unit <- run_frame(6n, 64, small_iterations())
    frame128 : Unit <- run_frame(7n, 128, large_iterations())
    frame256 : Unit <- run_frame(8n, 256, 4n)
    ray32 : Unit <- run_ray(5n, 32, small_iterations())
    ray64 : Unit <- run_ray(6n, 64, small_iterations())
    ray128 : Unit <- run_ray(7n, 128, large_iterations())
    prep32 : Unit <- run_prep(32, 5n, small_iterations())
    prep64 : Unit <- run_prep(64, 6n, small_iterations())
    prep128 : Unit <- run_prep(128, 7n, large_iterations())
    IO.print("frame_bench=pass")
