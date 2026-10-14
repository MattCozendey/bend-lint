import Base
import ../world/world.bend as World
import ./voxel.bend as Voxel
import ./face.bend as Face

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, message)

# The ray renderer's label for the -z face of a cell is 5, and for +z is 2, so
# the front view of a block at z=8 seen from z=0.5 must report (block 1, face 5)
# and the same block seen from z=15.5 must report (block 1, face 2). Packing them
# as block*8 + face makes one integer cover the pair the comparison needs.
def front_key() -> U32:
  ((1 : U32) * 8 + 5 : U32)

def back_key() -> U32:
  ((1 : U32) * 8 + 2 : U32)

def center_child(first: Bool, image: Image) -> Image:
  match first:
    case True{}:
      match image:
        case Pix{color}:
          Pix{color}
        case Qua{tl, tr, bl, br}:
          br
    case False{}:
      match image:
        case Pix{color}:
          Pix{color}
        case Qua{tl, tr, bl, br}:
          tl

# Follow pixel (16,16) in a 32x32 quadtree. It enters the lower-right root tile,
# then the upper-left child at each smaller level.
def center_pixel(depth: Nat, first: Bool, image: Image) -> U32:
  match depth:
    case 0n:
      match image:
        case Pix{color}:
          color
        case Qua{tl, tr, bl, br}:
          0
    case 1n+q:
      +next = center_child(first, image)
      center_pixel(q, False{}, next)

# How many pixels of a frame show exactly `key`, and how many show some other
# non-sky face. This is what pins "exactly that block, and not from the other
# side": a renderer that also drew the far face would report a non-zero `wrong`.
type Seen is Data:
  Seen{hits: U32, wrong: U32}

def seen_hits(+s: Seen) -> U32:
  match s:
    case Seen{hits, wrong}:
      hits

def seen_wrong(+s: Seen) -> U32:
  match s:
    case Seen{hits, wrong}:
      wrong

# The ray-versus-face agreement tally for one frame: both empty or both the same
# block and face, the same block but a different face, or a different block.
# `only_face` and `only_ray` split the block disagreements by which renderer
# showed something the other did not; the screen box is only a broad phase, so
# the exact ray/quad intersection should reject false candidates.
type Agreement is Data:
  Agreement{same: U32, face_only: U32, block_diff: U32, only_face: U32, only_ray: U32,
    wrong: U32, both_empty: U32}

def agreement_same(+a: Agreement) -> U32:
  match a:
    case Agreement{same, face_only, block_diff, only_face, only_ray, wrong, both_empty}:
      same

def agreement_face_only(+a: Agreement) -> U32:
  match a:
    case Agreement{same, face_only, block_diff, only_face, only_ray, wrong, both_empty}:
      face_only

def agreement_block_diff(+a: Agreement) -> U32:
  match a:
    case Agreement{same, face_only, block_diff, only_face, only_ray, wrong, both_empty}:
      block_diff

def agreement_only_face(+a: Agreement) -> U32:
  match a:
    case Agreement{same, face_only, block_diff, only_face, only_ray, wrong, both_empty}:
      only_face

def agreement_wrong(+a: Agreement) -> U32:
  match a:
    case Agreement{same, face_only, block_diff, only_face, only_ray, wrong, both_empty}:
      wrong

def agreement_only_ray(+a: Agreement) -> U32:
  match a:
    case Agreement{same, face_only, block_diff, only_face, only_ray, wrong, both_empty}:
      only_ray

def agreement_both_empty(+a: Agreement) -> U32:
  match a:
    case Agreement{same, face_only, block_diff, only_face, only_ray, wrong, both_empty}:
      both_empty

# The extraction tally: cells whose sides disagree with the grid, and the number
# of exposed sides the grid reports.
type Tally is Data:
  Tally{bad: U32, want: U32, actual: U32}

def tally_bad(t: Tally) -> U32:
  match t:
    case Tally{bad, want, actual}:
      bad

def tally_want(t: Tally) -> U32:
  match t:
    case Tally{bad, want, actual}:
      want

def tally_actual(t: Tally) -> U32:
  match t:
    case Tally{bad, want, actual}:
      actual

