import Base
import ../../../world/world.bend as World
import ../../../native/voxel.bend as Voxel
import ../../../native/face.bend as Face

def summarize(+size: U32, +depth: Nat, +edge: U32) -> IO(Unit):
  +half = Voxel.projection_half(depth)
  +focal = F32.mul(1.5, half)
  +camera : Voxel.Camera = Voxel.Camera.look(Voxel.Vec{8.0, 14.0, 0.5}, 0.7, 0.30)
  +scatter = Face.bucket_faces_with_tile_size(
    Face.faces_from_chunk(World.chunk(1337n, 0n, 0n)), Face.cam_eye(camera),
    Face.cam_right(camera), Face.cam_up(camera), Face.cam_forward(camera), half, focal, size, edge)
  +row_major = Face.bucket_faces_row_major_with_tile_size(
    Face.faces_from_chunk(World.chunk(1337n, 0n, 0n)), Face.cam_eye(camera),
    Face.cam_right(camera), Face.cam_up(camera), Face.cam_forward(camera), half, focal, size, edge)
  +scatter_candidates = Face.candidate_count(size, scatter)
  +row_major_candidates = Face.candidate_count(size, row_major)
  +scatter_cells = Face.scatter_grid_list_cells(size, scatter)
  +legacy_cells = Face.legacy_scatter_grid_list_cells(size, scatter)
  +row_major_cells = Face.row_major_grid_list_cells(size, row_major)
  +screen_cells = Face.face_total(Face.faces_from_chunk(World.chunk(1337n, 0n, 0n)))
  +pixel_count = U32.mul(size, size)
  +scatter_per_milli = U32.div(U32.mul(scatter_candidates, 1000), pixel_count)
  +row_major_per_milli = U32.div(U32.mul(row_major_candidates, 1000), pixel_count)
  +row_major_total = U32.add(row_major_cells, screen_cells)
  do IO<Unit>:
    IO.print("bucket size=" ++ U32.show(size) ++ " edge=" ++ U32.show(edge)
      ++ " candidates=" ++ U32.show(scatter_candidates)
      ++ " scatter_per_pixel_milli=" ++ U32.show(scatter_per_milli)
      ++ " row_major_candidates=" ++ U32.show(row_major_candidates)
      ++ " row_major_per_pixel_milli=" ++ U32.show(row_major_per_milli)
      ++ " legacy_scatter_list_cells=" ++ U32.show(legacy_cells)
      ++ " direct_scatter_list_cells=" ++ U32.show(scatter_cells)
      ++ " row_major_grid_list_cells=" ++ U32.show(row_major_cells)
      ++ " row_major_screen_list_cells=" ++ U32.show(screen_cells)
      ++ " row_major_total_list_cells=" ++ U32.show(row_major_total))

def sizes32() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- summarize(32, 5n, 8)
    b : Unit <- summarize(32, 5n, 16)
    summarize(32, 5n, 32)

def sizes64() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- summarize(64, 6n, 8)
    b : Unit <- summarize(64, 6n, 16)
    summarize(64, 6n, 32)

def sizes128() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- summarize(128, 7n, 8)
    b : Unit <- summarize(128, 7n, 16)
    summarize(128, 7n, 32)

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- sizes32()
    b : Unit <- sizes64()
    c : Unit <- sizes128()
    IO.print("bucket_summary=pass")
