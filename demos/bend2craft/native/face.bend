import Base
import ../world/world.bend as World
import ./voxel.bend as Voxel

# ---------------------------------------------------------------------------
# Visible-face renderer, against the per-pixel ray renderer in
# `voxel.bend`.
# The ray renderer pays about 21 DDA probes per pixel, each probe three nested
# `List.get` walks, so a pixel costs roughly 1100 cons steps. This renderer inverts
# the work:
#
#   1. `faces_from_chunk` walks the 5120 bulk cells once, in the same y/z/x
#      order the nested grid uses, and emits one `Face` per exposed side. All six
#      neighbours of a cell are already in hand from the walk: -x is the previous
#      value, +x the next one, -z the previous z-row, +z the next z-row, and
#      -y/+y the carried rows of the layers below and above. No neighbour is ever
#      read back from the grid, so extraction is linear in the cell count.
#   2. `bucket_faces` projects each face's corners to a conservative screen box
#      and pushes the face into every screen tile that box meets.
#   3. `image` casts the corresponding pixel ray against each candidate's plane,
#      keeps only hits inside the unit face quad, and chooses the nearest hit.
#
# The quadtree fold, the block palette and the per-face tint are reused from
# `Voxel` unchanged, so the two renderers are directly comparable per pixel.
# ---------------------------------------------------------------------------

# One exposed side of one solid cell.
#
# `dir` is the ray renderer's own label for the side the face sits on, so no
# translation table is needed to compare or to tint: 3 is -x, 0 is +x, 4 is -y,
# 1 is +y, 5 is -z and 2 is +z. Those are the labels `Voxel.trace_steps` assigns
# when a ray enters a cell through that side, and `Voxel.shade_color` reduces
# them by `mod 3` to the same three axes.
type Face is Data:
  Face{x: U32, y: U32, z: U32, dir: Nat, block: U32}

# The six neighbour block values around one cell, gathered from the walk.
type Neighbours is Data:
  Neighbours{block: U32, xm: U32, xp: U32, ym: U32, yp: U32, zm: U32, zp: U32}

# A world point.
type P is Data:
  P{x: F32, y: F32, z: F32}

# A projected corner: screen position and camera-space depth.
type Q is Data:
  Q{sx: F32, sy: F32, depth: F32}

# The running bounds over a face's four projected corners.
type Bounds is Data:
  Bounds{x0: F32, y0: F32, x1: F32, y1: F32, near: F32, alive: Bool}

# A face reduced to a conservative pixel box. Near-plane-crossing faces use the
# full frame as their candidate box; the ray/quad test still decides ownership.
#
# The box is stored packed rather than as four numbers: `low` is `x0 | y0 << 16` and
# `high` is `x1 | y1 << 16`. Two reasons, and both are about the per-pixel walk. A
# pixel packs the same way, and because the halves occupy disjoint bit ranges with y
# in the more significant one, `low <= pix <= high` as two unsigned compares is
# exactly `x0 <= px <= x1 and y0 <= py <= y1`: y decides first and the x halves are
# only compared when y ties. And it is the whole test, where the four-number form
# needed four `U32.is_le` and three `Bool.and`, each of which is a call the pinned
# runtime dispatches. At the client's own view that is 170 candidates for each of
# 4,096 pixels, so the walk is the frame.
#
# Every coordinate is at most 65535: `corners` clamps the near-plane fallback to
# that and `clip` clamps the rest to the frame edge, so no half can overflow into
# its neighbour.
type Screen is Data:
  Screen{low: U32, high: U32, depth: F32, block: U32, dir: Nat, alive: Bool,
    origin: P}

# Pack one corner of a box into the single word the pixel walk compares against.
def pack(x: U32, y: U32) -> U32:
  U32.or(x, U32.shln(y, 16n))

# The screen tile grid: tile rows, then buckets within a row, then the faces in a
# bucket. A bucket is only ever read, so one `&2` grid is shared by every pixel.
type Tiles is Data:
  Tiles{rows: List<&2, List<&2, List<&2, Screen>>>, size: U32, edge: U32,
    camera: Voxel.Camera, half: F32, focal: F32}

# The winning face for one pixel. The candidate count this record used to carry is
# gone: the walk advanced it once per candidate, which meant one `Best` allocation
# per candidate, and the number it reported was `List.length` of the pixel's own
# bucket. `Face.candidate_count` still reports that, from the bucket lengths, with
# no per-candidate work at all.
type Best is Data:
  Best{block: U32, dir: Nat, depth: F32}

# What an observation pass counted over one frame.
type Observed is Data:
  Observed{hits: U32, wrong: U32, sky: U32}

# The ray-versus-face agreement tally for one frame.
type Agreement is Data:
  Agreement{same: U32, face_only: U32, block_diff: U32}

def agreement_same(a: Agreement) -> U32:
  match a:
    case Agreement{same, face_only, block_diff}:
      same

def agreement_face_only(a: Agreement) -> U32:
  match a:
    case Agreement{same, face_only, block_diff}:
      face_only

def agreement_block_diff(a: Agreement) -> U32:
  match a:
    case Agreement{same, face_only, block_diff}:
      block_diff

# One layer is `extent_z` z-rows of `extent_x` cells; `Layers` is 20 of those.
type Layers is Data:
  Layers{rows: List<&2, List<&2, U32>>}

# A region of `columns` x `rows` chunks is `chunk_size * columns` cells wide and
# `chunk_size * rows` deep. The walks below take that extent as an argument instead
# of reading one chunk's width, so the same walk covers one chunk or nine and the
# face count stops being capped by the size of a single `Array<U32>`.
def width() -> U32:
  U32.from_nat(World.chunk_size())

def extent_x(columns: Nat) -> U32:
  U32.mul(width(), U32.from_nat(columns))

def extent_z(rows: Nat) -> U32:
  U32.mul(width(), U32.from_nat(rows))

def layer_count() -> Nat:
  World.max_y()

def tile_shift() -> Nat:
  3n

def share_blocks(blocks: List<&1, U32>) -> List<&2, U32>:
  match blocks:
    case Nil{}:
      []
    case +block <> rest:
      block <> share_blocks(rest)

def air_row(extent: U32) -> List<&2, U32>:
  List.replicate(U32, U32.to_nat(extent), 0)

def air_values(cells: U32, rows_deep: U32) -> List<&2, U32>:
  List.replicate(U32, U32.to_nat(U32.mul(cells, rows_deep)), 0)

