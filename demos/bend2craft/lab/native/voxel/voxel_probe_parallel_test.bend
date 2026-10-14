import Base
import ../../../world/world.bend as World
import ../../../native/voxel.bend as Voxel
import ./voxel_probe_parallel.bend as Parallel

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, message)

# The parallel frame must be the single-thread frame: same pixels, same
# fingerprint, at every size the quadtree can build. A fork that lost, reordered
# or duplicated a quadrant would show up here as a different digest.
def same_frame_test(+depth: Nat, +size: U32) -> IO(Unit):
  +eye : Voxel.Vec = Voxel.Vec{8.0, 14.0, 0.5}
  +yaw : F32 = 0.0
  +pitch : F32 = 0.30
  +single : U32 = Voxel.fingerprint(
    Voxel.render_size_at(World.chunk(1337n, 0n, 0n), eye, yaw, pitch, depth))
  +parallel : U32 = Voxel.fingerprint(
    Parallel.render_size_at_parallel(World.chunk(1337n, 0n, 0n), eye, yaw, pitch, depth))
  do IO<Unit>:
    Unit <- check(U32.is_eq(single, parallel),
      "parallel render disagreed with the single-thread render at size " ++ U32.show(size))
    check(Bool.and(U32.is_ne(single, 0), U32.is_ne(parallel, 0)),
      "render at size " ++ U32.show(size) ++ " produced the empty fingerprint")

# The parallel path has to stay a camera: a moved eye or a turned yaw must move
# its fingerprint, otherwise the fork tree is ignoring the camera it forked on.
def camera_sensitivity_test(+depth: Nat, +size: U32) -> IO(Unit):
  +eye : Voxel.Vec = Voxel.Vec{8.0, 14.0, 0.5}
  +moved : Voxel.Vec = Voxel.Vec{8.0, 12.0, 0.5}
  +front : U32 = Voxel.fingerprint(
    Parallel.render_size_at_parallel(World.chunk(1337n, 0n, 0n), eye, 0.0, 0.30, depth))
  +eye_moved : U32 = Voxel.fingerprint(
    Parallel.render_size_at_parallel(World.chunk(1337n, 0n, 0n), moved, 0.0, 0.30, depth))
  +yaw_turned : U32 = Voxel.fingerprint(
    Parallel.render_size_at_parallel(World.chunk(1337n, 0n, 0n), eye, 0.7, 0.30, depth))
  do IO<Unit>:
    Unit <- check(U32.is_ne(front, eye_moved),
      "parallel render ignored the eye at size " ++ U32.show(size))
    check(U32.is_ne(front, yaw_turned),
      "parallel render ignored the yaw at size " ++ U32.show(size))

# The pinned 32x32 goldens, reached through the parallel entry point, so the
# fork tree is tied to the same bytes the single-thread test pins.
def golden_test() -> IO(Unit):
  +front : U32 = Voxel.fingerprint(
    Parallel.render_chunk_parallel(World.chunk(1337n, 0n, 0n), 0.0))
  +turned : U32 = Voxel.fingerprint(
    Parallel.render_chunk_parallel(World.chunk(1337n, 0n, 0n), 0.7))
  do IO<Unit>:
    Unit <- check(U32.is_eq(front, 3923257805), "parallel yaw=0 render golden changed")
    check(U32.is_eq(turned, 2153099706), "parallel yaw=0.7 render golden changed")

# The digests the benchmark reports, printed here so a failing run says which
# pixels moved.
def frame_digest(+depth: Nat) -> U32:
  Voxel.fingerprint(Parallel.render_size_at_parallel(World.chunk(1337n, 0n, 0n),
    Voxel.Vec{8.0, 14.0, 0.5}, 0.0, 0.30, depth))

def main() -> IO(Unit):
  do IO<Unit>:
    frame32 : Unit <- same_frame_test(5n, 32)
    frame64 : Unit <- same_frame_test(6n, 64)
    camera32 : Unit <- camera_sensitivity_test(5n, 32)
    camera64 : Unit <- camera_sensitivity_test(6n, 64)
    golden_check : Unit <- golden_test()
    report : Unit <- IO.print("frame_32=" ++ U32.show(frame_digest(5n))
      ++ " frame_64=" ++ U32.show(frame_digest(6n)))
    IO.print("parallel=pass same_32=pass same_64=pass eye=pass yaw=pass golden=pass")
