import Base
import ../../../world/world.bend as World
import ../../../native/voxel.bend as Voxel
import ../../../native/face.bend as Face

# Split frame preparation into cached extraction and camera-dependent projection.
# Every project digest folds every Screen record in every bucket so neither a
# lazy/unbuilt bucket grid nor an omitted candidate can appear cheaper.
def fold_hash(+hash: U32, +value: U32) -> U32:
  U32.mul(U32.xor(hash, value), 16777619)

def fold_faces(+faces: List<&2, Face.Face>, +hash: U32) -> U32:
  match faces:
    case Nil{}:
      hash
    case +face <> rest:
      Face.Face{x, y, z, dir, block} = face
      fold_faces(rest, fold_hash(hash,
        U32.add(U32.add(x, y), U32.add(U32.add(z, U32.from_nat(dir)), block))))

def extract_many(remaining: Nat, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      +digest : U32 = fold_faces(Face.faces_from_chunk(World.chunk(1337n, 0n, 0n)), hash)
      extract_many(p, digest)

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

def project_current_many(remaining: Nat, +faces: List<&2, Face.Face>, +eye: Voxel.Vec,
  +yaw: F32, +pitch: F32, +size: U32, +view_half: F32, +focal: F32, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      +camera : Voxel.Camera = Voxel.Camera.look(eye, yaw, pitch)
      +tiles = Face.bucket_faces(faces, Face.cam_eye(camera), Face.cam_right(camera),
        Face.cam_up(camera), Face.cam_forward(camera), view_half, focal, size)
      project_current_many(p, faces, eye, yaw, pitch, size, view_half, focal,
        fold_hash(hash, prep_digest(tiles)))

def project_scatter_many(remaining: Nat, +faces: List<&2, Face.Face>, +eye: Voxel.Vec,
  +yaw: F32, +pitch: F32, +size: U32, +edge: U32, +view_half: F32, +focal: F32,
  +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      +camera : Voxel.Camera = Voxel.Camera.look(eye, yaw, pitch)
      +tiles = Face.bucket_faces_with_tile_size(faces, Face.cam_eye(camera),
        Face.cam_right(camera), Face.cam_up(camera), Face.cam_forward(camera),
        view_half, focal, size, edge)
      project_scatter_many(p, faces, eye, yaw, pitch, size, edge, view_half, focal,
        fold_hash(hash, prep_digest(tiles)))

def project_row_major_many(remaining: Nat, +faces: List<&2, Face.Face>, +eye: Voxel.Vec,
  +yaw: F32, +pitch: F32, +size: U32, +edge: U32, +view_half: F32, +focal: F32,
  +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      +camera : Voxel.Camera = Voxel.Camera.look(eye, yaw, pitch)
      +tiles = Face.bucket_faces_row_major_with_tile_size(faces, Face.cam_eye(camera),
        Face.cam_right(camera), Face.cam_up(camera), Face.cam_forward(camera),
        view_half, focal, size, edge)
      project_row_major_many(p, faces, eye, yaw, pitch, size, edge, view_half, focal,
        fold_hash(hash, prep_digest(tiles)))

def full_scatter_many(remaining: Nat, +size: U32, +depth: Nat, +eye: Voxel.Vec,
  +yaw: F32, +pitch: F32, +edge: U32, +view_half: F32, +focal: F32, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      +camera : Voxel.Camera = Voxel.Camera.look(eye, yaw, pitch)
      +tiles = Face.bucket_faces_with_tile_size(
        Face.faces_from_chunk(World.chunk(1337n, 0n, 0n)), Face.cam_eye(camera),
        Face.cam_right(camera), Face.cam_up(camera), Face.cam_forward(camera),
        view_half, focal, size, edge)
      +image = Face.render_size_tiles(tiles, depth)
      +digest = Voxel.fingerprint(image)
      full_scatter_many(p, size, depth, eye, yaw, pitch, edge, view_half, focal,
        fold_hash(hash, digest))

def full_row_major_many(remaining: Nat, +size: U32, +depth: Nat, +eye: Voxel.Vec,
  +yaw: F32, +pitch: F32, +edge: U32, +view_half: F32, +focal: F32, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      +camera : Voxel.Camera = Voxel.Camera.look(eye, yaw, pitch)
      +tiles = Face.bucket_faces_row_major_with_tile_size(
        Face.faces_from_chunk(World.chunk(1337n, 0n, 0n)), Face.cam_eye(camera),
        Face.cam_right(camera), Face.cam_up(camera), Face.cam_forward(camera),
        view_half, focal, size, edge)
      +image = Face.render_size_tiles(tiles, depth)
      +digest = Voxel.fingerprint(image)
      full_row_major_many(p, size, depth, eye, yaw, pitch, edge, view_half, focal,
        fold_hash(hash, digest))

def split_iterations() -> Nat:
  64n

def if_nat(small: Bool, medium: Bool, small_n: Nat, medium_n: Nat, large_n: Nat) -> Nat:
  match small:
    case True{}:
      small_n
    case False{}:
      match medium:
        case True{}:
          medium_n
        case False{}:
          large_n

def run_extract(+size: U32, +iterations: Nat) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 = extract_many(iterations, 2166136261)
    consumed : Unit <- IO.print("consume=extract:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print("phase=extract size=" ++ U32.show(size) ++ " iterations="
      ++ Nat.show(iterations) ++ " elapsed_ms=" ++ Nat.show(Nat.sub(finished, started))
      ++ " digest=" ++ U32.show(digest))

def run_project_current(+size: U32, +depth: Nat, +iterations: Nat) -> IO(Unit):
  +eye : Voxel.Vec = Voxel.Vec{8.0, 14.0, 0.5}
  +yaw : F32 = 0.7
  +pitch : F32 = 0.30
  +view_half : F32 = Voxel.projection_half(depth)
  +focal : F32 = F32.mul(1.5, view_half)
  +faces = Face.faces_from_chunk(World.chunk(1337n, 0n, 0n))
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 = project_current_many(iterations, faces, eye, yaw, pitch, size,
      view_half, focal, 2166136261)
    consumed : Unit <- IO.print("consume=project:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print("phase=project size=" ++ U32.show(size) ++ " edge="
      ++ U32.show(Face.tile_size()) ++ " iterations=" ++ Nat.show(iterations)
      ++ " elapsed_ms=" ++ Nat.show(Nat.sub(finished, started))
      ++ " digest=" ++ U32.show(digest))

def run_scatter(+size: U32, +edge: U32, +iterations: Nat) -> IO(Unit):
  +eye : Voxel.Vec = Voxel.Vec{8.0, 14.0, 0.5}
  +yaw : F32 = 0.7
  +pitch : F32 = 0.30
  +depth = if_nat(U32.is_lt(size, 40), U32.is_lt(size, 100), 5n, 6n, 7n)
  +view_half : F32 = Voxel.projection_half(depth)
  +focal : F32 = F32.mul(1.5, view_half)
  +faces = Face.faces_from_chunk(World.chunk(1337n, 0n, 0n))
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 = project_scatter_many(iterations, faces, eye, yaw, pitch, size,
      edge, view_half, focal, 2166136261)
    consumed : Unit <- IO.print("consume=scatter:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print("phase=scatter size=" ++ U32.show(size) ++ " edge=" ++ U32.show(edge)
      ++ " iterations=" ++ Nat.show(iterations) ++ " elapsed_ms="
      ++ Nat.show(Nat.sub(finished, started)) ++ " digest=" ++ U32.show(digest))

def run_row_major(+size: U32, +edge: U32, +iterations: Nat) -> IO(Unit):
  +eye : Voxel.Vec = Voxel.Vec{8.0, 14.0, 0.5}
  +yaw : F32 = 0.7
  +pitch : F32 = 0.30
  +depth = if_nat(U32.is_lt(size, 40), U32.is_lt(size, 100), 5n, 6n, 7n)
  +view_half : F32 = Voxel.projection_half(depth)
  +focal : F32 = F32.mul(1.5, view_half)
  +faces = Face.faces_from_chunk(World.chunk(1337n, 0n, 0n))
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 = project_row_major_many(iterations, faces, eye, yaw, pitch, size,
      edge, view_half, focal, 2166136261)
    consumed : Unit <- IO.print("consume=row-major:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print("phase=row_major size=" ++ U32.show(size) ++ " edge=" ++ U32.show(edge)
      ++ " iterations=" ++ Nat.show(iterations) ++ " elapsed_ms="
      ++ Nat.show(Nat.sub(finished, started)) ++ " digest=" ++ U32.show(digest))

def run_full_scatter(+size: U32, +depth: Nat, +edge: U32, +iterations: Nat) -> IO(Unit):
  +eye : Voxel.Vec = Voxel.Vec{8.0, 14.0, 0.5}
  +yaw : F32 = 0.7
  +pitch : F32 = 0.30
  +view_half : F32 = Voxel.projection_half(depth)
  +focal : F32 = F32.mul(1.5, view_half)
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 = full_scatter_many(iterations, size, depth, eye, yaw, pitch, edge,
      view_half, focal, 2166136261)
    consumed : Unit <- IO.print("consume=frame-scatter:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print("phase=frame_scatter size=" ++ U32.show(size) ++ " edge=" ++ U32.show(edge)
      ++ " iterations=" ++ Nat.show(iterations) ++ " elapsed_ms="
      ++ Nat.show(Nat.sub(finished, started)) ++ " digest=" ++ U32.show(digest))

def run_full_row_major(+size: U32, +depth: Nat, +edge: U32, +iterations: Nat) -> IO(Unit):
  +eye : Voxel.Vec = Voxel.Vec{8.0, 14.0, 0.5}
  +yaw : F32 = 0.7
  +pitch : F32 = 0.30
  +view_half : F32 = Voxel.projection_half(depth)
  +focal : F32 = F32.mul(1.5, view_half)
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 = full_row_major_many(iterations, size, depth, eye, yaw, pitch, edge,
      view_half, focal, 2166136261)
    consumed : Unit <- IO.print("consume=frame-row-major:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print("phase=frame_row_major size=" ++ U32.show(size) ++ " edge=" ++ U32.show(edge)
      ++ " iterations=" ++ Nat.show(iterations) ++ " elapsed_ms="
      ++ Nat.show(Nat.sub(finished, started)) ++ " digest=" ++ U32.show(digest))

def run_tuning() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- run_full_scatter(32, 5n, 8, 8n)
    b : Unit <- run_full_scatter(32, 5n, 16, 8n)
    c : Unit <- run_full_scatter(32, 5n, 32, 8n)
    d : Unit <- run_full_scatter(64, 6n, 8, 8n)
    e : Unit <- run_full_scatter(64, 6n, 16, 8n)
    f : Unit <- run_full_scatter(64, 6n, 32, 8n)
    g : Unit <- run_full_scatter(128, 7n, 8, 8n)
    h : Unit <- run_full_scatter(128, 7n, 16, 8n)
    i : Unit <- run_full_scatter(128, 7n, 32, 8n)
    j : Unit <- run_full_row_major(128, 7n, 8, 8n)
    k : Unit <- run_full_row_major(128, 7n, 16, 8n)
    l : Unit <- run_full_row_major(128, 7n, 32, 8n)
    m : Unit <- run_scatter(128, 8, split_iterations())
    n : Unit <- run_scatter(128, 16, split_iterations())
    o : Unit <- run_scatter(128, 32, split_iterations())
    p : Unit <- run_row_major(128, 8, split_iterations())
    q : Unit <- run_row_major(128, 16, split_iterations())
    run_row_major(128, 32, split_iterations())

def main() -> IO(Unit):
  do IO<Unit>:
    extract32 : Unit <- run_extract(32, split_iterations())
    extract64 : Unit <- run_extract(64, split_iterations())
    extract128 : Unit <- run_extract(128, split_iterations())
    project32 : Unit <- run_project_current(32, 5n, split_iterations())
    project64 : Unit <- run_project_current(64, 6n, split_iterations())
    project128 : Unit <- run_project_current(128, 7n, split_iterations())
    tuning : Unit <- run_tuning()
    IO.print("prep_split=pass")