# The grid the ray renderer consults, used as the reference the one-pass
# extractor must reproduce. Bits follow the ray renderer's face labels:
# 3 = -x, 0 = +x, 4 = -y, 1 = +y, 5 = -z, 2 = +z.
def expected_sides(+grid: Voxel.VoxelGrid, +x: U32, +y: U32, +z: U32) -> U32:
  +b = Voxel.grid_at(grid, x, y, z)
  +m0 = Bool.pick(U32, U32.is_eq(Voxel.grid_at(grid, U32.sub(x, 1), y, z), 0), 8, 0)
  +m1 = Bool.pick(U32, U32.is_eq(Voxel.grid_at(grid, U32.add(x, 1), y, z), 0), 1, 0)
  +m2 = Bool.pick(U32, U32.is_eq(Voxel.grid_at(grid, x, U32.sub(y, 1), z), 0), 16, 0)
  +m3 = Bool.pick(U32, U32.is_eq(Voxel.grid_at(grid, x, U32.add(y, 1), z), 0), 2, 0)
  +m4 = Bool.pick(U32, U32.is_eq(Voxel.grid_at(grid, x, y, U32.sub(z, 1)), 0), 32, 0)
  +m5 = Bool.pick(U32, U32.is_eq(Voxel.grid_at(grid, x, y, U32.add(z, 1)), 0), 4, 0)
  Bool.pick(U32, U32.is_eq(b, 0), 0, U32.or(U32.or(m0, m1), U32.or(U32.or(m2, m3), U32.or(m4, m5))))

# Six bits, so the fuel is the bit position and the recursion terminates.
def popcount(bits: Nat, +value: U32) -> U32:
  match bits:
    case 0n:
      0
    case 1n+p:
      +low = U32.and(value, 1)
      (low + popcount(p, U32.shr(value)) : U32)

def trace_face(trace: Voxel.Trace) -> U32:
  match trace:
    case Voxel.Miss{probes}:
      0
    case Voxel.Hit{block, face, probes}:
      face

# The block and face the ray renderer reports for one pixel, packed the same way
# the face renderer packs them so one compare covers both.
def ray_key(+grid: Voxel.VoxelGrid, +camera: Voxel.Camera, +half: F32, +focal: F32,
  +px: U32, +py: U32) -> U32:
  +trace = Voxel.trace_inside(grid, Voxel.Camera.eye(camera),
    Voxel.Camera.ray_for(camera, px, py, half, focal))
  +block = Voxel.hit_block(trace)
  Bool.pick(U32, U32.is_eq(block, 0), 0,
    U32.add(U32.mul(block, 8), trace_face(trace)))

def one_block() -> Array<U32>:
  Array.set(U32, Array.new(U32, 13n, 0), Voxel.chunk_index(8, 8, 8), 1)

def two_block_chunk() -> Array<U32>:
  one = Array.set(U32, Array.new(U32, 13n, 0), Voxel.chunk_index(3, 4, 5), 1)
  Array.set(U32, one, Voxel.chunk_index(4, 4, 5), 7)

def count_frame(count: Nat, +px: U32, +py: U32, +size: U32,
  +tiles: Face.Tiles, +key: U32, +hits: U32,
  +wrong: U32) -> Seen:
  match count:
    case 0n:
      Seen{hits, wrong}
    case 1n+r:
      +best = Face.face_at_pixel(tiles, px, py)
      +block = Face.b_block(best)
      +seen = Bool.pick(U32, U32.is_eq(block, 0), (0 : U32),
        U32.add(U32.mul(block, 8), U32.from_nat(Face.b_dir(best))))
      +hit = Bool.pick(U32, U32.is_eq(seen, key), (1 : U32), 0)
      +miss = Bool.pick(U32, Bool.or(U32.is_eq(block, 0), U32.is_eq(seen, key)), (0 : U32), 1)
      +last = U32.is_eq(px, U32.sub(size, 1))
      +next_px = Bool.pick(U32, last, 0, (px + 1 : U32))
      +next_py = Bool.pick(U32, last, (py + 1 : U32), py)
      +new_hits = U32.add(hits, hit)
      +new_wrong = U32.add(wrong, miss)
      count_frame(r, next_px, next_py, size, tiles, key, new_hits, new_wrong)

# The `away` view must show no solid face at all. Counting the key 0 alone would
# count every sky pixel as a hit, so this walk counts non-sky pixels instead.
def count_solid(count: Nat, +px: U32, +py: U32, +size: U32,
  +tiles: Face.Tiles, +solid: U32) -> U32:
  match count:
    case 0n:
      solid
    case 1n+r:
      +best = Face.face_at_pixel(tiles, px, py)
      +hit = Bool.pick(U32, U32.is_eq(Face.b_block(best), 0), (0 : U32), 1)
      +last = U32.is_eq(px, U32.sub(size, 1))
      +next_px = Bool.pick(U32, last, 0, (px + 1 : U32))
      +next_py = Bool.pick(U32, last, (py + 1 : U32), py)
      +next = U32.add(solid, hit)
      count_solid(r, next_px, next_py, size, tiles, next)

def solid_count(tiles: Face.Tiles, +size: U32) -> U32:
  count_solid(U32.to_nat(U32.mul(size, size)), 0, 0, size, tiles, 0)