def rows_of(remaining: Nat, +cells: U32, +values: List<&2, U32>,
  +rows: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match remaining:
    case 0n:
      List.reverse(&2, List<&2, U32>, rows)
    case 1n+p:
      +row : List<&2, U32> = List.take(&2, U32, values, U32.to_nat(cells))
      rows_of(p, cells, List.drop(&2, U32, values, U32.to_nat(cells)), row <> rows)

def air_layer(+cells: U32, +rows_deep: U32) -> List<&2, List<&2, U32>>:
  rows_of(U32.to_nat(rows_deep), cells, air_values(cells, rows_deep), [])

def layers_of(remaining: Nat, +cells: U32, +rows_deep: U32, +values: List<&2, U32>,
  +layers: List<&2, List<&2, List<&2, U32>>>) -> List<&2, List<&2, List<&2, U32>>>:
  match remaining:
    case 0n:
      List.reverse(&2, List<&2, List<&2, U32>>, layers)
    case 1n+p:
      +per_layer = U32.to_nat(U32.mul(cells, rows_deep))
      layers_of(p, cells, rows_deep, List.drop(&2, U32, values, per_layer),
        rows_of(U32.to_nat(rows_deep), cells,
          List.take(&2, U32, values, per_layer), []) <> layers)

# ---------------------------------------------------------------------------
# 1. Face extraction: one forward pass, no per-neighbour lookups.
# ---------------------------------------------------------------------------

# Emit the exposed sides of one cell. A side is exposed when the cell is solid
# and the neighbour on that side is air. The label is the ray renderer's label
# for that side, so a face's index is directly comparable with a ray hit's.
#
# The six sides are folded in a fixed order (3, 0, 4, 1, 5, 2) so each step
# receives the accumulator once and returns it once, which the linear
# accumulator demands.
# Offer one face, or nothing, so the shared accumulator is consumed exactly once
# on each path. `Bool.pick` would need both of its branches to hold the
# accumulator at the same time, which the linear check rejects.
def offer(cond: Bool, +x: U32, +y: U32, +z: U32, dir: Nat, +b: U32) -> Maybe<&2, Face>:
  Bool.pick(Maybe<&2, Face>, cond, Some{Face{x, y, z, dir, b}}, None{})

def put(m: Maybe<&2, Face>, acc: List<&2, Face>) -> List<&2, Face>:
  match m:
    case None{}:
      acc
    case Some{face}:
      face <> acc

def emit_sides(+b: U32, +xm: U32, +xp: U32, +ym: U32, +yp: U32, +zm: U32,
  +zp: U32, +x: U32, +y: U32, +z: U32, acc: List<&2, Face>) -> List<&2, Face>:
  +a = put(offer(U32.is_eq(xm, 0), x, y, z, 3n, b), acc)
  +c = put(offer(U32.is_eq(xp, 0), x, y, z, 0n, b), a)
  +d = put(offer(U32.is_eq(ym, 0), x, y, z, 4n, b), c)
  +e = put(offer(U32.is_eq(yp, 0), x, y, z, 1n, b), d)
  +f = put(offer(U32.is_eq(zm, 0), x, y, z, 5n, b), e)
  put(offer(U32.is_eq(zp, 0), x, y, z, 2n, b), f)

# Emit the exposed sides of one cell. A side is exposed when the cell is solid
# and the neighbour on that side is air. The label is the ray renderer's label
# for that side, so a face's index is directly comparable with a ray hit's.
#
# The six sides are folded in a fixed order (3, 0, 4, 1, 5, 2) so each step
# receives the accumulator once and returns it once, which the linear
# accumulator demands.
def emit(solid: Bool, b: U32, xm: U32, xp: U32, ym: U32, yp: U32, zm: U32, zp: U32,
  +x: U32, +y: U32, +z: U32, acc: List<&2, Face>) -> List<&2, Face>:
  match solid:
    case False{}:
      acc
    case True{}:
      emit_sides(b, xm, xp, ym, yp, zm, zp, x, y, z, acc)

# Walk the 16 cells of one z-row. Five rows are peeled in lockstep, so every
# neighbour of the current cell is a list head: `zm_row` is the same x of the
# previous z-row, `row` is this cell, `zp_row` the next z-row, `ym_row` the same
# x of the layer below and `yp_row` the layer above. `prev_value` carries the -x
# neighbour, because it is the cell just visited.
def x_walk(remaining: Nat, +zm_row: List<&2, U32>, +row: List<&2, U32>,
  +zp_row: List<&2, U32>, +ym_row: List<&2, U32>, +yp_row: List<&2, U32>,
  +prev_value: U32, +x: U32, +y: U32, +z: U32, +acc: List<&2, Face>) -> List<&2, Face>:
  match remaining:
    case 0n:
      acc
    case 1n+r:
      match zm_row row zp_row ym_row yp_row:
        case Nil{} _ _ _ _:
          acc
        case _ Nil{} _ _ _:
          acc
        case _ _ Nil{} _ _:
          acc
        case _ _ _ Nil{} _:
          acc
        case _ _ _ _ Nil{}:
          acc
        case zm <> zmt +h <> t +zp <> zpt ym <> ymt yp <> ypt:
          +xp = Maybe.default(&2, U32, List.head(&2, U32, t), 0)
          +faces = emit(U32.is_ne(h, 0), h, prev_value, xp, ym, yp, zm, zp, x, y, z, acc)
          x_walk(r, zmt, t, zpt, ymt, ypt, h, (x + 1 : U32), y, z, faces)

# The head of a row, or an all-air row when the rows have run out.
#
# `Maybe.default(head, air_row(cells))` says this too, and it is the shape the rest of
# the file uses, but its default argument is *built before the call*. This walk asks
# once per row of every layer — 20 layers of 32 rows is 640 times — and an air row is
# `cells` wide, so the eager version spent 20,480 cons cells per cold frame building air
# it then discarded, against the few thousand it spent reading blocks. This is the same
# trap as the walk's `Bool.and` hit test: a guard around a call is not a guard around
# its arguments.
def head_row(cells: U32, rows: List<&2, List<&2, U32>>) -> List<&2, U32>:
  match rows:
    case Nil{}:
      air_row(cells)
    case head <> rest:
      head

# Walk the 16 z-rows of one layer. The three carried layer cursors give the
# below/this/above rows at the same z, and each step advances all of them. The
# walk runs `rows_deep` z-rows and each of those runs `cells` x-steps, which is what
# lets one region of chunks be walked with the same code that walks a single chunk.
def z_walk(remaining: Nat, +cells: U32, +below: List<&2, List<&2, U32>>,
  +here: List<&2, List<&2, U32>>, +above: List<&2, List<&2, U32>>,
  +prev_row: List<&2, U32>, +z: U32, +y: U32, +acc: List<&2, Face>) -> List<&2, Face>:
  match remaining:
    case 0n:
      acc
    case 1n+r:
      match below here above:
        case Nil{} _ _:
          acc
        case _ Nil{} _:
          acc
        case _ _ Nil{}:
          acc
        case b <> bt h <> ht a <> at:
          +zprow = head_row(cells, ht)
          +x_walked = x_walk(U32.to_nat(cells), prev_row, h, zprow, b, a, 0, 0, y, z, acc)
          z_walk(r, cells, bt, ht, at, h, (z + 1 : U32), y, x_walked)

# The head layer of a layer stack, or all air when the stack is exhausted. This
# is what makes the y=0 and y=19 boundaries read as air without a bounds check.
def head_layer(stack: List<&2, List<&2, List<&2, U32>>>, cells: U32,
  rows_deep: U32) -> List<&2, List<&2, U32>>:
  match stack:
    case Nil{}:
      air_layer(cells, rows_deep)
    case head <> rest:
      head

# Walk the 20 layers. `l0..l3` are the layers y-1, y, y+1 and y+2, so the whole
# run keeps the rows it needs one and two layers ahead without an index walk.
def layer_walk(remaining: Nat, +cells: U32, +rows_deep: U32,
  +l0: List<&2, List<&2, U32>>, +l1: List<&2, List<&2, U32>>,
  +l2: List<&2, List<&2, U32>>, +l3: List<&2, List<&2, U32>>,
  +rest: List<&2, List<&2, List<&2, U32>>>, +y: U32, +acc: List<&2, Face>) -> List<&2, Face>:
  match remaining:
    case 0n:
      acc
    case 1n+r:
      +walked = z_walk(U32.to_nat(rows_deep), cells, l0, l1, l2, air_row(cells), 0, y, acc)
      layer_walk(r, cells, rows_deep, l1, l2, l3, head_layer(rest, cells, rows_deep),
        List.tail(&2, List<&2, List<&2, U32>>, rest), (y + 1 : U32), walked)

# The 20 real layers in y order, behind one all-air layer so the walk that
# carries the layer below reads air at y=0 rather than the layer itself. Two
# air layers are not needed at the top: `head_layer` turns a missing layer into
# air, and the walk only ever looks one layer past the last real one.
def padded_layers(flat: List<&2, U32>, +cells: U32, +rows_deep: U32) ->
  List<&2, List<&2, List<&2, U32>>>:
  +air : List<&2, List<&2, U32>> = air_layer(cells, rows_deep)
  air <> layers_of(World.max_y(), cells, rows_deep, flat, [])

# `layer_walk` needs the layers y-1, y, y+1 and y+2, plus the tail of the stack
# beginning at y+3. Four heads and one tail over the same shared stack give all
# five cursors without an index walk.
def faces_from_layers(+stack: List<&2, List<&2, List<&2, U32>>>, +cells: U32,
  +rows_deep: U32) -> List<&2, Face>:
  +s1 = List.tail(&2, List<&2, List<&2, U32>>, stack)
  +s2 = List.tail(&2, List<&2, List<&2, U32>>, s1)
  +s3 = List.tail(&2, List<&2, List<&2, U32>>, s2)
  +s4 = List.tail(&2, List<&2, List<&2, U32>>, s3)
  layer_walk(layer_count(), cells, rows_deep, head_layer(stack, cells, rows_deep),
    head_layer(s1, cells, rows_deep), head_layer(s2, cells, rows_deep),
    head_layer(s3, cells, rows_deep), s4, 0, [])

# One chunk is the region of one chunk by one chunk, so the single-chunk entry the
# agreement gate uses stays the same walk over the same numbers.
def faces_from_chunk(chunk: Array<U32>) -> List<&2, Face>:
  faces_from_layers(padded_layers(share_blocks(Array.to_list(~U32, chunk)),
    extent_x(1n), extent_z(1n)), extent_x(1n), extent_z(1n))

# --- a region of chunks -----------------------------------------------------
#
# The renderer's input used to be exactly one `Array<U32>`, which capped the visible
# world at 16x16 cells: from inside a village that is a wooden wall, and the camera at
# the chunk's own edge has nothing in front of it at all. A region is the same walk
# over a wider footprint, so the only new code here is laying several chunks out as one
# array. The chunks arrive in region order, one chunk row at a time and x within it,
# because concatenating their layers in that order is exactly the x-fastest layout
# `rows_of` and the walks already read.
#
# The layout used to reach into each chunk with `List.drop` once per layer, and
# `List.drop` is O(n), so four chunks cost `chunks * layers` full passes over every
# cell before a single face was looked at. That was the whole of the region's extra
# fixed cost: 20.6 ms of plumbing against 6.3 ms of work, barely moving with the output
# resolution. Cutting a chunk consumes its cells instead, so the layout is one pass.

def chunk_blocks(chunk: Array<U32>) -> List<&2, U32>:
  share_blocks(Array.to_list(~U32, chunk))

# `per` cells off the front of a chunk, in order, with what is left. A record rather
# than a bare pair because the two halves have different types and naming them makes
# the call sites read.
def chunk_layer(blocks: List<&2, U32>, y: Nat) -> List<&2, U32>:
  +per_chunk = U32.to_nat(U32.mul(width(), width()))
  List.take(&2, U32, List.drop(&2, U32, blocks, Nat.mul(y, per_chunk)), per_chunk)

# One chunk's layer as its sixteen z-rows.
def layer_rows(remaining: Nat, +layer: List<&2, U32>) -> List<&2, List<&2, U32>>:
  match remaining:
    case 0n:
      []
    case 1n+r:
      List.take(&2, U32, layer, U32.to_nat(width()))
        <> layer_rows(r, List.drop(&2, U32, layer, U32.to_nat(width())))

# Two strips side by side: each z-row of the left with the same z-row of the right after it.
def join_rows(left: List<&2, List<&2, U32>>, right: List<&2, List<&2, U32>>) ->
  List<&2, List<&2, U32>>:
  match left right:
    case l <> lt r <> rt:
      List.append(&2, U32, l, r) <> join_rows(lt, rt)
    case _ _:
      []

def strip.joined(more: Nat, rows: List<&2, List<&2, U32>>, tail: List<&2, List<&2, U32>>) ->
  List<&2, List<&2, U32>>:
  match more:
    case 0n:
      rows
    case 1n+r:
      join_rows(rows, tail)

# One row of chunks at height `y`, as z-rows the whole region wide. A region row is the
# same z-row of every chunk in the strip, west to east — not one chunk's layer after
# another's, which is the right order for a single chunk and a scramble for more.
def strip_rows(+remaining: Nat, chunks: List<&2, List<&2, U32>>, +y: Nat) ->
  List<&2, List<&2, U32>>:
  match remaining chunks:
    case 1n+r blocks <> rest:
      strip.joined(r, layer_rows(U32.to_nat(width()), chunk_layer(blocks, y)),
        strip_rows(r, rest, y))
    case _ _:
      []

# The region's layer at height `y`: its `strips` rows of chunks north to south, each
# `columns` chunks wide.
def region_layer(strips: Nat, +chunks: List<&2, List<&2, U32>>, +y: Nat, +columns: Nat) ->
  List<&2, U32>:
  match strips:
    case 0n:
      []
    case 1n+r:
      List.append(&2, U32, List.concat(&2, U32, strip_rows(columns, chunks, y)),
        region_layer(r, List.drop(&2, List<&2, U32>, chunks, columns), y, columns))

def region_layers(remaining: Nat, +y: Nat, +chunks: List<&2, List<&2, U32>>,
  +columns: Nat, +rows: Nat) -> List<&2, List<&2, U32>>:
  match remaining:
    case 0n:
      []
    case 1n+r:
      region_layer(rows, chunks, y, columns)
        <> region_layers(r, Nat.add(y, 1n), chunks, columns, rows)

def region_flat(chunks: List<&2, List<&2, U32>>, +columns: Nat, +rows: Nat) -> List<&2, U32>:
  List.concat(&2, U32, region_layers(layer_count(), 0n, chunks, columns, rows))

def faces_from_chunks(+chunks: List<&2, List<&2, U32>>, +columns: Nat, +rows: Nat) ->
  List<&2, Face>:
  faces_from_layers(padded_layers(region_flat(chunks, columns, rows), extent_x(columns),
    extent_z(rows)), extent_x(columns), extent_z(rows))

# A count kept on the way down, so a region's tens of thousands of faces are a loop and not
# a call for each.
def face_total.go(faces: List<&2, Face>, +count: U32) -> U32:
  match faces:
    case Nil{}:
      count
    case face <> rest:
      face_total.go(rest, U32.add(count, 1))

def face_total(faces: List<&2, Face>) -> U32:
  face_total.go(faces, 0)

# The side labels present at one cell, as a bitmask over 0..5, and the count.
type At is Data:
  At{mask: U32, total: U32}

def face_bit(dir: Nat) -> U32:
  U32.shln(1, dir)

def face_at_step(faces: List<&2, Face>, +x: U32, +y: U32, +z: U32, +mask: U32,
  +total: U32) -> At:
  match faces:
    case Nil{}:
      At{mask, total}
    case Face{fx, fy, fz, dir, block} <> rest:
      +here = Bool.and(Bool.and(U32.is_eq(fx, x), U32.is_eq(fy, y)), U32.is_eq(fz, z))
      face_at_step(rest, x, y, z,
        Bool.pick(U32, here, U32.or(mask, face_bit(dir)), mask),
        Bool.pick(U32, here, (total + 1 : U32), total))

def face_at(faces: List<&2, Face>, +x: U32, +y: U32, +z: U32) -> At:
  face_at_step(faces, x, y, z, 0, 0)

# ---------------------------------------------------------------------------
# 2. Project each face to screen space and bucket it by screen tile.
# ---------------------------------------------------------------------------

# The camera basis pieces the projection needs, taken apart once per frame so
# the per-face work never re-destructures the shared camera.
def cam_eye(+camera: Voxel.Camera) -> Voxel.Vec:
  Voxel.Camera.eye(camera)

def cam_right(+camera: Voxel.Camera) -> Voxel.Vec:
  Voxel.Camera{eye, forward, right, up} = camera
  right

def cam_up(+camera: Voxel.Camera) -> Voxel.Vec:
  Voxel.Camera{eye, forward, right, up} = camera
  up

def cam_forward(+camera: Voxel.Camera) -> Voxel.Vec:
  Voxel.Camera{eye, forward, right, up} = camera
  forward

def dot3(+a: Voxel.Vec, +b: Voxel.Vec) -> F32:
  Voxel.Vec{ax, ay, az} = a
  Voxel.Vec{bx, by, bz} = b
  (ax * bx + ay * by + az * bz : F32)

def vx(+v: Voxel.Vec) -> F32:
  Voxel.Vec{x, y, z} = v
  x

def vy(+v: Voxel.Vec) -> F32:
  Voxel.Vec{x, y, z} = v
  y

def vz(+v: Voxel.Vec) -> F32:
  Voxel.Vec{x, y, z} = v
  z

# Project a world point to a pixel position and a view-space depth, using the
# same basis and the same `half`/`focal` pair the ray renderer uses, so the two
# agree on the framing.
def project(+eye: Voxel.Vec, +right: Voxel.Vec, +up: Voxel.Vec,
  +forward: Voxel.Vec, +px: F32, +py: F32, +pz: F32, +half: F32, +focal: F32) -> Q:
  +dx = (px - vx(eye) : F32)
  +dy = (py - vy(eye) : F32)
  +pz2 = (pz - vz(eye) : F32)
  +depth = dot3(forward, Voxel.Vec{dx, dy, pz2})
  +safe_depth = F32.max(depth, 0.0001)
  +sx = (half - 0.5 + focal * dot3(right, Voxel.Vec{dx, dy, pz2}) / safe_depth : F32)
  +sy = (half - 0.5 - focal * dot3(up, Voxel.Vec{dx, dy, pz2}) / safe_depth : F32)
  Q{sx, sy, depth}

# The running screen bounds over a face's four projected corners, plus a
# diagnostic mean depth and whether any/all corners are in front of the near plane.
type Span is Data:
  Span{sx0: F32, sy0: F32, sx1: F32, sy1: F32, sum: F32, alive: Bool, front: Bool}

def q_sx(q: Q) -> F32:
  match q:
    case Q{sx, sy, depth}:
      sx

def q_sy(q: Q) -> F32:
  match q:
    case Q{sx, sy, depth}:
      sy

def q_depth(q: Q) -> F32:
  match q:
    case Q{sx, sy, depth}:
      depth

# Fold one corner into the running span. Every value is a plain F32 or Bool, so
# each is read once and returned once, which is what the linear checker requires.
def widen(+sx0: F32, +sy0: F32, +sx1: F32, +sy1: F32, +sum: F32, +alive: Bool,
  +front: Bool, +x: F32, +y: F32, +depth: F32) -> Span:
  Span{F32.min(sx0, x), F32.min(sy0, y), F32.max(sx1, x), F32.max(sy1, y),
    F32.add(sum, depth), Bool.and(alive, F32.is_gt(depth, 0.0001)),
    Bool.or(front, F32.is_gt(depth, 0.0001))}

def span_sx0(s: Span) -> F32:
  match s:
    case Span{sx0, sy0, sx1, sy1, near, alive, front}:
      sx0

def span_sy0(s: Span) -> F32:
  match s:
    case Span{sx0, sy0, sx1, sy1, near, alive, front}:
      sy0

def span_sx1(s: Span) -> F32:
  match s:
    case Span{sx0, sy0, sx1, sy1, near, alive, front}:
      sx1

def span_sy1(s: Span) -> F32:
  match s:
    case Span{sx0, sy0, sx1, sy1, near, alive, front}:
      sy1

# The diagnostic mean of the four corner depths, clamped away from zero.
def span_near(s: Span) -> F32:
  match s:
    case Span{sx0, sy0, sx1, sy1, sum, live, front}:
      F32.max(F32.mul(sum, 0.25), 0.0001)

def span_sum(s: Span) -> F32:
  match s:
    case Span{sx0, sy0, sx1, sy1, sum, live, front}:
      sum

def span_alive(s: Span) -> Bool:
  match s:
    case Span{sx0, sy0, sx1, sy1, sum, live, front}:
      live

def span_front(s: Span) -> Bool:
  match s:
    case Span{sx0, sy0, sx1, sy1, sum, live, front}:
      front

# Seed the span from the first corner. The record is read exactly once, so its
# three fields are destructured together.
def span_from(+x: F32, +y: F32, +depth: F32) -> Span:
  +front = F32.is_gt(depth, 0.0001)
  Span{x, y, x, y, depth, front, front}

def seed(q: Q) -> Span:
  match q:
    case Q{x, y, depth}:
      span_from(x, y, depth)

# Fold one more corner in, reading the span through accessors so each field is
# consumed once. The corner's three values are unpacked by `corner` first,
# because a record can only be read once.
def corner(q: Q) -> Q:
  match q:
    case Q{x, y, depth}:
      Q{x, y, depth}

def span_copy(s: Span) -> Span:
  match s:
    case Span{x0, y0, x1, y1, sum, live, front}:
      Span{x0, y0, x1, y1, sum, live, front}

def widen_row(s: Span, q: Q) -> Span:
  +sp = span_copy(s)
  +c = corner(q)
  +x = q_sx(c)
  +y = q_sy(c)
  +depth = q_depth(c)
  widen(span_sx0(sp), span_sy0(sp), span_sx1(sp), span_sy1(sp), span_sum(sp),
    span_alive(sp), span_front(sp), x, y, depth)

def screen_coord(+value: F32) -> U32:
  +nonnegative = F32.max(value, 0.0)
  +bounded = F32.min(nonnegative, 65535.0)
  F32.to_u32(F32.floor(bounded))

# Reduce four projected corners to the inclusive pixel box they can cover. A
# face crossing the near plane gets a conservative full-frame box so no visible
# portion is lost; per-pixel plane and unit-square tests reject false candidates.
def corners(a: Q, b: Q, c: Q, d: Q, +block: U32, dir: Nat, origin: P) -> Screen:
  +s0 = seed(a)
  +s1 = widen_row(s0, b)
  +s2 = widen_row(s1, c)
  +s3 = widen_row(s2, d)
  +all_front = span_alive(s3)
  +any_front = span_front(s3)
  +raw_x0 = screen_coord(span_sx0(s3))
  +raw_y0 = screen_coord(span_sy0(s3))
  +raw_x1 = screen_coord(span_sx1(s3))
  +raw_y1 = screen_coord(span_sy1(s3))
  +x0 = Bool.pick(U32, all_front, raw_x0, 0)
  +y0 = Bool.pick(U32, all_front, raw_y0, 0)
  +x1 = Bool.pick(U32, all_front, raw_x1, 65535)
  +y1 = Bool.pick(U32, all_front, raw_y1, 65535)
  Screen{pack(x0, y0), pack(x1, y1), F32.max(span_near(s3), 0.0001), block, dir,
    any_front, origin}

# Project the four corners of the unit square whose plane coordinate is fixed and
# whose other two axes run from the cell origin to origin+1. `axis` is the
# constant axis; the other two are the in-plane ones in cyclic order.
def square(dir: Nat, +fx: F32, +fy: F32, +fz: F32, +plane: F32, axis: Nat,
  +eye: Voxel.Vec, +right: Voxel.Vec, +up: Voxel.Vec, +forward: Voxel.Vec,
  +half: F32, +focal: F32, +block: U32) -> Screen:
  match axis:
    case 0n:
      corners(project(eye, right, up, forward, plane, fy, fz, half, focal),
        project(eye, right, up, forward, plane, (fy + 1.0 : F32), fz, half, focal),
        project(eye, right, up, forward, plane, fy, (fz + 1.0 : F32), half, focal),
        project(eye, right, up, forward, plane, (fy + 1.0 : F32), (fz + 1.0 : F32), half, focal),
        block, dir, P{fx, fy, fz})
    case 1n:
      corners(project(eye, right, up, forward, fx, plane, fz, half, focal),
        project(eye, right, up, forward, (fx + 1.0 : F32), plane, fz, half, focal),
        project(eye, right, up, forward, fx, plane, (fz + 1.0 : F32), half, focal),
        project(eye, right, up, forward, (fx + 1.0 : F32), plane, (fz + 1.0 : F32), half, focal),
        block, dir, P{fx, fy, fz})
    case _:
      corners(project(eye, right, up, forward, fx, fy, plane, half, focal),
        project(eye, right, up, forward, (fx + 1.0 : F32), fy, plane, half, focal),
        project(eye, right, up, forward, fx, (fy + 1.0 : F32), plane, half, focal),
        project(eye, right, up, forward, (fx + 1.0 : F32), (fy + 1.0 : F32), plane, half, focal),
        block, dir, P{fx, fy, fz})

# The screen box a face covers. dir 0..5 are +x, +y, +z, -x, -y, -z, so the plane
# coordinate is origin+1 for the first three and origin for the last three, and
# the in-plane axes are the other two.
def box_of(dir: Nat, +block: U32, +fx: F32, +fy: F32, +fz: F32, +eye: Voxel.Vec,
  +right: Voxel.Vec, +up: Voxel.Vec, +forward: Voxel.Vec, +half: F32, +focal: F32) -> Screen:
  match dir:
    case 0n:
      square(dir, fx, fy, fz, F32.add(fx, 1.0), 0n, eye, right, up, forward, half, focal, block)
    case 1n:
      square(dir, fx, fy, fz, F32.add(fy, 1.0), 1n, eye, right, up, forward, half, focal, block)
    case 2n:
      square(dir, fx, fy, fz, F32.add(fz, 1.0), 2n, eye, right, up, forward, half, focal, block)
    case 3n:
      square(dir, fx, fy, fz, fx, 0n, eye, right, up, forward, half, focal, block)
    case 4n:
      square(dir, fx, fy, fz, fy, 1n, eye, right, up, forward, half, focal, block)
    case _:
      square(dir, fx, fy, fz, fz, 2n, eye, right, up, forward, half, focal, block)

# ---------------------------------------------------------------------------
# 2a. How much geometry a frame actually holds.
#
# `box_of` reduces a face to the conservative box the walk tests, and the sum of those
# boxes is what the walk is charged. A renderer that painted each face once instead
# would touch each face's own quad, and the two differ by the box's waste over the quad:
# a wall seen edge-on has a thin quad inside a wide box, and that difference is the whole
# argument for painting rather than walking per pixel.
#
# So the quads are measured at the same camera as the boxes rather than assumed from
# them. `Square` holds the four projected corners in cycle order, which is the order the
# shoelace needs; `square` above builds them in a different order because a running span
# does not care, and rebuilding that walk to reorder it would put a hot path at risk for
# a diagnostic.
# ---------------------------------------------------------------------------

type Square is Data:
  Square{a: Q, b: Q, c: Q, d: Q}

# The plane coordinate of a face's square, and the axis it is constant in. These are
# `box_of`'s own two decisions, written out again rather than reached through it: the
# diagnostic must not sit in the hot path it measures, and `quad_area_below` holds the
# two forms together.
def plane_of(dir: Nat, +fx: F32, +fy: F32, +fz: F32) -> F32:
  match dir:
    case 0n:
      F32.add(fx, 1.0)
    case 1n:
      F32.add(fy, 1.0)
    case 2n:
      F32.add(fz, 1.0)
    case 3n:
      fx
    case 4n:
      fy
    case _:
      fz

def axis_of(dir: Nat) -> Nat:
  match dir:
    case 0n:
      0n
    case 1n:
      1n
    case 2n:
      2n
    case 3n:
      0n
    case 4n:
      1n
    case _:
      2n

def square_axis(axis: Nat, +fx: F32, +fy: F32, +fz: F32, +plane: F32,
  +eye: Voxel.Vec, +right: Voxel.Vec, +up: Voxel.Vec, +forward: Voxel.Vec,
  +half: F32, +focal: F32) -> Square:
  match axis:
    case 0n:
      Square{project(eye, right, up, forward, plane, fy, fz, half, focal),
        project(eye, right, up, forward, plane, (fy + 1.0 : F32), fz, half, focal),
        project(eye, right, up, forward, plane, (fy + 1.0 : F32), (fz + 1.0 : F32), half, focal),
        project(eye, right, up, forward, plane, fy, (fz + 1.0 : F32), half, focal)}
    case 1n:
      Square{project(eye, right, up, forward, fx, plane, fz, half, focal),
        project(eye, right, up, forward, (fx + 1.0 : F32), plane, fz, half, focal),
        project(eye, right, up, forward, (fx + 1.0 : F32), plane, (fz + 1.0 : F32), half, focal),
        project(eye, right, up, forward, fx, plane, (fz + 1.0 : F32), half, focal)}
    case _:
      Square{project(eye, right, up, forward, fx, fy, plane, half, focal),
        project(eye, right, up, forward, (fx + 1.0 : F32), fy, plane, half, focal),
        project(eye, right, up, forward, (fx + 1.0 : F32), (fy + 1.0 : F32), plane, half, focal),
        project(eye, right, up, forward, fx, (fy + 1.0 : F32), plane, half, focal)}

def square_plane(axis: Nat, +fx: F32, +fy: F32, +fz: F32, +plane: F32, +eye: Voxel.Vec,
  +right: Voxel.Vec, +up: Voxel.Vec, +forward: Voxel.Vec, +half: F32, +focal: F32) -> Square:
  square_axis(axis, fx, fy, fz, plane, eye, right, up, forward, half, focal)

# `dir` twice would be two reads of one affine parameter, so the axis is resolved first
# and the plane second.
def square_of(+dir: Nat, +fx: F32, +fy: F32, +fz: F32, +eye: Voxel.Vec, +right: Voxel.Vec,
  +up: Voxel.Vec, +forward: Voxel.Vec, +half: F32, +focal: F32) -> Square:
  square_plane(axis_of(dir), fx, fy, fz, plane_of(dir, fx, fy, fz), eye, right, up, forward,
    half, focal)

# The shoelace of one edge pair, `px * qy - qx * py`.
def edge(px: F32, py: F32, qx: F32, qy: F32) -> F32:
  F32.sub(F32.mul(px, qy), F32.mul(qx, py))

def clamp(+value: F32, +last: F32) -> F32:
  F32.min(F32.max(value, 0.0), last)

# Twice the area of a quad, by the shoelace over its four edges in cycle order, every
# corner first clamped into the frame.
#
# The clamp is not decoration and is not optional. A quad whose corner is behind the eye
# projects to a coordinate of tens of thousands of pixels, and one such corner makes the
# shoelace term enormous: the first run of this reported 4,193,030,645 for a 16,384-pixel
# frame, which is a wrap of the sum rather than a measurement. The faces that cross the
# eye plane are counted separately and excluded, and the rest are clamped, so the sum is
# a quantity that can be compared with the frame it is drawn into.
def shoelace2(s: Square, +last: F32) -> F32:
  Square{a, b, c, d} = s
  Q{x1, y1, _} = a
  Q{x2, y2, _} = b
  Q{x3, y3, _} = c
  Q{x4, y4, _} = d
  +ax = clamp(x1, last)
  +ay = clamp(y1, last)
  +bx = clamp(x2, last)
  +by = clamp(y2, last)
  +cx = clamp(x3, last)
  +cy = clamp(y3, last)
  +dx = clamp(x4, last)
  +dy = clamp(y4, last)
  +e1 = edge(ax, ay, bx, by)
  +e2 = edge(bx, by, cx, cy)
  +e3 = edge(cx, cy, dx, dy)
  +e4 = edge(dx, dy, ax, ay)
  F32.add(F32.add(e1, e2), F32.add(e3, e4))

# The quad's area inside the frame. Clamping corners is not polygon clipping: a quad
# that leaves the frame counts its clamped hull, so this overcounts the off-frame part
# rather than undercounting the on-frame part. It is the same convention `clip_area` uses
# for the boxes, and the two numbers are meant to be read against each other.
def quad_area(s: Square, +last: F32) -> U32:
  +sum = shoelace2(s, last)
  F32.to_u32(F32.mul(0.5, F32.abs(sum)))

def q_depth_first(s: Square) -> F32:
  Square{a, _, _, _} = s
  q_depth(a)

# One face's contribution: the pixels its own quad covers at this camera, and whether any
# of its corners fell behind the eye, which is the case the shoelace cannot describe.
type Counted is Data:
  Counted{pixels: U32, behind: Bool}

def quad_area.first(dir: Nat, +block: U32, +fx: F32, +fy: F32, +fz: F32, +eye: Voxel.Vec,
  +right: Voxel.Vec, +up: Voxel.Vec, +forward: Voxel.Vec, +half: F32, +focal: F32,
  +last: F32) -> Counted:
  +square = square_of(dir, fx, fy, fz, eye, right, up, forward, half, focal)
  +behind = F32.is_le(q_depth_first(square), 0.0001)
  Counted{Bool.pick(U32, behind, 0, quad_area(square, last)), behind}

def counted_pixels(c: Counted) -> U32:
  match c:
    case Counted{pixels, behind}:
      pixels

def counted_behind(c: Counted) -> Bool:
  match c:
    case Counted{pixels, behind}:
      behind

def counted.plus(one: Counted, +total: Counted) -> Counted:
  Counted{pixels, behind} = one
  Counted{sum, crossed} = total
  Counted{U32.add(pixels, sum), Bool.or(behind, crossed)}

def quad_area.go(faces: List<&2, Face>, +eye: Voxel.Vec, +right: Voxel.Vec, +up: Voxel.Vec,
  +forward: Voxel.Vec, +half: F32, +focal: F32, +last: F32, +total: Counted) -> Counted:
  match faces:
    case Nil{}:
      total
    case Face{fx, fy, fz, dir, block} <> rest:
      quad_area.go(rest, eye, right, up, forward, half, focal, last, counted.plus(
        quad_area.first(dir, block, U32.to_f32(fx), U32.to_f32(fy), U32.to_f32(fz), eye,
          right, up, forward, half, focal, last), total))

def quad_area_of(faces: List<&2, Face>, +camera: Voxel.Camera, +half: F32, +focal: F32,
  +size: U32) -> Counted:
  quad_area.go(faces, cam_eye(camera), cam_right(camera), cam_up(camera),
    cam_forward(camera), half, focal, F32.from_nat(U32.to_nat(U32.sub(size, (1 : U32)))),
    Counted{(0 : U32), False{}})

# ---------------------------------------------------------------------------
# 3. The screen tile grid, and the per-pixel fold over one tile's candidates.
# ---------------------------------------------------------------------------

# Default production tile edge; the benchmark passes alternatives explicitly.
def tile_size() -> U32:
  (8 : U32)

def tiles_across(size: U32, +edge: U32) -> U32:
  U32.div(size, edge)

# The bucket a pixel reads: the tile's list of projected faces. Rows and buckets
# are shared, so a pixel only walks the faces its own tile collected.
def empty_buckets(count: U32) -> List<&2, List<&2, Screen>>:
  List.replicate(List<&2, Screen>, U32.to_nat(count), [])

def grid_rows_of(count: Nat, +blank: List<&2, List<&2, Screen>>) ->
  List<&2, List<&2, List<&2, Screen>>>:
  match count:
    case 0n:
      []
    case 1n+p:
      +rest = grid_rows_of(p, blank)
      blank <> rest

# The empty tile grid: every row shares one empty bucket spine. Build the outer
# row spine directly instead of repeatedly appending and copying its prefix.
def empty_grid(+across: U32) -> List<&2, List<&2, List<&2, Screen>>>:
  # `+across` is affine: a U32 is Copy, so it is readable many times.
  +blank : List<&2, List<&2, Screen>> = empty_buckets(across)
  grid_rows_of(U32.to_nat(across), blank)

# Screen-face accessors. A `Screen` record can be read exactly once, so every
# field the caller needs is taken by its own accessor. The four box corners are
# unpacked from the two words the walk compares; nothing in the per-pixel walk uses
# these, which is the point of packing them.
def s_x0(s: Screen) -> U32:
  match s:
    case Screen{low, high, depth, block, dir, alive, origin}:
      U32.and(low, 65535)

def s_y0(s: Screen) -> U32:
  match s:
    case Screen{low, high, depth, block, dir, alive, origin}:
      U32.shrn(low, 16n)

def s_x1(s: Screen) -> U32:
  match s:
    case Screen{low, high, depth, block, dir, alive, origin}:
      U32.and(high, 65535)

def s_y1(s: Screen) -> U32:
  match s:
    case Screen{low, high, depth, block, dir, alive, origin}:
      U32.shrn(high, 16n)

def s_depth(s: Screen) -> F32:
  match s:
    case Screen{low, high, depth, block, dir, alive, origin}:
      depth

def s_block(s: Screen) -> U32:
  match s:
    case Screen{low, high, depth, block, dir, alive, origin}:
      block

def s_dir(s: Screen) -> Nat:
  match s:
    case Screen{low, high, depth, block, dir, alive, origin}:
      dir

def s_alive(s: Screen) -> Bool:
  match s:
    case Screen{low, high, depth, block, dir, alive, origin}:
      alive

def s_origin(s: Screen) -> P:
  match s:
    case Screen{low, high, depth, block, dir, alive, origin}:
      origin

def position_key(origin: P) -> U32:
  match origin:
    case P{x, y, z}:
      U32.xor(U32.xor(F32.to_u32(x), U32.mul(F32.to_u32(y), 31)),
        U32.mul(F32.to_u32(z), 997))

# A digest of every projected face field, so a benchmark that folds the bucket
# grid observes the actual screen boxes, face plane and material in every bucket.
def s_depth_key(s: Screen) -> U32:
  match s:
    case Screen{+low, +high, depth, block, dir, alive, origin}:
      +x0 = U32.and(low, 65535)
      +y0 = U32.shrn(low, 16n)
      +x1 = U32.and(high, 65535)
      +y1 = U32.shrn(high, 16n)
      +xy0 = U32.xor(U32.mul(x0, 73856093), U32.mul(y0, 19349663))
      +xy1 = U32.xor(U32.mul(x1, 83492791), U32.mul(y1, 2971215073))
      +z = F32.to_u32(F32.mul(depth, 1024.0))
      +material = U32.xor(U32.mul(block, 2654435761), U32.from_nat(dir))
      +live = Bool.pick(U32, alive, 1, 0)
      +position = position_key(origin)
      U32.xor(U32.xor(xy0, xy1), U32.xor(z, U32.xor(material, U32.xor(live, position))))

# Clamp a face's box to the frame and mark it not alive when the clamped box is
# empty or the face crossed the near plane. The depth, block and label pass
# through untouched; only the box and the liveness flag change. The fields are
# parameters rather than a record so the liveness match can scrutinize one.
def clip(x0: U32, y0: U32, x1: U32, y1: U32, depth: F32, block: U32, dir: Nat,
  alive: Bool, origin: P, +size: U32) -> Screen:
  +cx0 = U32.min(x0, U32.sub(size, 1))
  +cy0 = U32.min(y0, U32.sub(size, 1))
  +cx1 = U32.min(x1, U32.sub(size, 1))
  +cy1 = U32.min(y1, U32.sub(size, 1))
  +ok = Bool.and(alive, Bool.and(U32.is_le(cx0, cx1), U32.is_le(cy0, cy1)))
  Screen{pack(cx0, cy0), pack(cx1, cy1), depth, block, dir, ok, origin}

def clip_screen(+s: Screen, +size: U32) -> Screen:
  clip(s_x0(s), s_y0(s), s_x1(s), s_y1(s), s_depth(s), s_block(s), s_dir(s),
    s_alive(s), s_origin(s), size)

# Add one projected face to the bucket at (tx, ty). Both spines are rebuilt, so
# the grid is threaded through the insertion rather than mutated in place.
def add_at_bucket(+row: List<&2, List<&2, Screen>>, +tx: U32, +screen: Screen) ->
  List<&2, List<&2, Screen>>:
  +bucket = Maybe.default(&2, List<&2, Screen>, List.get(&2, List<&2, Screen>, row, U32.to_nat(tx)), [])
  List.set(&2, List<&2, Screen>, row, U32.to_nat(tx), screen <> bucket)

def set_existing_row(found: Maybe<&2, List<&2, List<&2, Screen>>>,
  +rows: List<&2, List<&2, List<&2, Screen>>>, +ty: U32, +tx: U32,
  +screen: Screen) -> List<&2, List<&2, List<&2, Screen>>>:
  match found:
    case None{}:
      rows
    case Some{row}:
      List.set(&2, List<&2, List<&2, Screen>>, rows, U32.to_nat(ty),
        add_at_bucket(row, tx, screen))

def add_at_row(+rows: List<&2, List<&2, List<&2, Screen>>>, +ty: U32, +tx: U32,
  +screen: Screen) -> List<&2, List<&2, List<&2, Screen>>>:
  +found = List.get(&2, List<&2, List<&2, Screen>>, rows, U32.to_nat(ty))
  set_existing_row(found, rows, ty, tx, screen)

# Fill one tile row: every tile from tx0 to tx1 receives the same face.
def tiles_in_row(columns: Nat, +tx: U32, +ty: U32,
  +rows: List<&2, List<&2, List<&2, Screen>>>, +screen: Screen) ->
  List<&2, List<&2, List<&2, Screen>>>:
  match columns:
    case 0n:
      rows
    case 1n+p:
      tiles_in_row(p, (tx + 1 : U32), ty,
        add_at_row(rows, ty, tx, screen), screen)

# Walk the tile rows from ty0 to ty1, filling each with the same face.
def rows_of_tiles(rows_left: Nat, +ty: U32, +tx0: U32, +span_x: Nat,
  +rows: List<&2, List<&2, List<&2, Screen>>>, +screen: Screen) ->
  List<&2, List<&2, List<&2, Screen>>>:
  match rows_left:
    case 0n:
      rows
    case 1n+p:
      rows_of_tiles(p, (ty + 1 : U32), tx0, span_x,
        tiles_in_row(span_x, tx0, ty, rows, screen), screen)

# Put one face into every tile its box covers, or keep the grid unchanged when
# the face is not alive. The box is passed unpacked so the match can scrutinize
# the liveness flag, which the language only allows on a parameter.
def place(alive: Bool, x0: U32, y0: U32, x1: U32, y1: U32, s: Screen, +across: U32,
  +edge: U32,
  +rows: List<&2, List<&2, List<&2, Screen>>>) -> List<&2, List<&2, List<&2, Screen>>>:
  match alive:
    case False{}:
      rows
    case True{}:
      +tx0 = U32.div(x0, edge)
      +ty0 = U32.div(y0, edge)
      +tx1 = U32.min(U32.div(x1, edge), U32.sub(across, 1))
      +ty1 = U32.min(U32.div(y1, edge), U32.sub(across, 1))
      +span_x = Nat.sub(U32.to_nat(U32.add(tx1, 1)), U32.to_nat(tx0))
      +span_y = Nat.sub(U32.to_nat(U32.add(ty1, 1)), U32.to_nat(ty0))
      rows_of_tiles(span_y, ty0, tx0, span_x, rows, s)

# The whole face list, projected, clipped and bucketed. `size` is the frame edge
# in pixels, so the tile grid is size/edge tiles across.
def bucket_all(faces: List<&2, Face>, +eye: Voxel.Vec, +right: Voxel.Vec, +up: Voxel.Vec,
  +forward: Voxel.Vec, +half: F32, +focal: F32, +size: U32, +across: U32, +edge: U32,
  +rows: List<&2, List<&2, List<&2, Screen>>>) -> List<&2, List<&2, List<&2, Screen>>>:
  match faces:
    case Nil{}:
      rows
    case Face{fx, fy, fz, dir, block} <> rest:
      +boxed = box_of(dir, block, U32.to_f32(fx), U32.to_f32(fy), U32.to_f32(fz),
        eye, right, up, forward, half, focal)
      +screen = clip_screen(boxed, size)
      bucket_all(rest, eye, right, up, forward, half, focal, size, across, edge,
        place(s_alive(screen), s_x0(screen), s_y0(screen), s_x1(screen), s_y1(screen),
          screen, across, edge, rows))

# Which builder fills the grid, by how many tiles are across it.
#
# The two builders are equivalent — `row_major_matches_scatter` holds that on every
# size the test covers — and they fail in opposite directions. Scatter pays
# `2 * across * placements` list steps, because each placement costs a `List.get` and a
# `List.set` and both walk the row it is indexing. Row-major pays no index at all: it
# fills one tile row at a time and conses, at the price of re-deciding every face's
# placement once per row, which is about eight operations a visit.
#
# So scatter wins when the row is short, and row-major wins when it is long enough that
# eight operations a visit is cheaper than two walks of `across`. Measured at the
# client's own region and camera, grid build inclusive of projection:
#
#   tiles across   4 (64x64)    8 (128x128)
#   scatter            2.90         5.40
#   row-major          3.00         5.10
#
# The crossover is between them, so eight is where the choice is made.
def grid_is_wide(across: U32) -> Bool:
  U32.is_ge(across, 8)

# Project once into a forward-ordered screen list. The row-major builder below
# scans this list once per tile and conses matches into that tile's bucket.
def project_screens(faces: List<&2, Face>, +eye: Voxel.Vec, +right: Voxel.Vec,
  +up: Voxel.Vec, +forward: Voxel.Vec, +half: F32, +focal: F32, +size: U32) ->
  List<&2, Screen>:
  match faces:
    case Nil{}:
      []
    case Face{fx, fy, fz, dir, block} <> rest:
      +boxed = box_of(dir, block, U32.to_f32(fx), U32.to_f32(fy), U32.to_f32(fz),
        eye, right, up, forward, half, focal)
      +screen = clip_screen(boxed, size)
      +tail = project_screens(rest, eye, right, up, forward, half, focal, size)
      screen <> tail

def tile_overlaps(alive: Bool, x0: U32, y0: U32, x1: U32, y1: U32,
  +tx: U32, +ty: U32, +edge: U32) -> Bool:
  +left = U32.mul(tx, edge)
  +top = U32.mul(ty, edge)
  +right = U32.sub(U32.mul((tx + 1 : U32), edge), 1)
  +bottom = U32.sub(U32.mul((ty + 1 : U32), edge), 1)
  Bool.and(alive, Bool.and(Bool.and(U32.is_le(x0, right), U32.is_le(left, x1)),
    Bool.and(U32.is_le(y0, bottom), U32.is_le(top, y1))))

def screen_hits_tile(+screen: Screen, tx: U32, ty: U32, +edge: U32) -> Bool:
  tile_overlaps(s_alive(screen), s_x0(screen), s_y0(screen), s_x1(screen), s_y1(screen),
    tx, ty, edge)

def maybe_screen(hit: Bool, screen: Screen) -> Maybe<&2, Screen>:
  Bool.pick(Maybe<&2, Screen>, hit, Some{screen}, None{})

def put_screen(maybe: Maybe<&2, Screen>, acc: List<&2, Screen>) -> List<&2, Screen>:
  match maybe:
    case None{}:
      acc
    case Some{screen}:
      screen <> acc

def bucket_screens(screens: List<&2, Screen>, +tx: U32, +ty: U32,
  +edge: U32, +bucket: List<&2, Screen>) -> List<&2, Screen>:
  match screens:
    case Nil{}:
      bucket
    case +screen <> rest:
      +hit = screen_hits_tile(screen, tx, ty, edge)
      +candidate = maybe_screen(hit, screen)
      +next = put_screen(candidate, bucket)
      bucket_screens(rest, tx, ty, edge, next)

def row_major_buckets(columns: Nat, +tx: U32, +ty: U32,
  +edge: U32, +screens: List<&2, Screen>) -> List<&2, List<&2, Screen>>:
  match columns:
    case 0n:
      []
    case 1n+p:
      +tail = row_major_buckets(p, (tx + 1 : U32), ty, edge, screens)
      +bucket = bucket_screens(screens, tx, ty, edge, [])
      bucket <> tail

def row_major_rows(count: Nat, +ty: U32, +across: U32,
  +edge: U32, +screens: List<&2, Screen>) -> List<&2, List<&2, List<&2, Screen>>>:
  match count:
    case 0n:
      []
    case 1n+p:
      +tail = row_major_rows(p, (ty + 1 : U32), across, edge, screens)
      +row = row_major_buckets(U32.to_nat(across), 0, ty, edge, screens)
      row <> tail

def bucket_faces.for(faces: List<&2, Face>, wide: Bool, +eye: Voxel.Vec,
  +right: Voxel.Vec, +up: Voxel.Vec, +forward: Voxel.Vec, +half: F32, +focal: F32,
  +size: U32, +across: U32, +edge: U32) -> Tiles:
  match wide:
    case False{}:
      +empty : List<&2, List<&2, List<&2, Screen>>> = empty_grid(across)
      Tiles{bucket_all(faces, eye, right, up, forward, half, focal, size, across, edge,
        empty), size, edge, Voxel.Camera{eye, forward, right, up}, half, focal}
    case True{}:
      +screens = project_screens(faces, eye, right, up, forward, half, focal, size)
      Tiles{row_major_rows(U32.to_nat(across), 0, across, edge, screens), size, edge,
        Voxel.Camera{eye, forward, right, up}, half, focal}

def bucket_faces_with_tile_size(faces: List<&2, Face>, +eye: Voxel.Vec, +right: Voxel.Vec,
  +up: Voxel.Vec, +forward: Voxel.Vec, +half: F32, +focal: F32, +size: U32,
  +edge: U32) -> Tiles:
  +across = tiles_across(size, edge)
  bucket_faces.for(faces, grid_is_wide(across), eye, right, up, forward, half, focal,
    size, across, edge)

def bucket_faces(faces: List<&2, Face>, +eye: Voxel.Vec, +right: Voxel.Vec, +up: Voxel.Vec,
    +forward: Voxel.Vec, +half: F32, +focal: F32, +size: U32) -> Tiles:
  bucket_faces_with_tile_size(faces, eye, right, up, forward, half, focal, size, tile_size())

def bucket_faces_row_major_with_tile_size(faces: List<&2, Face>, +eye: Voxel.Vec,
  +right: Voxel.Vec, +up: Voxel.Vec, +forward: Voxel.Vec, +half: F32, +focal: F32,
  +size: U32, +edge: U32) -> Tiles:
  +across = tiles_across(size, edge)
  +screens = project_screens(faces, eye, right, up, forward, half, focal, size)
  Tiles{row_major_rows(U32.to_nat(across), 0, across, edge, screens), size, edge,
    Voxel.Camera{eye, forward, right, up}, half, focal}

def bucket_faces_row_major(faces: List<&2, Face>, +eye: Voxel.Vec, +right: Voxel.Vec,
  +up: Voxel.Vec, +forward: Voxel.Vec, +half: F32, +focal: F32, +size: U32) -> Tiles:
  bucket_faces_row_major_with_tile_size(faces, eye, right, up, forward, half, focal, size,
    tile_size())

# ---------------------------------------------------------------------------
# 4. Per pixel: walk one tile's candidates and keep the nearest covering face.
# ---------------------------------------------------------------------------

# The bucket list, and the pixel it is being asked about.
def bucket_at(+rows: List<&2, List<&2, List<&2, Screen>>>, +tx: U32, +ty: U32) ->
  List<&2, Screen>:
  +row = Maybe.default(&2, List<&2, List<&2, Screen>>,
    List.get(&2, List<&2, List<&2, Screen>>, rows, U32.to_nat(ty)), [])
  Maybe.default(&2, List<&2, Screen>, List.get(&2, List<&2, Screen>, row, U32.to_nat(tx)), [])

def b_block(b: Best) -> U32:
  match b:
    case Best{block, dir, depth}:
      block

def b_dir(b: Best) -> Nat:
  match b:
    case Best{block, dir, depth}:
      dir

def b_depth(b: Best) -> F32:
  match b:
    case Best{block, dir, depth}:
      depth

def position_x(origin: P) -> F32:
  match origin:
    case P{x, y, z}:
      x

def position_y(origin: P) -> F32:
  match origin:
    case P{x, y, z}:
      y

def position_z(origin: P) -> F32:
  match origin:
    case P{x, y, z}:
      z

# Parameter distance along the normalized pixel ray to this face's world plane.
# A parallel ray has no finite plane hit and is rejected without dividing by zero.
def plane_depth(plane: F32, eye_coordinate: F32, +component: F32) -> F32:
  +crosses = F32.is_gt(F32.abs(component), 0.00001)
  +safe_component = Bool.pick(F32, crosses, component, 1.0)
  +distance = (F32.sub(plane, eye_coordinate) / safe_component : F32)
  Bool.pick(F32, crosses, distance, 1.0e30)

def ray_plane_depth(dir: Nat, origin: P, eye: Voxel.Vec, ray: Voxel.Vec) -> F32:
  match dir:
    case 0n:
      plane_depth(F32.add(position_x(origin), 1.0), vx(eye), vx(ray))
    case 1n:
      plane_depth(F32.add(position_y(origin), 1.0), vy(eye), vy(ray))
    case 2n:
      plane_depth(F32.add(position_z(origin), 1.0), vz(eye), vz(ray))
    case 3n:
      plane_depth(position_x(origin), vx(eye), vx(ray))
    case 4n:
      plane_depth(position_y(origin), vy(eye), vy(ray))
    case _:
      plane_depth(position_z(origin), vz(eye), vz(ray))

def within_unit(+coord: F32, +origin: F32) -> Bool:
  +above = F32.is_ge(coord, F32.sub(origin, 0.00001))
  +below = F32.is_le(coord, F32.add(origin, 1.00001))
  Bool.and(above, below)

# Intersecting the face plane is an exact point-in-projected-quad test: the hit
# belongs to the projected face iff its world point lies in the face's unit square.
#
# Two ways of doing less work here were tried and both lost, and the reason is the same
# and worth writing down.
#
# The hit's coordinate along the face's own normal is the plane coordinate by
# construction, so one of the three comparisons is always true and could be skipped by
# choosing the normal's axis in a `match` first. Measured a wash: 17.90 ms of sequential
# walk against 17.80.
#
# Short-circuiting the three behind `match`es so a candidate that misses on its first
# coordinate does not pay for the other two is a *worse* wash: 54.45 ms of sequential
# walk at 128x128 against 52.50, with the bare iteration unchanged, so the two extra
# dispatches are being paid on every candidate and saving nothing.
#
# The reason is the same in both cases and it is the opposite of the win beside it. The
# walk's *depth* test short-circuits because it usually fails — most candidates are
# farther than the running best, so the guard usually skips the work. The quad test only
# runs for candidates that already passed the box test *and* beat the running best on
# depth, so its operands usually **pass**, and guarding a usually-true operand buys
# nothing and costs a dispatch. **Short-circuiting pays when the guarded operand usually
# fails and costs when it usually holds.** Look at which way the bias runs before
# reaching for it.
def face_contains_hit(origin: P, eye: Voxel.Vec, ray: Voxel.Vec, +distance: F32) -> Bool:
  P{x, y, z} = origin
  Voxel.Vec{ex, ey, ez} = eye
  Voxel.Vec{dx, dy, dz} = ray
  +hit_x = F32.add(ex, F32.mul(dx, distance))
  +hit_y = F32.add(ey, F32.mul(dy, distance))
  +hit_z = F32.add(ez, F32.mul(dz, distance))
  Bool.and(Bool.and(within_unit(hit_x, x), within_unit(hit_y, y)),
    within_unit(hit_z, z))

# A candidate whose screen box holds the pixel, with the exact distance along this
# pixel's ray written into the record. The winner's `depth` is therefore the exact
# ray distance, not the projected one, so the next candidate is compared against the
# same scale as the test that produced it. Rebuilding from the record's own fields
# rather than threading values down the walk matters: a rejected candidate is the
# common case by two orders of magnitude, and every value threaded past it is paid
# for on every candidate whether or not the walk needs it.
def retimed(+s: Screen, +distance: F32) -> Screen:
  Screen{low, high, depth, block, dir, alive, origin} = s
  Screen{low, high, distance, block, dir, alive, origin}

# The exact face-quad hit, when this candidate wins the pixel. The distance is a
# parameter rather than a computed value because a `match` may only scrutinize a
# parameter or a field, and this is the branch the walk should skip when the
# candidate is not nearer.
def decide(covered: Bool, +s: Screen, +distance: F32, +win: Screen) -> Screen:
  match covered:
    case False{}:
      win
    case True{}:
      retimed(s, distance)

# The quad test, behind a `match` on the depth comparison.
#
# `face_contains_hit` is three multiplies, three adds and six float compares against
# the two float compares that decide whether the candidate is in front of the eye and
# nearer than the pixel's current winner. It used to be the third argument of a
# `Bool.and`, which evaluates both arguments before the call, so every candidate that
# reached the plane test paid for it — including the ones that had already lost on
# depth, which is the overwhelming majority. Of the candidates whose screen box holds
# a given pixel, only the ones that successively beat the running best reach the quad,
# and the expected number of those is the harmonic number of the bucket's depth-hits
# rather than the bucket's depth-hits itself.
def decide.quad(nearer_than_win: Bool, +s: Screen, +origin: P, +eye: Voxel.Vec,
  +ray: Voxel.Vec, +distance: F32, +win: Screen) -> Screen:
  match nearer_than_win:
    case False{}:
      win
    case True{}:
      decide(face_contains_hit(origin, eye, ray, distance), s, distance, win)

# The plane intersection, behind a `match` on the in-front-of-the-eye comparison, so
# the depth comparison is made before the quad test rather than alongside it. This is a
# divide, three multiplies and six float compares, against the two integer compares of
# the box test, and a bucket holds every face that overlaps its tile while a pixel is
# covered by only the few whose screen box contains it, so running this for every
# candidate in the tile was most of the per-pixel cost.
def nearer(+s: Screen, +eye: Voxel.Vec, +ray: Voxel.Vec, +win: Screen) -> Screen:
  +face_dir = s_dir(s)
  +origin = s_origin(s)
  +distance = ray_plane_depth(face_dir, origin, eye, ray)
  decide.quad(Bool.and(F32.is_gt(distance, 0.0001), F32.is_lt(distance, s_depth(win))),
    s, origin, eye, ray, distance, win)

# The pixel is above the box's top edge, or level with it and right of its right
# edge. Splitting the box test across two `match`es is what makes the second compare
# conditional: a candidate whose box starts past the pixel in y is rejected on one
# compare, and the runtime never dispatches the second.
def consider.inside(inside: Bool, +s: Screen, +eye: Voxel.Vec, +ray: Voxel.Vec,
  +win: Screen) -> Screen:
  match inside:
    case False{}:
      win
    case True{}:
      nearer(s, eye, ray, win)

# The pixel is below the box's bottom edge, or level with it and left of its left
# edge. The two halves of the packed words decide this between them: y sits in the
# more significant half, so it settles the test unless the two y values tie.
def consider(low_side: Bool, high: U32, +s: Screen, +pix: U32, +eye: Voxel.Vec,
  +ray: Voxel.Vec, +win: Screen) -> Screen:
  match low_side:
    case False{}:
      win
    case True{}:
      consider.inside(U32.is_le(pix, high), s, eye, ray, win)

# Walk the bucket, folding the winning face forward. The accumulator is a `Screen`
# and not a `Best` on purpose: a rejected candidate is by far the common case, and
# with a `Best` it cost a record allocation per rejection. At the client's own view
# that is 170 candidates for each of 4,096 pixels, in the loop whose whole job is
# to reject them. Here a rejected candidate allocates nothing, and a winner costs
# the one record that carries the new depth.
#

# per call and not per candidate: measured against a one-candidate-per-call walk

# a twentieth of the total, so the rest is the step back into the loop.
def scan_bucket(bucket: List<&2, Screen>, +pix: U32, +eye: Voxel.Vec,
  +ray: Voxel.Vec, +win: Screen) -> Screen:
  match bucket:
    case Nil{}:
      win
    case +s <> rest:
      Screen{low, high, depth, block, dir, alive, origin} = s
      scan_bucket(rest, pix, eye, ray,
        consider(U32.is_le(low, pix), high, s, pix, eye, ray, win))

# The nearest face covering one pixel, or the sky block when nothing covers it.
# The depth starts at the maximum so the first candidate always wins its test, and
# the block is 0, which is the sky the colour path already looks for. Its box spans
# the whole 16-bit range, so it sits in the same packed form the walk compares.
def no_face() -> Screen:
  Screen{(0 : U32), 4294967295, (1.0e30 : F32), (0 : U32), 0n, False{},
    P{(0.0 : F32), (0.0 : F32), (0.0 : F32)}}

def nearest_face(tiles: Tiles, +px: U32, +py: U32) -> Screen:
  Tiles{rows, size, +edge, +camera, half, focal} = tiles
  +eye = Voxel.Camera.eye(camera)
  +ray = Voxel.Camera.ray_for(camera, px, py, half, focal)
  # The pixel packs the way the boxes do, once per pixel rather than once per
  # candidate: this is the only place the walk's two compares are set up.
  +pix = pack(px, py)
  scan_bucket(bucket_at(rows, U32.div(px, edge), U32.div(py, edge)), pix, eye, ray,
    no_face())

def face_at_pixel(tiles: Tiles, +px: U32, +py: U32) -> Best:
  +win = nearest_face(tiles, px, py)
  Best{s_block(win), s_dir(win), s_depth(win)}

# The colour of one pixel, using the ray renderer's palette and per-face tint so
# the two renderers' colours are directly comparable.
#
# This looks like the eager-argument trap twice over and is neither. `Bool.pick` builds
# both arms, so a sky pixel does pay for `Voxel.block_color` — a match over thirty ids —
# and `Voxel.shade_color`, which is three integer divides; and the winner is read
# through `s_block` twice and `s_dir` once, three accessor calls each destructuring all
# seven fields. Splitting the pick behind a `match` and reading the winner once needs a
# `shade.of` helper and a `shade.is_sky` helper, because a destructure needs a parameter
# and a `let`-bound local will not do, and that is two more dispatches per pixel against
# the one it removes.
#
# Measured, it is a small loss: the sequential walk 53.70 ms against 52.80, with the bare
# iteration unchanged. The arithmetic is the reason and it is worth having — skipping a
# usually-taken arm saves three integer divides, about 23 cycles each, while a dispatch
# is well under ten, so the saving does not cover the call that buys it. `Bool.pick` is
# one dispatch for both arms; two helpers are two.
def face_pixel_color(tiles: Tiles, +px: U32, +py: U32) -> U32:
  +win = nearest_face(tiles, px, py)
  Bool.pick(U32, U32.is_eq(s_block(win), 0), Voxel.sky_color(py),
    Voxel.shade_color(Voxel.block_color(s_block(win)), U32.from_nat(s_dir(win))))

# ---------------------------------------------------------------------------
# 4a. Walk cost probe: what a step of the bucket walk actually costs.
# ---------------------------------------------------------------------------

# The floor. One cons cell, one destructure, one add, one tail call: no test, no
# branch, no helper. This is the runtime's list iteration and nothing else, so the
# difference between it and `scan_bucket` is everything the walk does per candidate
# on top of stepping.
def step_only(bucket: List<&2, Screen>, +pix: U32, +acc: U32) -> U32:
  match bucket:
    case Nil{}:
      acc
    case +s <> rest:
      Screen{low, high, depth, block, dir, alive, origin} = s
      step_only(rest, pix, U32.add(acc, low))

# The same iteration with the destructure left out. `step_only` binds all seven fields
# of the record because a pattern must list every one of them, and the walk reads two;
# the difference between this and `step_only` is what those five unread field reads
# cost, which is the whole case for splitting the record.
def step_bare(bucket: List<&2, Screen>, +acc: U32) -> U32:
  match bucket:
    case Nil{}:
      acc
    case +s <> rest:
      step_bare(rest, U32.add(acc, 1))

# The same walk with the two halves of the box test folded into one `Bool.and` and
# one helper, so the reject path makes a single call instead of two. The shipped walk
# splits the test so the second compare is conditional; here both are always paid and
# the call is saved. The bench measures the two the same over three runs, so this is
# not an improvement to collect — it is here because it is the other end of the
# measurement that prices the walk's reject path, and because it is the shape the
# split has to be checked against. `nearest_face_one` is the same answer as
# `nearest_face`, and `face_probe_test` holds them equal on every pixel.
def consider.any(inside: Bool, +s: Screen, +eye: Voxel.Vec, +ray: Voxel.Vec,
  +win: Screen) -> Screen:
  match inside:
    case False{}:
      win
    case True{}:
      nearer(s, eye, ray, win)

def scan_bucket_one(bucket: List<&2, Screen>, +pix: U32, +eye: Voxel.Vec,
  +ray: Voxel.Vec, +win: Screen) -> Screen:
  match bucket:
    case Nil{}:
      win
    case +s <> rest:
      Screen{low, high, depth, block, dir, alive, origin} = s
      scan_bucket_one(rest, pix, eye, ray,
        consider.any(Bool.and(U32.is_le(low, pix), U32.is_le(pix, high)), s, eye, ray, win))

def nearest_face_one(tiles: Tiles, +px: U32, +py: U32) -> Screen:
  Tiles{rows, size, +edge, +camera, half, focal} = tiles
  +eye = Voxel.Camera.eye(camera)
  +ray = Voxel.Camera.ray_for(camera, px, py, half, focal)
  +pix = pack(px, py)
  scan_bucket_one(bucket_at(rows, U32.div(px, edge), U32.div(py, edge)), pix, eye, ray,
    no_face())

def face_pixel_color_one(tiles: Tiles, +px: U32, +py: U32) -> U32:
  +win = nearest_face_one(tiles, px, py)
  Bool.pick(U32, U32.is_eq(s_block(win), 0), Voxel.sky_color(py),
    Voxel.shade_color(Voxel.block_color(s_block(win)), U32.from_nat(s_dir(win))))

# The bare iteration, summed over every pixel, so a benchmark can time it.
def step_mix(hash: U32, value: U32) -> U32:
  U32.xor(U32.mul(hash, 16777619), value)

def step_row(+rows: List<&2, List<&2, List<&2, Screen>>>, +edge: U32, remaining: Nat,
  +px: U32, +py: U32, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+r:
      +next = (px + 1 : U32)
      step_row(rows, edge, r, next, py,
        step_mix(hash, step_only(bucket_at(rows, U32.div(px, edge), U32.div(py, edge)),
          pack(px, py), 2166136261)))

def step_walk(+rows: List<&2, List<&2, List<&2, Screen>>>, +edge: U32, +size: U32,
  rows_left: Nat, +py: U32, +hash: U32) -> U32:
  match rows_left:
    case 0n:
      hash
    case 1n+r:
      +next = (py + 1 : U32)
      step_walk(rows, edge, size, r, next, step_row(rows, edge, U32.to_nat(size), 0, py, hash))

def step_bare_row(+rows: List<&2, List<&2, List<&2, Screen>>>, +edge: U32,
  remaining: Nat, +px: U32, +py: U32, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+r:
      step_bare_row(rows, edge, r, (px + 1 : U32), py,
        step_mix(hash, step_bare(bucket_at(rows, U32.div(px, edge), U32.div(py, edge)),
          2166136261)))

def step_bare.walk(+rows: List<&2, List<&2, List<&2, Screen>>>, +edge: U32, +size: U32,
  rows_left: Nat, +py: U32, +hash: U32) -> U32:
  match rows_left:
    case 0n:
      hash
    case 1n+r:
      step_bare.walk(rows, edge, size, r, (py + 1 : U32),
        step_bare_row(rows, edge, U32.to_nat(size), 0, py, hash))

def step_bare.go(remaining: Nat, +rows: List<&2, List<&2, List<&2, Screen>>>,
  +edge: U32, +size: U32, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+r:
      step_bare.go(r, rows, edge, size,
        step_bare.walk(rows, edge, size, U32.to_nat(size), 0, hash))

# A \match\ may only scrutinize a parameter or a field, and destructuring the grid
# turns every other binder into a computed value, so the countdown and the destructure
# cannot share a definition.
def step_bare.rows(remaining: Nat, +tiles: Tiles, +size: U32, +hash: U32) -> U32:
  Tiles{rows, tile_size, edge, camera, half, focal} = tiles
  step_bare.go(remaining, rows, edge, size, hash)

def step_bare.go2(remaining: Nat, +tiles: Tiles, +size: U32, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      step_bare.rows(p, tiles, size, hash)

# A `match` may only scrutinize a parameter or a field, and destructuring the grid
# turns every other binder into a computed value, so the countdown and the destructure
# cannot share a definition.
def step.rows.go(remaining: Nat, +rows: List<&2, List<&2, List<&2, Screen>>>,
  +edge: U32, +size: U32, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+r:
      step.rows.go(r, rows, edge, size,
        step_walk(rows, edge, size, U32.to_nat(size), 0, hash))

def step.rows(remaining: Nat, +tiles: Tiles, +size: U32, +hash: U32) -> U32:
  Tiles{rows, tile_size, edge, camera, half, focal} = tiles
  step.rows.go(remaining, rows, edge, size, hash)

def step.go(remaining: Nat, +tiles: Tiles, +size: U32, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      step.rows(p, tiles, size, hash)

# The one-call walk, over the same grid, driven the same way `pixel.go` drives the
# shipped one.
def one_row(+tiles: Tiles, remaining: Nat, +px: U32, +py: U32, +size: U32,
  +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+r:
      +next = (px + 1 : U32)
      one_row(tiles, r, next, py, size, step_mix(hash, face_pixel_color_one(tiles, px, py)))

def one_walk(+tiles: Tiles, rows_left: Nat, +py: U32, +size: U32, +hash: U32) -> U32:
  match rows_left:
    case 0n:
      hash
    case 1n+r:
      +next = (py + 1 : U32)
      one_walk(tiles, r, next, size, one_row(tiles, U32.to_nat(size), 0, py, size, hash))

def one.go(remaining: Nat, +tiles: Tiles, +size: U32, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      one.go(p, tiles, size, one_walk(tiles, U32.to_nat(size), 0, size, hash))

# ---------------------------------------------------------------------------
# 5. The quadtree fold, the same shape as the ray renderer's `image`.
# ---------------------------------------------------------------------------

# At a leaf, pixel coordinates are divided by the configured edge to select a
# tile. The four-quadrant fork matches `Voxel.image` exactly.
def face_image(+depth: Nat, +tiles: Tiles, +px: U32, +py: U32) -> Image:
  match depth:
    case 0n:
      Pix{face_pixel_color(tiles, px, py)}
    case 1n+q:
      +step = U32.shln((1 : U32), q)
      tl tr bl br = face_image(q, tiles, px, py)
        face_image(q, tiles, (px + step : U32), py)
        face_image(q, tiles, px, (py + step : U32))
        face_image(q, tiles, (px + step : U32), (py + step : U32))
      Qua{tl, tr, bl, br}

# Render a 2^depth frame from an already-bucketed tile grid.
def render_size_tiles(tiles: Tiles, depth: Nat) -> Image:
  face_image(depth, tiles, 0, 0)

# The tile grid's rows, for a caller that wants to resolve pixels itself rather
# than through the quadtree. The pixel fold and the agreement measurement both
# use this, so they see exactly the same candidates the image does.
def tiles_rows(tiles: Tiles) -> List<&2, List<&2, List<&2, Screen>>>:
  match tiles:
    case Tiles{rows, size, edge, camera, half, focal}:
      rows

def tiles_edge(tiles: Tiles) -> U32:
  match tiles:
    case Tiles{rows, size, edge, camera, half, focal}:
      edge

def tiles_size(tiles: Tiles) -> U32:
  match tiles:
    case Tiles{rows, size, edge, camera, half, focal}:
      size

# The side labels present at one cell, as a bitmask over 0..5.
def at_mask(at: At) -> U32:
  match at:
    case At{mask, total}:
      mask

def at_total(at: At) -> U32:
  match at:
    case At{mask, total}:
      total

# Every projected face's box, as text. This is a diagnostic for a failing
# projection: it shows the pixel box and depth each face was given, so a wrong
# side or a wrong plane is visible without rendering a frame.
def boxes_go(faces: List<&2, Face>, +eye: Voxel.Vec, +right: Voxel.Vec, +up: Voxel.Vec,
  +forward: Voxel.Vec, +half: F32, +focal: F32, +size: U32, +acc: String) -> String:
  match faces:
    case Nil{}:
      acc
    case Face{fx, fy, fz, +dir, block} <> rest:
      +boxed = box_of(dir, block, U32.to_f32(fx), U32.to_f32(fy), U32.to_f32(fz),
        eye, right, up, forward, half, focal)
      +clipped = clip_screen(boxed, size)
      +line = "[dir=" ++ Nat.show(dir) ++ " box=" ++ U32.show(s_x0(clipped)) ++ ","
        ++ U32.show(s_y0(clipped)) ++ ".." ++ U32.show(s_x1(clipped)) ++ ","
        ++ U32.show(s_y1(clipped)) ++ " depthx100=" ++ U32.show(F32.to_u32(F32.mul(s_depth(clipped), 100.0)))
        ++ " alive=" ++ Bool.show(s_alive(clipped)) ++ "]"
      boxes_go(rest, eye, right, up, forward, half, focal, size, acc ++ line)

# A full frame from a bulk chunk: extract, project, bucket, then fold. This is
# the path the benchmark times, so it is exactly the work a real frame would do.
def render_size_at_with_tile_size(chunk: Array<U32>, +eye: Voxel.Vec, +yaw: F32,
  +pitch: F32, +depth: Nat, +edge: U32) -> Image:
  +camera : Voxel.Camera = Voxel.Camera.look(eye, yaw, pitch)
  +half = Voxel.projection_half(depth)
  +focal = F32.mul(1.5, half)
  +size = U32.shln((1 : U32), depth)
  +tiles = bucket_faces_with_tile_size(faces_from_chunk(chunk), cam_eye(camera),
    cam_right(camera), cam_up(camera), cam_forward(camera), half, focal, size, edge)
  render_size_tiles(tiles, depth)

# The frame over a face list the caller already holds. Extraction is the client's to
# schedule, not the renderer's: the region's cells do not change when the player walks,
# so a client that re-extracts them every frame pays for a world that did not move.
# Everything from the projection down is the same code either way.
def render_faces_at_with_tile_size(faces: List<&2, Face>, +eye: Voxel.Vec, +yaw: F32,
  +pitch: F32, +depth: Nat, +edge: U32) -> Image:
  +camera : Voxel.Camera = Voxel.Camera.look(eye, yaw, pitch)
  +half = Voxel.projection_half(depth)
  +focal = F32.mul(1.5, half)
  +size = U32.shln((1 : U32), depth)
  render_size_tiles(bucket_faces_with_tile_size(faces, cam_eye(camera), cam_right(camera),
    cam_up(camera), cam_forward(camera), half, focal, size, edge), depth)

# The same frame over a region of chunks. Identical to the entry above from the
# projection down; only the face source differs, so a region cannot drift into a
# different camera, bucket or fill than the one-chunk path the agreement gate checks.
def render_region_at_with_tile_size(chunks: List<&2, List<&2, U32>>, columns: Nat,
  rows: Nat, +eye: Voxel.Vec, +yaw: F32, +pitch: F32, +depth: Nat, +edge: U32) -> Image:
  render_faces_at_with_tile_size(faces_from_chunks(chunks, columns, rows), eye, yaw,
    pitch, depth, edge)

def render_size_at(chunk: Array<U32>, +eye: Voxel.Vec, +yaw: F32, +pitch: F32,
  +depth: Nat) -> Image:
  render_size_at_with_tile_size(chunk, eye, yaw, pitch, depth, 8)

def render_at(chunk: Array<U32>, +eye: Voxel.Vec, +yaw: F32, +pitch: F32) -> Image:
  render_size_at(chunk, eye, yaw, pitch, 5n)

# How many candidates the per-pixel walk actually considered across a whole
# frame. This is the measured cost model, not an assumption about it.
# Each tile's bucket is charged once per pixel in that tile, so this reports the
# actual candidate walk for the configured tile edge.
#
def count_row(+count: Nat, +tx: U32, +ty: U32, +edge: U32,
  +rows: List<&2, List<&2, List<&2, Screen>>>, +total: U32) -> U32:
  match count:
    case 0n:
      total
    case 1n+r:
      +bucket = bucket_at(rows, tx, ty)
      +added = (total + U32.from_nat(List.length(&2, Screen, bucket)) : U32)
      count_row(r, tx, ty, edge, rows, added)

# One row of tiles, each paying its own block cost.
def count_tile_row(remaining: Nat, +tx: U32, +ty: U32, +edge: U32,
  +rows: List<&2, List<&2, List<&2, Screen>>>, +across: U32, +total: U32) -> U32:
  match remaining:
    case 0n:
      total
    case 1n+p:
      +pixels = U32.to_nat(U32.mul(edge, edge))
      count_tile_row(p, (tx + 1 : U32), ty, edge, rows, across,
        count_row(pixels, tx, ty, edge, rows, total))

# Every tile row of the grid.
def count_tiles(remaining: Nat, +ty: U32, +edge: U32,
  +rows: List<&2, List<&2, List<&2, Screen>>>, +across: U32, +total: U32) -> U32:
  match remaining:
    case 0n:
      total
    case 1n+p:
      count_tiles(p, (ty + 1 : U32), edge, rows, across,
        count_tile_row(U32.to_nat(across), 0, ty, edge, rows, across, total))

def candidate_count(size: U32, +tiles: Tiles) -> U32:
  +rows = tiles_rows(tiles)
  +edge = tiles_edge(tiles)
  +across = tiles_across(size, edge)
  count_tiles(U32.to_nat(across), 0, edge, rows, across, 0)

type GridStats is Data:
  GridStats{entries: U32, path_cells: U32}

def stats_entries(stats: GridStats) -> U32:
  match stats:
    case GridStats{entries, path_cells}:
      entries

def stats_path_cells(stats: GridStats) -> U32:
  match stats:
    case GridStats{entries, path_cells}:
      path_cells

# Count candidate cons cells and the prefix cells rebuilt by each List.set in
# the scatter builder. A set at tile index tx copies tx+1 bucket-row cells; the
# row update similarly copies ty+1 outer-grid cells.
def stats_bucket_row(row: List<&2, List<&2, Screen>>, +tx: U32, +ty: U32,
  +entries: U32, +path_cells: U32) -> GridStats:
  match row:
    case Nil{}:
      GridStats{entries, path_cells}
    case +bucket <> rest:
      +length = U32.from_nat(List.length(&2, Screen, bucket))
      +per_entry = U32.add(U32.add(tx, ty), 3)
      +added_path = U32.mul(length, per_entry)
      stats_bucket_row(rest, (tx + 1 : U32), ty, U32.add(entries, length),
        U32.add(path_cells, added_path))

def stats_grid_rows(rows: List<&2, List<&2, List<&2, Screen>>>, +ty: U32,
  +entries: U32, +path_cells: U32) -> GridStats:
  match rows:
    case Nil{}:
      GridStats{entries, path_cells}
    case +row <> rest:
      +row_stats = stats_bucket_row(row, 0, ty, 0, 0)
      +row_entries = stats_entries(row_stats)
      +row_paths = stats_path_cells(row_stats)
      stats_grid_rows(rest, (ty + 1 : U32), U32.add(entries, row_entries),
        U32.add(path_cells, row_paths))

# The direct scatter builder allocates two empty spines (one shared bucket row
# and the outer row spine), then one candidate cell plus two set paths per face
# placement. This excludes screen records and the extracted Face list.
def scatter_grid_list_cells(size: U32, +tiles: Tiles) -> U32:
  +across = U32.div(size, tiles_edge(tiles))
  +stats = stats_grid_rows(tiles_rows(tiles), 0, 0, 0)
  U32.add(U32.mul(across, 2), stats_path_cells(stats))

# Row-major construction directly conses each bucket entry, one tile slot per
# tile, and one outer row cell per row. Its separate projected Screen list has
# one cell per exposed Face and is not part of the bucket grid.
def row_major_grid_list_cells(size: U32, +tiles: Tiles) -> U32:
  +across = U32.div(size, tiles_edge(tiles))
  +entries = stats_entries(stats_grid_rows(tiles_rows(tiles), 0, 0, 0))
  U32.add(entries, U32.add(U32.mul(across, across), across))

# Reconstruct the allocation count of the earlier scatter shape for comparison:
# quadratic append prefixes for the empty rows, plus an eager empty row passed
# as Maybe.default on every insertion.
def legacy_scatter_grid_list_cells(size: U32, +tiles: Tiles) -> U32:
  +across = U32.div(size, tiles_edge(tiles))
  +stats = stats_grid_rows(tiles_rows(tiles), 0, 0, 0)
  +empty_row = U32.add(across, U32.div(U32.mul(across, U32.add(across, 1)), 2))
  +fallback_rows = U32.mul(across, stats_entries(stats))
  U32.add(stats_path_cells(stats),
    U32.add(empty_row, fallback_rows))
# The candidate bucket one tile holds, as text. A diagnostic for a failing
# projection: it shows which faces reached the tile the failing pixel is in.
def dump_go(bucket: List<&2, Screen>, +acc: String) -> String:
  match bucket:
    case Nil{}:
      acc
    case +s <> rest:
      dump_go(rest, acc ++ "[d=" ++ Nat.show(s_dir(s)) ++ " " ++ U32.show(s_x0(s)) ++ ","
        ++ U32.show(s_y0(s)) ++ ".." ++ U32.show(s_x1(s)) ++ "," ++ U32.show(s_y1(s))
        ++ " z=" ++ U32.show(F32.to_u32(F32.mul(s_depth(s), 100.0))) ++ "]")

def dump_bucket(+rows: List<&2, List<&2, List<&2, Screen>>>, +tx: U32, +ty: U32) -> String:
  dump_go(bucket_at(rows, tx, ty), "")

def boxes_for(faces: List<&2, Face>, +eye: Voxel.Vec, +right: Voxel.Vec, +up: Voxel.Vec,
  +forward: Voxel.Vec, +half: F32, +focal: F32, +size: U32) -> String:
  boxes_go(faces, eye, right, up, forward, half, focal, size, "")
