import Base
import ../../../world/world.bend as World
import ../../../native/voxel.bend as Voxel

type RayStats is Data:
  RayStats{digest: U32, probes: U32}

type BenchData is Data:
  BenchData{blocks: List<&2, U32>, grid: Voxel.VoxelGrid}

def total_probes(+stats: RayStats) -> U32:
  RayStats{_, probes} = stats
  probes

def ray_digest(+stats: RayStats) -> U32:
  RayStats{digest, _} = stats
  digest

def fold_hash(+hash: U32, +value: U32) -> U32:
  U32.mul(U32.xor(hash, value), 16777619)

def list_lookup_many(remaining: Nat, +iteration: U32, +base_y: U32,
  +blocks: List<&2, U32>, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      +slot = U32.mod(iteration, 256)
      +x = U32.mod(slot, 16)
      +z = U32.div(slot, 16)
      +block = Voxel.list_block_at(blocks, x, base_y, z)
      list_lookup_many(p, (iteration + 1 : U32), base_y, blocks, fold_hash(hash, block))

def grid_lookup_many(remaining: Nat, +iteration: U32, +base_y: U32,
  +grid: Voxel.VoxelGrid, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      +slot = U32.mod(iteration, 256)
      +x = U32.mod(slot, 16)
      +z = U32.div(slot, 16)
      +block = Voxel.grid_at(grid, x, base_y, z)
      grid_lookup_many(p, (iteration + 1 : U32), base_y, grid, fold_hash(hash, block))

def ray_many(remaining: Nat, +iteration: U32, +grid: Voxel.VoxelGrid,
  +camera: Voxel.Camera, +hash: U32, +probes: U32) -> RayStats:
  match remaining:
    case 0n:
      RayStats{hash, probes}
    case 1n+p:
      +x = U32.mod(iteration, 32)
      +y = U32.div(iteration, 32)
      +trace : Voxel.Trace = Voxel.trace_inside(grid, Voxel.Camera.eye(camera),
        Voxel.Camera.ray(camera, x, y))
      +block = Voxel.hit_block(trace)
      ray_many(p, (iteration + 1 : U32), grid, camera, fold_hash(hash, block),
        (probes + Voxel.trace_probes(trace) : U32))

def fingerprints(remaining: Nat, +image: Image, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      +image_hash = Voxel.fingerprint(image)
      fingerprints(p, image, fold_hash(hash, image_hash))

def lookup_count() -> Nat:
  1024n

def ray_count() -> Nat:
  1024n

def fingerprint_count() -> Nat:
  128n

def make_bench_data(chunk: Array<U32>) -> BenchData:
  +blocks : List<&2, U32> = Voxel.shared_blocks(chunk)
  BenchData{blocks, Voxel.grid_from_blocks(blocks)}

def run_list_lookup(+blocks: List<&2, U32>, +y: U32, +count: Nat) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 = list_lookup_many(count, 0, y, blocks, 2166136261)
    consumed : Unit <- IO.print("consume=list_lookup:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print("phase=list_lookup y=" ++ U32.show(y) ++ " reads=" ++ Nat.show(count)
      ++ " elapsed_ms=" ++ Nat.show(Nat.sub(finished, started)) ++ " digest="
      ++ U32.show(digest))

def run_grid_lookup(+grid: Voxel.VoxelGrid, +y: U32, +count: Nat) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 = grid_lookup_many(count, 0, y, grid, 2166136261)
    consumed : Unit <- IO.print("consume=grid_lookup:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print("phase=grid_lookup y=" ++ U32.show(y) ++ " reads=" ++ Nat.show(count)
      ++ " elapsed_ms=" ++ Nat.show(Nat.sub(finished, started)) ++ " digest="
      ++ U32.show(digest))

def run_rays(+grid: Voxel.VoxelGrid, +camera: Voxel.Camera) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +stats : RayStats = ray_many(ray_count(), 0, grid, camera, 2166136261, 0)
    +digest : U32 = ray_digest(stats)
    +probes : U32 = total_probes(stats)
    consumed : Unit <- IO.print("consume=rays:" ++ U32.show(digest)
      ++ ":probes=" ++ U32.show(probes))
    finished : Nat <- IO.now()
    IO.print("phase=dda_rays pixels=" ++ Nat.show(ray_count()) ++ " elapsed_ms="
      ++ Nat.show(Nat.sub(finished, started)) ++ " probes=" ++ U32.show(probes)
      ++ " digest=" ++ U32.show(digest))

def run_fingerprints(+image: Image) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 = fingerprints(fingerprint_count(), image, 2166136261)
    consumed : Unit <- IO.print("consume=fingerprint:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print("phase=fingerprint_only renders=" ++ Nat.show(fingerprint_count())
      ++ " elapsed_ms=" ++ Nat.show(Nat.sub(finished, started)) ++ " digest="
      ++ U32.show(digest))

def run_bench(data: BenchData) -> IO(Unit):
  BenchData{+blocks, +grid} = data
  do IO<Unit>:
    +camera : Voxel.Camera = Voxel.Camera.at(0.0)
    +image : Image = Voxel.render_grid(grid, 0.0)
    +probes : U32 = total_probes(ray_many(ray_count(), 0, grid, camera, 2166136261, 0))
    run_list_lookup(blocks, 0, lookup_count())
    run_list_lookup(blocks, 10, lookup_count())
    run_list_lookup(blocks, 14, lookup_count())
    run_grid_lookup(grid, 0, lookup_count())
    run_grid_lookup(grid, 10, lookup_count())
    run_grid_lookup(grid, 14, lookup_count())
    run_rays(grid, camera)
    run_list_lookup(blocks, 10, U32.to_nat(probes))
    run_list_lookup(blocks, 14, U32.to_nat(probes))
    run_grid_lookup(grid, 10, U32.to_nat(probes))
    run_grid_lookup(grid, 14, U32.to_nat(probes))
    run_fingerprints(image)

def main() -> IO(Unit):
  run_bench(make_bench_data(World.chunk(1337n, 0n, 0n)))