def count_key(tiles: Face.Tiles, +key: U32, +size: U32) -> Seen:
  count_frame(U32.to_nat(U32.mul(size, size)), 0, 0, size, tiles, key, 0, 0)

# Walk every cell in y/z/x order and compare the extracted side mask with the
# grid's. The one-pass extractor must agree on all 5120 cells of the real chunk.
def scan_cells(count: Nat, +y: U32, +z: U32, +x: U32, +faces: List<&2, Face.Face>,
  +grid: Voxel.VoxelGrid, +bad: U32, +want: U32, +actual: U32) -> Tally:
  match count:
    case 0n:
      Tally{bad, want, actual}
    case 1n+r:
      +sides = expected_sides(grid, x, y, z)
      +at = Face.face_at(faces, x, y, z)
      +seen = Face.at_mask(at)
      +seen_total = Face.at_total(at)
      +expected_total = popcount(6n, sides)
      +same_mask = U32.is_eq(seen, sides)
      +same_count = U32.is_eq(seen_total, expected_total)
      +miss = Bool.pick(U32, Bool.and(same_mask, same_count), 0, 1)
      +next_y = Bool.pick(U32, U32.is_eq(x, 15), Bool.pick(U32, U32.is_eq(z, 15), (y + 1 : U32), y), y)
      +next_z = Bool.pick(U32, U32.is_eq(x, 15),
        Bool.pick(U32, U32.is_eq(z, 15), 0, (z + 1 : U32)), z)
      +next_x = Bool.pick(U32, U32.is_eq(x, 15), 0, (x + 1 : U32))
      scan_cells(r, next_y, next_z, next_x, faces, grid, (bad + miss : U32),
        (want + expected_total : U32), U32.add(actual, seen_total))

def compare_frame(count: Nat, +px: U32, +py: U32, +size: U32,
  +tiles: Face.Tiles, +grid: Voxel.VoxelGrid,
  +camera: Voxel.Camera, +half: F32, +focal: F32, +same: U32, +face_only: U32,
  +block_diff: U32, +only_face: U32, +only_ray: U32, +wrong: U32,
  +empty_count: U32) -> Agreement:
  match count:
    case 0n:
      Agreement{same, face_only, block_diff, only_face, only_ray, wrong, empty_count}
    case 1n+r:
      +best = Face.face_at_pixel(tiles, px, py)
      +mine = Bool.pick(U32, U32.is_eq(Face.b_block(best), 0), (0 : U32),
        U32.add(U32.mul(Face.b_block(best), 8), U32.from_nat(Face.b_dir(best))))
      +theirs = ray_key(grid, camera, half, focal, px, py)
      +same_block = Bool.pick(Bool, U32.is_eq(U32.shrn(mine, 3n), U32.shrn(theirs, 3n)), True{}, False{})
      +both_empty = Bool.pick(Bool, U32.is_eq(mine, 0), U32.is_eq(theirs, 0), False{})
      # A pixel agrees when both renderers are empty, or both name the same block
      # and the same face. Anything else falls into face_only (same block, other
      # face) or block_diff (different block, or one empty and one not).
       +equal_hit = U32.is_eq(mine, theirs)
      +mine_solid = Bool.pick(Bool, U32.is_eq(mine, 0), False{}, True{})
      +their_solid = Bool.pick(Bool, U32.is_eq(theirs, 0), False{}, True{})
      +differ = Bool.and(Bool.not(same_block), Bool.not(both_empty))
      +last = U32.is_eq(px, U32.sub(size, 1))
      +next_px = Bool.pick(U32, last, 0, (px + 1 : U32))
      +next_py = Bool.pick(U32, last, (py + 1 : U32), py)
      +new_same = U32.add(same, Bool.pick(U32, equal_hit, (1 : U32), 0))
      +new_face = U32.add(face_only, Bool.pick(U32, Bool.and(same_block, Bool.not(equal_hit)), (1 : U32), 0))
      +new_block = U32.add(block_diff, Bool.pick(U32, differ, (1 : U32), 0))
      +new_only_face = U32.add(only_face, Bool.pick(U32,
        Bool.and(differ, Bool.and(mine_solid, Bool.not(their_solid))), (1 : U32), 0))
      +new_only_ray = U32.add(only_ray, Bool.pick(U32,
        Bool.and(differ, Bool.and(their_solid, Bool.not(mine_solid))), (1 : U32), 0))
      # Both hit, but different blocks: the face renderer picked a nearer box that
      # the ray does not agree is nearer. This is the depth rule's cost.
       +both_differ = Bool.and(differ, Bool.and(mine_solid, their_solid))
       +new_wrong = U32.add(wrong, Bool.pick(U32, both_differ, (1 : U32), 0))
       +new_empty = U32.add(empty_count, Bool.pick(U32, both_empty, (1 : U32), 0))
        compare_frame(r, next_px, next_py, size, tiles, grid, camera, half, focal,
         new_same, new_face, new_block, new_only_face, new_only_ray, new_wrong, new_empty)

