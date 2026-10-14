import Base
import ../../../native/voxel.bend as Voxel

# The parallel render entry point. `Voxel.image` already forks its four
# quadrants with a parallel let, so the fork tree is the same one in both paths;
# the bang on the root call is what marks that call for parallel execution, which
# on the native CPU lane is the pool `--threads N` sizes. No pixel, ray, grid read
# or fingerprint step changes, so the parallel frame is the single-thread frame.
def image_root(+depth: Nat, +grid: Voxel.VoxelGrid, +camera: Voxel.Camera,
  +half: F32, +focal: F32, +x: U32, +y: U32) -> Image:
  Voxel.image(depth, grid, camera, half, focal, x, y)

def render_size_parallel(+grid: Voxel.VoxelGrid, +camera: Voxel.Camera, +depth: Nat) -> Image:
  +half = Voxel.projection_half(depth)
  image_root!(depth, grid, camera, half, F32.mul(1.5, half), 0, 0)

def render_view_parallel(+grid: Voxel.VoxelGrid, +camera: Voxel.Camera) -> Image:
  render_size_parallel(grid, camera, 5n)

def render_grid_parallel(+grid: Voxel.VoxelGrid, +yaw: F32) -> Image:
  render_view_parallel(grid, Voxel.Camera.at(yaw))

def render_chunk_parallel(chunk: Array<U32>, +yaw: F32) -> Image:
  render_grid_parallel(Voxel.grid_from_chunk(chunk), yaw)

# A full frame from a bulk chunk at any eye, yaw, pitch and 2^depth size, with
# the image forked. This is `Voxel.render_size_at` with the bang on the image.
def render_size_at_parallel(chunk: Array<U32>, +eye: Voxel.Vec, +yaw: F32, +pitch: F32,
  +depth: Nat) -> Image:
  render_size_parallel(Voxel.grid_from_chunk(chunk), Voxel.Camera.look(eye, yaw, pitch), depth)

def render_at_parallel(chunk: Array<U32>, +eye: Voxel.Vec, +yaw: F32, +pitch: F32) -> Image:
  render_size_at_parallel(chunk, eye, yaw, pitch, 5n)