# The quadtree depth that matches a frame size, so the two renderers are compared
# at the same `half`/`focal` pair the ray renderer would use.
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

# A one-cell cube is a closed projected silhouette: every rendered solid pixel
# must be a pixel where the reference ray intersects the cube. This catches
# bounding-box corners that happen to intersect an infinite face plane.
def single_block_coverage() -> IO(Unit):
  +size : U32 = 32
  +depth : Nat = 5n
  +half = Voxel.projection_half(depth)
  +focal = F32.mul(1.5, half)
  +camera : Voxel.Camera = Voxel.Camera.look(Voxel.Vec{8.5, 8.5, 0.5}, 0.0, 0.0)
  +grid : Voxel.VoxelGrid = Voxel.grid_from_chunk(one_block())
  +tiles = Face.bucket_faces(Face.faces_from_chunk(one_block()), Face.cam_eye(camera),
    Face.cam_right(camera), Face.cam_up(camera), Face.cam_forward(camera), half, focal, size)
  +result = compare_frame(1024n, 0, 0, size, tiles, grid, camera, half, focal,
    0, 0, 0, 0, 0, 0, 0)
  do IO<Unit>:
    Unit <- check(U32.is_eq(agreement_block_diff(result), 0),
      "single-block projected coverage disagreed with ray visibility")
    check(U32.is_eq(agreement_face_only(result), 0),
      "single-block coverage selected a different face from the ray")

# A ray parallel to a face plane has no finite plane hit. The camera sees the
# cube's -x face head-on; the exactly edge-on -z face must not steal its pixel.
def edge_on_face_test() -> IO(Unit):
  +size : U32 = 32
  +half = Voxel.projection_half(5n)
  +focal = F32.mul(1.5, half)
  +camera : Voxel.Camera = Voxel.Camera.look(Voxel.Vec{0.5, 8.5, 8.5},
    1.57079632679, 0.0)
  +tiles = Face.bucket_faces(Face.faces_from_chunk(one_block()), Face.cam_eye(camera),
    Face.cam_right(camera), Face.cam_up(camera), Face.cam_forward(camera), half, focal, size)
  +best = Face.face_at_pixel(tiles, 16, 16)
  do IO<Unit>:
    Unit <- check(U32.is_eq(Face.b_block(best), 1),
      "the edge-on fixture did not show its visible cube")
    check(U32.is_eq(U32.from_nat(Face.b_dir(best)), 3),
      "an exactly edge-on face won the pixel")

# A face crossing the camera plane must be conservatively bucketed, then resolved
# by the actual ray/quad intersection rather than dropped with one bad corner.
def near_plane_test() -> IO(Unit):
  +size : U32 = 32
  +half = Voxel.projection_half(5n)
  +focal = F32.mul(1.5, half)
  +camera : Voxel.Camera = Voxel.Camera.look(Voxel.Vec{0.5, 0.5, 0.999}, 2.4415927, 0.3)
  +faces : List<&2, Face.Face> = Face.Face{0, 0, 1, 5n, 1} <> []
  +screen = Face.box_of(5n, 1, 0.0, 0.0, 1.0, Face.cam_eye(camera),
    Face.cam_right(camera), Face.cam_up(camera), Face.cam_forward(camera), half, focal)
  +tiles = Face.bucket_faces(faces, Face.cam_eye(camera), Face.cam_right(camera),
    Face.cam_up(camera), Face.cam_forward(camera), half, focal, size)
  +best = Face.face_at_pixel(tiles, 15, 15)
  do IO<Unit>:
    Unit <- check(Bool.and(Face.s_alive(screen), Bool.and(U32.is_eq(Face.s_x0(screen), 0),
        U32.is_eq(Face.s_x1(screen), 65535))),
      "the near-plane-crossing face did not use its conservative candidate bounds")
    check(U32.is_eq(Face.b_block(best), 1),
      "the near-plane-crossing face was dropped instead of intersected")

# This face projects to much less than one pixel and is positioned between ray
# sample centres. Its screen box may touch a pixel, but its exact quad must not.
# Yaw pi looks toward +z, and at yaw pi the game's right axis points at -x, so the
# face at x 520 lands left of centre rather than right of it.
def subpixel_face_test() -> IO(Unit):
  +size : U32 = 32
  +half = Voxel.projection_half(5n)
  +focal = F32.mul(1.5, half)
  +camera : Voxel.Camera = Voxel.Camera.look(Voxel.Vec{0.5, 0.5, 0.0}, 3.14159265, 0.0)
  +faces : List<&2, Face.Face> = Face.Face{520, 0, 10000, 5n, 1} <> []
  +tiles = Face.bucket_faces(faces, Face.cam_eye(camera), Face.cam_right(camera),
    Face.cam_up(camera), Face.cam_forward(camera), half, focal, size)
  +best = Face.face_at_pixel(tiles, 14, 15)
  +edge = Face.tile_size()
  +bucket = Face.bucket_at(Face.tiles_rows(tiles), U32.div(14, edge), U32.div(15, edge))
  do IO<Unit>:
    Unit <- check(U32.is_gt(U32.from_nat(List.length(&2, Face.Screen, bucket)), 0),
      "the subpixel fixture did not reach the pixel's conservative candidate box")
    check(U32.is_eq(Face.b_block(best), 0),
      "a subpixel face between sample centres claimed a pixel")

# The two box-test shapes must be the same answer, not two renderers that happen to
# agree on the fixtures anyone thought to write.
#
# `scan_bucket` splits the packed-box test so the second compare is conditional, and
# `scan_bucket_one` folds the two halves into one `Bool.and` so the reject path makes
# one call instead of two. The bench measures the two the same over three runs, so the
# shipped walk keeps the split and there is nothing to collect. That is only safe
# while the two agree on every pixel of a real grid, which is what this counts. The
# count is of pixels where the two chose a different block, a different face label, or
# a different depth, and it must be zero.
def walk_shape_bad(+px: U32, +py: U32, +tiles: Face.Tiles, +bad: U32) -> U32:
  +shipped = Face.face_at_pixel(tiles, px, py)
  +folded = Face.nearest_face_one(tiles, px, py)
  +same_block = U32.is_eq(Face.b_block(shipped), Face.s_block(folded))
  +same_dir = U32.is_eq(U32.from_nat(Face.b_dir(shipped)), U32.from_nat(Face.s_dir(folded)))
  +same_depth = F32.is_eq(Face.b_depth(shipped), Face.s_depth(folded))
  +same = Bool.and(same_block, Bool.and(same_dir, same_depth))
  U32.add(Bool.pick(U32, same, 0, 1), bad)

def walk_shape_count(+tiles: Face.Tiles, remaining: Nat, +px: U32, +py: U32,
  +bad: U32) -> U32:
  match remaining:
    case 0n:
      bad
    case 1n+r:
      walk_shape_count(tiles, r, (px + 1 : U32), py, walk_shape_bad(px, py, tiles, bad))

def walk_shape_rows(+tiles: Face.Tiles, rows_left: Nat, +py: U32, +size: U32,
  +bad: U32) -> U32:
  match rows_left:
    case 0n:
      bad
    case 1n+r:
      walk_shape_rows(tiles, r, (py + 1 : U32), size,
        walk_shape_count(tiles, U32.to_nat(size), 0, py, bad))

def walk_shape_test() -> IO(Unit):
  +size : U32 = 32
  +half = Voxel.projection_half(5n)
  +focal = F32.mul(1.5, half)
  +camera : Voxel.Camera = Voxel.Camera.look(Voxel.Vec{8.5, 8.5, 0.5}, 3.14159265, 0.0)
  +tiles = Face.bucket_faces(Face.faces_from_chunk(one_block()), Face.cam_eye(camera),
    Face.cam_right(camera), Face.cam_up(camera), Face.cam_forward(camera), half, focal, size)
  +bad = walk_shape_rows(tiles, U32.to_nat(size), 0, size, 0)
  +covered = solid_count(tiles, size)
  do IO<Unit>:
    Unit <- check(U32.is_gt(covered, 0),
      "the walk-shape fixture covered no pixel, so it would agree vacuously")
    check(U32.is_eq(bad, 0),
      "the split box test and the folded box test chose different faces")

# Starting inside a single solid cube means every forward ray exits through one
# of its exposed faces; the face renderer must not turn that volume into sky.
def containing_block_test() -> IO(Unit):
  +size : U32 = 32
  +half = Voxel.projection_half(5n)
  +focal = F32.mul(1.5, half)
  +camera : Voxel.Camera = Voxel.Camera.look(Voxel.Vec{8.5, 8.5, 8.5}, 0.0, 0.0)
  +tiles = Face.bucket_faces(Face.faces_from_chunk(one_block()), Face.cam_eye(camera),
    Face.cam_right(camera), Face.cam_up(camera), Face.cam_forward(camera), half, focal, size)
  +solid = solid_count(tiles, size)
  check(U32.is_eq(solid, U32.mul(size, size)),
    "the camera-containing block did not cover every forward pixel")

# The centre pixel of the fixture, pinned to the exact block and face. This is
# the direct check that the renderer shows the block and the correct side of it.
def single_block_centre() -> IO(Unit):
  +size : U32 = 32
  +half = Voxel.projection_half(5n)
  +focal = F32.mul(1.5, half)
  +camera : Voxel.Camera = Voxel.Camera.look(Voxel.Vec{8.5, 8.5, 0.5}, 3.14159265, 0.0)
  +tiles = Face.bucket_faces(Face.faces_from_chunk(one_block()), Face.cam_eye(camera),
    Face.cam_right(camera), Face.cam_up(camera), Face.cam_forward(camera), half, focal, size)
  +best = Face.face_at_pixel(tiles, 16, 16)
  +image = Face.render_size_at(one_block(), Voxel.Vec{8.5, 8.5, 0.5}, 3.14159265, 0.0, 5n)
  +rendered = center_pixel(5n, True{}, image)
  +expected = Voxel.shade_color(Voxel.block_color(1), 5)
  do IO<Unit>:
    Unit <- check(U32.is_eq(Face.b_block(best), 1),
      "the single stone block did not show stone at the screen centre from -z")
    Unit <- check(U32.is_eq(U32.from_nat(Face.b_dir(best)), 5),
      "the single stone block showed the wrong face label from -z")
    check(U32.is_eq(rendered, expected),
      "the rendered image did not show the stone at the screen centre")

# The pinned view the agreement comparison and the bucketing equivalence both
# use, over the real chunk at seed 1337. Yaw and pitch are spelled so the camera
# looks toward +x, down and +z from the chunk's -z corner, which is the direction
# `Player.direction` gives for this pair.
def agreement_camera() -> Voxel.Camera:
  Voxel.Camera.look(Voxel.Vec{8.0, 14.0, 0.5}, 2.4415927, F32.neg(0.30))

# The row-major bucket builder is an alternative implementation, not a relaxed
# renderer contract: it must produce the same image and candidate walk as scatter.
def row_major_matches_scatter(+edge: U32) -> IO(Unit):
  +size : U32 = 128
  +half = Voxel.projection_half(7n)
  +focal = F32.mul(1.5, half)
  +camera : Voxel.Camera = agreement_camera()
  +scatter = Face.bucket_faces_with_tile_size(Face.faces_from_chunk(World.chunk(1337n, 0n, 0n)),
    Face.cam_eye(camera), Face.cam_right(camera), Face.cam_up(camera), Face.cam_forward(camera),
    half, focal, size, edge)
  +row_major = Face.bucket_faces_row_major_with_tile_size(
    Face.faces_from_chunk(World.chunk(1337n, 0n, 0n)), Face.cam_eye(camera),
    Face.cam_right(camera), Face.cam_up(camera), Face.cam_forward(camera), half, focal, size, edge)
  +scatter_candidates = Face.candidate_count(size, scatter)
  +row_major_candidates = Face.candidate_count(size, row_major)
  +scatter_hash = Voxel.fingerprint(Face.render_size_tiles(scatter, 7n))
  +row_major_hash = Voxel.fingerprint(Face.render_size_tiles(row_major, 7n))
  do IO<Unit>:
    Unit <- check(U32.is_eq(scatter_hash, row_major_hash),
      "row-major bucketing changed the rendered image")
    check(U32.is_eq(scatter_candidates, row_major_candidates),
      "row-major bucketing changed the candidate count")

# The whole frame from three sides. Each view must show the block on exactly the
# side the camera is on, and a camera facing away must show nothing.
def seen_line(+label: String, +s: Seen) -> IO(Unit):
  do IO<Unit>:
    IO.print(label ++ " hits=" ++ U32.show(seen_hits(s)) ++ " wrong=" ++ U32.show(seen_wrong(s)))

def single_block_views() -> IO(Unit):
  +size : U32 = 32
  +half = Voxel.projection_half(5n)
  +focal = F32.mul(1.5, half)
  +front_camera : Voxel.Camera = Voxel.Camera.look(Voxel.Vec{8.5, 8.5, 0.5}, 3.14159265, 0.0)
  +back_camera : Voxel.Camera = Voxel.Camera.look(Voxel.Vec{8.5, 8.5, 15.5}, 0.0, 0.0)
  +away_camera : Voxel.Camera = Voxel.Camera.look(Voxel.Vec{8.5, 8.5, 15.5}, 3.14159265, 0.0)
  +front_tiles = Face.bucket_faces(Face.faces_from_chunk(one_block()),
    Face.cam_eye(front_camera), Face.cam_right(front_camera), Face.cam_up(front_camera),
    Face.cam_forward(front_camera), half, focal, size)
  +back_tiles = Face.bucket_faces(Face.faces_from_chunk(one_block()),
    Face.cam_eye(back_camera), Face.cam_right(back_camera), Face.cam_up(back_camera),
    Face.cam_forward(back_camera), half, focal, size)
  +away_tiles = Face.bucket_faces(Face.faces_from_chunk(one_block()),
    Face.cam_eye(away_camera), Face.cam_right(away_camera), Face.cam_up(away_camera),
    Face.cam_forward(away_camera), half, focal, size)
  +front_seen = count_key(front_tiles, front_key(), size)
  +back_seen = count_key(back_tiles, back_key(), size)
  +away_solid = solid_count(away_tiles, size)
  do IO<Unit>:
    a : Unit <- seen_line("front", front_seen)
    b : Unit <- seen_line("back", back_seen)
    c : Unit <- IO.print("away solid=" ++ U32.show(away_solid))
    Unit <- check(U32.is_gt(seen_hits(front_seen), 0),
      "the single stone block rendered no pixel from the front")
    Unit <- check(U32.is_eq(seen_wrong(front_seen), 0),
      "the front view showed a pixel that was not the stone -z face")
    Unit <- check(U32.is_gt(seen_hits(back_seen), 0),
      "the single stone block rendered no pixel from behind")
    Unit <- check(U32.is_eq(seen_wrong(back_seen), 0),
      "the back view showed a pixel that was not the stone +z face")
    check(U32.is_eq(away_solid, 0),
      "a camera looking away from the block still showed it")

# Face extraction on a hand-built chunk, pinned exactly rather than through the
# renderer. `chunk_index` takes (x, z, y), so the fixture places stone at
# x=3, z=4, y=5 and a second block at x=4, z=4, y=5 — the two are adjacent in x.
#
# The first block's mask is 62: every side except dir 0 (+x), which touches the
# adjacent block. The second block's mask is 55: every side except dir 3 (-x).
def extraction_test() -> IO(Unit):
  +faces = Face.faces_from_chunk(two_block_chunk())
  +at_3 = Face.at_mask(Face.face_at(faces, 3, 5, 4))
  +at_4 = Face.at_mask(Face.face_at(faces, 4, 5, 4))
  +total = Face.face_total(faces)
  do IO<Unit>:
    Unit <- check(U32.is_eq(total, 10), "the two-block fixture did not emit ten exposed faces")
    Unit <- check(U32.is_eq(at_3, 62), "the stone at (3,5,4) lost or gained a side")
    check(U32.is_eq(at_4, 55), "the block at (4,5,4) kept the face touching stone")

def extract_agreement() -> IO(Unit):
  +faces = Face.faces_from_chunk(World.chunk(1337n, 0n, 0n))
  +grid : Voxel.VoxelGrid = Voxel.grid_from_chunk(World.chunk(1337n, 0n, 0n))
  +tally = scan_cells(5120n, 0, 0, 0, faces, grid, 0, 0, 0)
  +actual_faces = Face.face_total(faces)
  do IO<Unit>:
    Unit <- check(U32.is_eq(tally_bad(tally), 0),
      "the one-pass extraction disagreed with the grid on the real chunk")
    Unit <- check(U32.is_eq(tally_actual(tally), tally_want(tally)),
      "the extractor emitted duplicate faces at one or more cells")
    Unit <- check(U32.is_eq(actual_faces, tally_actual(tally)),
      "the extractor emitted duplicate or missing faces")
    IO.print("extract seed1337 faces=" ++ U32.show(tally_want(tally))
      ++ " actual=" ++ U32.show(tally_actual(tally))
      ++ " mismatches=" ++ U32.show(tally_bad(tally)))

# One size's comparison between the two renderers, on the real chunk. An
# `Array<U32>` is linear, so each consumer gets its own bulk call.
def agreement(+size: U32) -> IO(Unit):
  +grid : Voxel.VoxelGrid = Voxel.grid_from_chunk(World.chunk(1337n, 0n, 0n))
  +faces = Face.faces_from_chunk(World.chunk(1337n, 0n, 0n))
  +depth = if_nat(U32.is_lt(size, 40), U32.is_lt(size, 100), 5n, 6n, 7n)
  +half = Voxel.projection_half(depth)
  +focal = F32.mul(1.5, half)
  +camera : Voxel.Camera = agreement_camera()
  +tiles = Face.bucket_faces(faces, Face.cam_eye(camera), Face.cam_right(camera),
    Face.cam_up(camera), Face.cam_forward(camera), half, focal, size)
  +result = compare_frame(U32.to_nat(U32.mul(size, size)), 0, 0, size,
    tiles, grid, camera, half, focal, 0, 0, 0, 0, 0, 0, 0)
  +empty = agreement_both_empty(result)
  +pixels = U32.mul(size, size)
  +error_limit = U32.div(pixels, 100)
  +classified = U32.add(U32.add(agreement_same(result), agreement_face_only(result)),
    agreement_block_diff(result))
  do IO<Unit>:
    Unit <- check(U32.is_le(empty, agreement_same(result)),
      "both-empty pixels were not counted as agreements")
    Unit <- check(U32.is_eq(classified, U32.mul(size, size)),
      "ray-versus-face agreement categories did not cover the frame")
    Unit <- check(U32.is_eq(agreement_only_ray(result), 0),
      "the face renderer missed a block reported by the ray renderer")
    Unit <- check(U32.is_le(agreement_wrong(result), error_limit),
      "wrong-block rate exceeded the 1% agreement limit")
    Unit <- check(U32.is_le(agreement_only_face(result), error_limit),
      "spurious-block rate exceeded the 1% agreement limit")
    Unit <- check(U32.is_le(agreement_block_diff(result), error_limit),
      "total block-disagreement rate exceeded the 1% agreement limit")
    IO.print("ray_vs_face size=" ++ U32.show(size)
      ++ " pixels=" ++ U32.show(U32.mul(size, size))
      ++ " same=" ++ U32.show(agreement_same(result))
      ++ " both_empty=" ++ U32.show(empty)
      ++ " face_only=" ++ U32.show(agreement_face_only(result))
      ++ " block_diff=" ++ U32.show(agreement_block_diff(result))
      ++ " only_face=" ++ U32.show(agreement_only_face(result))
       ++ " only_ray=" ++ U32.show(agreement_only_ray(result))
       ++ " wrong_block=" ++ U32.show(agreement_wrong(result))
       ++ " wrong_per_mille=" ++ U32.show(U32.div(U32.mul(agreement_wrong(result), 1000), pixels))
       ++ " spurious_per_mille=" ++ U32.show(U32.div(U32.mul(agreement_only_face(result), 1000), pixels))
       ++ " candidates=" ++ U32.show(Face.candidate_count(size, tiles))
      ++ " per_pixel=" ++ U32.show(U32.div(Face.candidate_count(size, tiles),
        U32.mul(size, size))))

# The measured agreement is also gated: wrong blocks, spurious blocks and total
# block differences may each occupy at most one percent of the frame.
def agreement_test() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- agreement(32)
    b : Unit <- agreement(64)
    c : Unit <- agreement(128)
    IO.print("agreement=asserted max_wrong=1% max_spurious=1% max_block_diff=1%")

def main() -> IO(Unit):
  do IO<Unit>:
    centre : Unit <- single_block_centre()
    row_major8 : Unit <- row_major_matches_scatter(8)
    row_major16 : Unit <- row_major_matches_scatter(16)
    row_major32 : Unit <- row_major_matches_scatter(32)
    coverage : Unit <- single_block_coverage()
    edge_on : Unit <- edge_on_face_test()
    near_plane : Unit <- near_plane_test()
    subpixel : Unit <- subpixel_face_test()
    walk_shape : Unit <- walk_shape_test()
    containing : Unit <- containing_block_test()
    views : Unit <- single_block_views()
    extraction : Unit <- extraction_test()
    extract_check : Unit <- extract_agreement()
    agree : Unit <- agreement_test()
    IO.print("face_probe=pass single_block=pass projection_cases=pass views=pass extraction=pass agreement=asserted")

#|extract seed1337 faces=1298 actual=1298 mismatches=0
#|ray_vs_face size=32 pixels=1024 same=1024 both_empty=553 face_only=0 block_diff=0 only_face=0 only_ray=0 wrong_block=0 wrong_per_mille=0 spurious_per_mille=0 candidates=136320 per_pixel=133
#|ray_vs_face size=64 pixels=4096 same=4096 both_empty=2219 face_only=0 block_diff=0 only_face=0 only_ray=0 wrong_block=0 wrong_per_mille=0 spurious_per_mille=0 candidates=280576 per_pixel=68
#|ray_vs_face size=128 pixels=16384 same=16384 both_empty=8889 face_only=0 block_diff=0 only_face=0 only_ray=0 wrong_block=0 wrong_per_mille=0 spurious_per_mille=0 candidates=796736 per_pixel=48
#|agreement=asserted max_wrong=1% max_spurious=1% max_block_diff=1%
#|face_probe=pass single_block=pass projection_cases=pass views=pass extraction=pass agreement=asserted
