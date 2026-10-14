import Base
import ../../../world/player.bend as Player
import ../../../world/world_state.bend as WorldState
import ../../../native/player.bend as PlayerProbe
import ../../../native/voxel.bend as Voxel
import ../../../native/frame.bend as Frame
import ../../../native/face.bend as Face
import ../../../native/client.bend as Client

# ---------------------------------------------------------------------------
# What a painter's algorithm would cost, measured rather than argued.
#
# The shipping renderer is a per-pixel bucket walk: every pixel walks every face whose
# *bounding box* overlaps its tile, and rejects the ones that are not there. At the client's
# own camera that is 1,957,888 candidate steps for a 16,384-pixel frame, and `clip_area`
# says the boxes those steps cover total 1,547,675 pixels.
#
# A painter asks a different question: for each face, which pixels does its own quad
# actually cover? That is `Face.quad_area`, and the facts line reports 50,102 pixels for
# the same frame. So the geometry the walk charges for is 31x the geometry there is, and
# the gap is the box's waste over the quad: a face seen at a grazing angle is long and
# thin, and a bounding box around one is nearly square.
#
# That ratio is the whole case for replacing the walk, so the painter's dominant term is
# measured here rather than assumed:
#
#   1. spans. For each face and each scanline of its quad, the x-range the quad covers on
#      that line. A span is the unit of work a painter's algorithm actually has, and how
#      many there are is a property of the geometry, not of a renderer choice.
#   2. span pixels. How many pixels those spans cover, against the walk's candidates and
#      against the canvas.
#   3. the fill. Writing those spans into a flat `Array<U32>` frame, which is the painter's
#      own work and nothing else.
#
# The fill is timed unconditionally, in face-list order, with no depth test and no
# ordering. That is a lower bound and it is deliberate: it is the cheapest a painter can
# be, and it is the right shape for asking whether there is room in a 16.67 ms frame at a
# resolution the walk cannot reach. Correctness would add the ordering and the depth test;
# this says whether the term underneath them is affordable first.
#
# The array is `Array<U32>` of `size * size` slots, which is what `Face.Square` already
# projects into and what the quadtree fold will later read back.
# ---------------------------------------------------------------------------

type Counted is Data:
  Counted{spans: U32, pixels: U32}

# A scanline's x-range. A record rather than a pair because `span_x` has to be read back
# by a def that takes it as a parameter: a `match` cannot scrutinize a local binder, so a
# pair handed straight out of a call could not be destructured by its caller.
type Span is Data:
  Span{x0: U32, x1: U32}

# A face's rows inside the frame: the first row, and one past the last.
type Rows is Data:
  Rows{first: U32, stop: U32}

def fold_hash(+hash: U32, +value: U32) -> U32:
  U32.mul(U32.xor(hash, value), 16777619)

# --- the client's own camera, region and palette ------------------------------

def region_faces(+edits: List<&2, WorldState.Edit>) -> List<&2, Face.Face>:
  Face.faces_from_chunks(Client.region_chunks(Frame.seed(), edits), Frame.view_columns(),
    Frame.view_rows())

def camera_of(+pose: Frame.Pose) -> Voxel.Camera:
  Voxel.Camera.look(Frame.eye_of(pose), Frame.yaw_of(pose), Frame.pitch_of(pose))

def colour_of(+block: U32, +dir: Nat) -> U32:
  Voxel.shade_color(Voxel.block_color(block), U32.from_nat(dir))

# --- one scanline of a projected quad ----------------------------------------
#
# A projected quad is convex, so any interior scanline crosses exactly two of its four
# edges. Each edge contributes a crossing x when it straddles the line and nothing when it
# does not, so the left bound is the minimum over the four and the right bound is the
# maximum over the four, with a non-crossing edge contributing a sentinel each way. The
# sentinels are past any frame edge and before any pixel, so neither can win a comparison
# it should lose.

def far() -> F32:
  1.0e30

def near() -> F32:
  F32.neg(1.0e30)

def crossing_x(+y: F32, +ax: F32, +ay: F32, +bx: F32, +by: F32) -> F32:
  F32.add(ax, F32.mul(F32.div(F32.sub(y, ay), F32.sub(by, ay)), F32.sub(bx, ax)))

# Whether the edge straddles the line: y is at or above one end and strictly below the
# other. Half-open, so a scanline through a vertex counts the edge below it exactly once.
def straddles(+y: F32, +ay: F32, +by: F32) -> Bool:
  Bool.or(Bool.and(F32.is_ge(y, ay), F32.is_lt(y, by)),
    Bool.and(F32.is_ge(y, by), F32.is_lt(y, ay)))

def keep_left(crossed: Bool, +x: F32, +best: F32) -> F32:
  match crossed:
    case True{}:
      F32.min(best, x)
    case False{}:
      best

def keep_right(crossed: Bool, +x: F32, +best: F32) -> F32:
  match crossed:
    case True{}:
      F32.max(best, x)
    case False{}:
      best

# The x-range of one scanline of the quad, clamped into the frame. A face that crosses the
# eye plane projects a corner far outside any frame, and the clamp is what keeps that out
# of the arithmetic rather than the arithmetic out of the picture.
def span_x(s: Face.Square, +y: F32, +size: U32) -> Span:
  Face.Square{a, b, c, d} = s
  Face.Q{+ax, +ay, _} = a
  Face.Q{+bx, +by, _} = b
  Face.Q{+cx, +cy, _} = c
  Face.Q{+dx, +dy, _} = d
  +last = F32.from_nat(U32.to_nat(U32.sub(size, (1 : U32))))
  +e1 = keep_left(straddles(y, ay, by), crossing_x(y, ax, ay, bx, by), far())
  +e2 = keep_left(straddles(y, by, cy), crossing_x(y, bx, by, cx, cy), e1)
  +e3 = keep_left(straddles(y, cy, dy), crossing_x(y, cx, cy, dx, dy), e2)
  +e4 = keep_left(straddles(y, dy, ay), crossing_x(y, dx, dy, ax, ay), e3)
  +f1 = keep_right(straddles(y, ay, by), crossing_x(y, ax, ay, bx, by), near())
  +f2 = keep_right(straddles(y, by, cy), crossing_x(y, bx, by, cx, cy), f1)
  +f3 = keep_right(straddles(y, cy, dy), crossing_x(y, cx, cy, dx, dy), f2)
  +f4 = keep_right(straddles(y, dy, ay), crossing_x(y, dx, dy, ax, ay), f3)
  # The two bounds are clamped into the frame as floats and then converted, so an edge that
  # is nearly parallel to a scanline — where the crossing divides by almost zero and lands
  # far outside any frame — cannot become a pixel index.
  +left = F32.to_u32(F32.min(F32.max(e4, 0.0), last))
  +right = F32.to_u32(F32.max(F32.min(f4, last), 0.0))
  Span{left, U32.max(right, left)}

# A face wholly above the frame has a `bottom` below zero, and a face wholly below has a
# `top` past the last row. Either way the span clamps to nothing while the row count stays
# enormous, and `F32.to_u32` of a negative floor is not a small number, so a face that
# misses the frame is given an empty row range: `first == stop`, both inside the frame.
def span_bounds(+top: F32, +bottom: F32, +size: U32) -> Rows:
  +last = U32.sub(size, (1 : U32))
  +misses = Bool.or(F32.is_ge(top, F32.from_nat(U32.to_nat(size))),
    F32.is_le(bottom, 0.0))
  +first = Bool.pick(U32, misses, (0 : U32), F32.to_u32(F32.max(F32.floor(top), 0.0)))
  +stop = Bool.pick(U32, misses, first,
    U32.add(F32.to_u32(F32.min(F32.floor(bottom), F32.from_nat(U32.to_nat(last)))),
      (1 : U32)))
  Rows{U32.min(first, last), U32.max(stop, U32.min(first, last))}

# The quad's vertical extent as whole scanline rows inside the frame: the first row and
# one past the last. A quad that misses the frame vertically yields no rows at all, which
# is what a painter skips and a per-pixel walk does not.
def span_rows(s: Face.Square, +size: U32) -> Rows:
  Face.Square{a, b, c, d} = s
  Face.Q{_, +ay, _} = a
  Face.Q{_, +by, _} = b
  Face.Q{_, +cy, _} = c
  Face.Q{_, +dy, _} = d
  span_bounds(F32.min(F32.min(ay, by), F32.min(cy, dy)),
    F32.max(F32.max(ay, by), F32.max(cy, dy)), size)

def rows_first(r: Rows) -> U32:
  match r:
    case Rows{first, stop}:
      first

def rows_stop(r: Rows) -> U32:
  match r:
    case Rows{first, stop}:
      stop

# How many scanlines this face contributes inside the frame: none at all for a face that
# misses it, which is what `span_rows` reports.
def rows_of(r: Rows) -> Nat:
  match r:
    case Rows{first, stop}:
      Nat.sub(U32.to_nat(stop), U32.to_nat(first))

def span_left_at(s: Span) -> U32:
  match s:
    case Span{x0, x1}:
      x0

def span_right_at(s: Span) -> U32:
  match s:
    case Span{x0, x1}:
      x1

# The span's width in pixels. The bounds are already clamped, so this is the right less the
# left plus the pixel at the right — which is what the fill writes.
def span_width(s: Span) -> U32:
  Span{x0, x1} = s
  U32.add(U32.sub(x1, x0), (1 : U32))

# The span written into one row of the frame. It is a def over `Span` rather than a pair
# so the span's two coordinates can each be read once.
# One span is `remaining` pixels of one row in one colour. The walk is one array write and
# one add per pixel, with no arithmetic beyond the address.
def fill_span(remaining: Nat, +at: U32, +colour: U32, frame: Array<U32>) -> Array<U32>:
  match remaining:
    case 0n:
      frame
    case 1n+r:
      fill_span(r, (at + 1 : U32), colour, frame[at] <- colour)

# The span written into one row of the frame: `last` pixels wide at most, starting at
# `first`.
#
# The clamp is a correctness requirement, not a guard. `span_x` already clamps its two bounds
# into the frame, but a projected edge whose two ends share a screen y divides by zero, and
# the resulting infinity is not a number a `F32.to_u32` can be trusted with — the first run of
# this probe turned one such face into a four-billion-pixel span and hung. Clamping after the
# conversion is what makes the count a count: `first` and `stop` are both inside the frame,
# and a `stop` at or below `first` is one pixel rather than an underflow.
def fill_row(+span: Span, +row: U32, +colour: U32, frame: Array<U32>) -> Array<U32>:
  fill_span(U32.to_nat(span_width(span)), U32.add(row, span_left_at(span)), colour, frame)

def frame_size(depth: Nat) -> U32:
  U32.shln((1 : U32), depth)

# A `size`-square frame is a `2*depth`-deep array of `size * size` slots, and the depth is
# what `Array.new` takes.
def slots_of(depth: Nat) -> Nat:
  Nat.mul(2n, depth)

# --- counting and filling the spans ------------------------------------------

def counted.zero() -> Counted:
  Counted{(0 : U32), (0 : U32)}

def counted.plus(left: Counted, right: Counted) -> Counted:
  Counted{spans, pixels} = left
  Counted{more_spans, more_pixels} = right
  Counted{U32.add(spans, more_spans), U32.add(pixels, more_pixels)}

def counted_spans(c: Counted) -> U32:
  match c:
    case Counted{spans, pixels}:
      spans

def counted_pixels(c: Counted) -> U32:
  match c:
    case Counted{spans, pixels}:
      pixels

# The painter runs as two folds over the same face list, and the split is not a convenience.
#
# A painter needs two things from a span: its width, to know the work, and the frame to
# write into. An `Array` is a `Type` and has exactly one owner, so the frame cannot be
# carried beside a tally in one accumulator and unpacked at each step: unpacking a pair
# needs a parameter to destructure, and the fold's own list is already that parameter, and a
# helper to do the unpacking would be a cycle, which the language has none of. So the tally
# and the frame are folded separately. The tally's fold is cheap arithmetic on the same
# spans the fill writes, and the fill's fold touches only the frame.
#
# The two folds together are what a painter's algorithm costs on this scene, which is the
# number this probe exists to produce.

# One scanline of one face: the span's width folded into the tally.
def count.row(remaining: Nat, +y: U32, +square: Face.Square, +size: U32,
  counted: Counted) -> Counted:
  match remaining:
    case 0n:
      counted
    case 1n+r:
      count.row(r, (y + 1 : U32), square, size, counted.plus(
        Counted{(1 : U32), span_width(span_x(square, F32.from_nat(U32.to_nat(y)), size))},
        counted))

# The tally's fold over the whole face list. One face's projection is inline rather than in
# a helper, because a helper here would have to call back into this fold and the language
# has neither forward references nor helper cycles.
def count.go(faces: List<&2, Face.Face>, +eye: Voxel.Vec, +right: Voxel.Vec, +up: Voxel.Vec,
  +forward: Voxel.Vec, +half: F32, +focal: F32, +size: U32, counted: Counted) -> Counted:
  match faces:
    case Nil{}:
      counted
    case Face.Face{fx, fy, fz, dir, block} <> rest:
      +square = Face.square_of(dir, U32.to_f32(fx), U32.to_f32(fy), U32.to_f32(fz), eye, right,
        up, forward, half, focal)
      +rows = span_rows(square, size)
      count.go(rest, eye, right, up, forward, half, focal, size, count.row(rows_of(rows),
        rows_first(rows), square, size, counted))

# One scanline of one face, written into the frame. The span is computed once and its two
# coordinates read once each inside `fill_row`.
def fill.row(remaining: Nat, +y: U32, +square: Face.Square, +size: U32, +colour: U32,
  frame: Array<U32>) -> Array<U32>:
  match remaining:
    case 0n:
      frame
    case 1n+r:
      fill.row(r, (y + 1 : U32), square, size, colour,
        fill_row(span_x(square, F32.from_nat(U32.to_nat(y)), size), (y * size : U32), colour,
          frame))

# A face the eye is inside or behind part of. `Face.project` divides by
# `max(depth, 0.0001)`, so a corner behind the eye projects to a coordinate of tens of
# millions of pixels; the crossing interpolation then spans the whole row and the face
# paints a full-width band over everything behind it. Measured on the spawn scene:
# 0 straddling faces scores 0.3% wrong blocks and 932 scores 100%.
def q_behind(q: Face.Q) -> Bool:
  F32.is_le(Face.q_depth(q), 0.0001)

def square_behind(+s: Face.Square) -> Bool:
  Face.Square{a, b, c, d} = s
  Bool.or(Bool.or(q_behind(a), q_behind(b)), Bool.or(q_behind(c), q_behind(d)))

def fill.draw(skip: Bool, +square: Face.Square, +size: U32, +colour: U32,
  frame: Array<U32>) -> Array<U32>:
  match skip:
    case True{}:
      frame
    case False{}:
      fill.row(rows_of(span_rows(square, size)), rows_first(span_rows(square, size)), square,
        size, colour, frame)

# The fill's fold over the whole face list. It is the painter's own work and nothing else:
# one projection per face, one span per scanline, one array write per pixel, no depth test
# and no ordering.
def fill.go(faces: List<&2, Face.Face>, +eye: Voxel.Vec, +right: Voxel.Vec, +up: Voxel.Vec,
  +forward: Voxel.Vec, +half: F32, +focal: F32, +size: U32, frame: Array<U32>) -> Array<U32>:
  match faces:
    case Nil{}:
      frame
    case Face.Face{fx, fy, fz, dir, block} <> rest:
      # A pattern binds each field once, and this face's label is needed twice: once to
      # choose the plane and the in-plane axes, and once to shade the colour. A `+` let
      # reads it into a reusable binding, which is what lets both see it.
      +label : Nat = dir
      +square = Face.square_of(label, U32.to_f32(fx), U32.to_f32(fy), U32.to_f32(fz), eye,
        right, up, forward, half, focal)
      fill.go(rest, eye, right, up, forward, half, focal, size,
        fill.draw(square_behind(square), square, size, colour_of(block, label), frame))

# ---------------------------------------------------------------------------
# How much of the frame is one colour.
#
# This is the fact the read-back's cost turns on, and it is asked of the frame rather than of
# the renderer, so the answer is a property of this scene at this camera. A node of the
# quadtree whose pixels are all one colour can be a single `Pix`: the runtime's `window_sq`
# only descends into a constructor, so a `Pix` at any level fills its whole block and a
# shallower tree is the same picture. The read-back spends twelve contended forks per node
# over 1.4 million nodes, so if most blocks were one colour, testing a block *before* the
# fan-out would remove most of the tree and most of the forks.
#
# One flat pass, and the only def that recurses on the counter. The read pair is threaded as a
# parameter and the next pixel arrives as a call in argument position, which is the shape that
# gets a linear handle through a loop here: a `do` block's destructuring statement may only
# open a parameter, so `pixels[at]` cannot be destructured where it is written, and a `match`
# may not scrutinize a computed value. Block boundaries are arithmetic rather than a second
# nested loop, because a loop over blocks calling a scan that loops over pixels would be a
# helper cycle. The derived booleans are folded with `Bool.pick` and never matched on, which
# is what keeps them from needing a `match` of their own.
def uniform.done(read: Array<U32> & U32, +flat: U32) -> (Array<U32> & U32) & U32:
  (read, flat)

def uniform.go(remaining: Nat, read: Array<U32> & U32, +at: U32, +col: U32, +row: U32,
  +side: U32, +size: U32, +ref: U32, +same: Bool, +flat: U32) -> (Array<U32> & U32) & U32:
  match remaining:
    case 0n:
      uniform.done(read, flat)
    case 1n+r:
      (pixels, +value) = read
      +mask = U32.sub(side, (1 : U32))
      +opens = Bool.and(U32.is_eq(col, (0 : U32)), U32.is_eq(U32.and(row, mask), (0 : U32)))
      +closes = Bool.and(U32.is_eq(col, mask), U32.is_eq(U32.and(row, mask), mask))
      +kept = Bool.pick(Bool, opens, True{}, Bool.and(same, U32.is_eq(value, ref)))
      +next_ref = Bool.pick(U32, opens, value, ref)
      +next_flat = Bool.pick(U32, closes, U32.add(flat, Bool.pick(U32, kept, (1 : U32),
        (0 : U32))), flat)
      +last = U32.is_eq(col, mask)
      +next_at = Bool.pick(U32, last, U32.add(at, size), U32.add(at, (1 : U32)))
      uniform.go(r, pixels[next_at], next_at, Bool.pick(U32, last, (0 : U32), U32.add(col,
        (1 : U32))), Bool.pick(U32, last, U32.add(row, (1 : U32)), row), side, size, next_ref,
        kept, next_flat)

def uniform_of.done(remaining: Nat, +side: U32, +size: U32, answer: (Array<U32> & U32) & U32) ->
  U32:
  (kept, count) = answer
  count

def uniform_of.at(+side: U32, +size: U32, read: Array<U32> & U32) -> U32:
  uniform_of.done(U32.to_nat(U32.mul(size, size)), side, size, uniform.go(
    U32.to_nat(U32.mul(size, size)), read, (0 : U32), (0 : U32), (0 : U32), side, size,
    (0 : U32), True{}, (0 : U32)))

def uniform_of(+side: U32, +size: U32, pixels: Array<U32>) -> U32:
  uniform_of.at(side, size, pixels[0])

# Two block sides, because collapsing only pays at a size where something is uniform and one
# number cannot say whether that is 8 or 32. Each walk needs its own handle, and an `Array` is
# a `Type`, so the two are forked apart rather than shared.
def uniform_pair.total(+size: U32, +side: U32) -> U32:
  U32.mul(U32.div(size, side), U32.div(size, side))

def uniform_pair.at(+size: U32, +fine: U32, +coarse: U32) -> String:
  "uniform s8=" ++ U32.show(fine) ++ "/" ++ U32.show(uniform_pair.total(size, (8 : U32)))
    ++ " s32=" ++ U32.show(coarse) ++ "/" ++ U32.show(uniform_pair.total(size, (32 : U32)))

def uniform_pair(for_fine: Array<U32>, for_coarse: Array<U32>, +size: U32) -> String:
  uniform_pair.at(size, uniform_of((8 : U32), size, for_fine),
    uniform_of((32 : U32), size, for_coarse))

# The control: a frame of one colour must report every block as uniform, and it is asked over
# many blocks rather than one, so a walk that only ever examined the first cannot pass.
def uniform_control.at(+side: U32, +size: U32, +flat: U32) -> U32:
  flat

def uniform_control(+side: U32, +depth: Nat, +size: U32) -> U32:
  uniform_control.at(side, size, uniform_of(side, size,
    Array.new(U32, Nat.mul(2n, depth), (305419896 : U32))))

# ---------------------------------------------------------------------------
# The read-back's own gate, and the ordering a painter needs.
#
# --- ordering ------------------------------------------------------------------
#
# Ordering is what lets the painter drop a depth buffer. Two axis-aligned unit faces on the
# integer lattice never interpenetrate: they share at most an edge, and the projection of a
# plane is injective, so two faces either do not overlap on screen at all or one of them is
# in front of the other over the whole of the overlap. Order the faces back to front once and
# the last write to a pixel is the nearest face covering it, exactly as a depth test would
# decide. That argument is about geometry, not about this scene; whether it holds here is
# measured by `agree_at`, not assumed.
#
# The key is each face's *farthest* corner in camera space rather than its centre. A centre
# key mis-orders two overlapping faces whenever the nearer face's centre is further from the
# eye than the farther one's, which is what a face at a grazing angle does. The farthest
# corner is a valid key because a face wholly in front of another has a smaller farthest
# corner, and two faces whose farthest corners are equal are touching, not overlapping.

type Keyed is Data:
  Keyed{key: F32, face: Face.Face}

def key_of(k: Keyed) -> F32:
  match k:
    case Keyed{key, face}:
      key

def face_of(k: Keyed) -> Face.Face:
  match k:
    case Keyed{key, face}:
      face

# Ascending by depth, so the far faces sort last and the near ones are written last.
def keyed.less(a: Keyed, b: Keyed) -> Bool:
  F32.is_lt(key_of(a), key_of(b))

# One step along an axis, toward whichever end of it the camera looks at.
def far_step(+along: F32) -> F32:
  Bool.pick(F32, F32.is_gt(along, 0.0), 1.0, 0.0)

# The farthest corner of the face whose plane is `plane` on `axis`. A face is a unit square
# on the lattice, so the far end of each of its three axes is independent of the other two
# and the corner is three adds away; no projection is needed to find it, which is what makes
# the key cheap enough to sort 1,654 faces by every frame.
def far_corner.x(+plane: F32, +fx: F32, +fy: F32, +fz: F32, +eye: Voxel.Vec,
  +forward: Voxel.Vec) -> F32:
  Face.dot3(forward, Voxel.Vec{F32.add(plane, far_step(Face.vx(forward))),
    F32.add(fy, far_step(Face.vy(forward))), F32.add(fz, far_step(Face.vz(forward)))})

def far_corner.y(+plane: F32, +fx: F32, +fy: F32, +fz: F32, +eye: Voxel.Vec,
  +forward: Voxel.Vec) -> F32:
  Face.dot3(forward, Voxel.Vec{F32.add(fx, far_step(Face.vx(forward))),
    F32.add(plane, far_step(Face.vy(forward))), F32.add(fz, far_step(Face.vz(forward)))})

def far_corner.z(+plane: F32, +fx: F32, +fy: F32, +fz: F32, +eye: Voxel.Vec,
  +forward: Voxel.Vec) -> F32:
  Face.dot3(forward, Voxel.Vec{F32.add(fx, far_step(Face.vx(forward))),
    F32.add(fy, far_step(Face.vy(forward))), F32.add(plane, far_step(Face.vz(forward)))})

def far_corner.at(axis: Nat, +plane: F32, +fx: F32, +fy: F32, +fz: F32, +eye: Voxel.Vec,
  +forward: Voxel.Vec) -> F32:
  match axis:
    case 0n:
      far_corner.x(plane, fx, fy, fz, eye, forward)
    case 1n:
      far_corner.y(plane, fx, fy, fz, eye, forward)
    case _:
      far_corner.z(plane, fx, fy, fz, eye, forward)

def depth_key.at(+dir: Nat, +fx: F32, +fy: F32, +fz: F32, +eye: Voxel.Vec,
  +forward: Voxel.Vec) -> F32:
  far_corner.at(Face.axis_of(dir), Face.plane_of(dir, fx, fy, fz), fx, fy, fz, eye, forward)

def keyed.go(faces: List<&2, Face.Face>, +eye: Voxel.Vec, +forward: Voxel.Vec) ->
  List<&2, Keyed>:
  match faces:
    case Nil{}:
      Nil{}
    case Face.Face{fx, fy, fz, dir, block} <> rest:
      +label : Nat = dir
      +x : U32 = fx
      +y : U32 = fy
      +z : U32 = fz
      +cx : F32 = U32.to_f32(x)
      +cy : F32 = U32.to_f32(y)
      +cz : F32 = U32.to_f32(z)
      Keyed{depth_key.at(label, cx, cy, cz, eye, forward),
        Face.Face{x, y, z, label, block}} <> keyed.go(rest, eye, forward)

def faces_of(keyed: List<&2, Keyed>) -> List<&2, Face.Face>:
  match keyed:
    case Nil{}:
      Nil{}
    case Keyed{key, face} <> rest:
      face <> faces_of(rest)

def ordered(faces: List<&2, Face.Face>, +eye: Voxel.Vec, +forward: Voxel.Vec) ->
  List<&2, Face.Face>:
  faces_of(List.sort(~Keyed, ~keyed.less, keyed.go(faces, eye, forward)))

# --- the driver ---------------------------------------------------------------

# `half` and `focal` are the projection the renderer at this depth uses, so the quads here
# are the same quads `bucket_faces` would project.
def half_at(depth: Nat) -> F32:
  Voxel.projection_half(depth)

def focal_at(depth: Nat) -> F32:
  F32.mul(1.5, half_at(depth))

def camera_of_pose(pose: Frame.Pose, depth: Nat) -> Voxel.Camera:
  camera_of(pose)

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# The read-back: the frame the painter wrote, folded into the `Image` quadtree.
#
# `output_probe.bend` prices that quadtree built from a *constant*, which is the shape the
# runtime's own output costs. A painter does not have the constant: it has to read
# `size * size` values back out of the array and turn each into a `Pix`. That read is what
# this fold measures, and it is the last unpriced term in the painter's cost.
#
# What this fold costs, and why, is the most useful thing the probe has found. A handle is a
# refcount on cells every branch shares, so a fork inside a parallel let is an atomic on one
# line that eight cores are writing. Measured at 1024x1024: a constant build of the very
# same tree is 4.5 ms, and this fold is 79 ms. Nothing about the pixels got more expensive;
# the sharing did. Twelve forks per node over 1.4 million nodes is where the 75 ms goes.
#
# Three forks per node is the floor for a four-way fan-out over a value that cannot be
# shared, and the language cannot reach it: a `match` may not be preceded by a destructuring
# statement, so the four handles a fork produces cannot be named inside the def that matches
# the level, and a helper that could name them would have to call the matcher back.
#
# Collapsing a node to one `Pix` when all four of its children agree would remove both the
# allocations and the recursion, and the runtime reads a `Pix` at any level by filling the
# whole block with it, so a shallower tree is the same picture. It is done here, bottom-up,
# which is why it changed nothing: by the time a node learns its children agree, the forks are
# paid. To save the forks the test has to come *before* the fan-out.
#
# An earlier note here said that testing before the fan-out is impossible because a strided
# walk cannot thread a linear handle through a loop in this language. That was wrong, and the
# uniformity walk above is the disproof: a handle threads fine when the read pair is carried as
# a parameter and the next pixel is passed as a call in argument position. The constraint that
# is real is narrower. The scan's answer is a pair, and a call's result cannot be destructured
# where it is written, so the parent cannot split a scan into the two arguments the child's
# call needs without a helper — and a helper that opens the scan and then fans out is a cycle,
# because the fan-out's four branches are the recursion. So the scan has to return a single
# `U32` (the colour if the region is uniform, a sentinel if not) that the caller can use twice
# without splitting, and the parent has to pay one extra fork per child to keep a handle for
# the scan while still handing a handle to the child. That is the shape to build next.
# ---------------------------------------------------------------------------

# A node's four handles, as two pairs. `Array` is a `Type` and Bend's only sharing
# quantifier, `+`, is for `Data`, so one handle cannot be handed to four parallel calls the
# way `const_image` hands its `+color: U32` to four of them, and threading one handle
# through four sequential calls is a helper cycle this language does not have. `Array.fork`
# is the way round both: a second handle to the same cells in O(1).
def fork4.done(left: Array<U32> & Array<U32>, right: Array<U32> & Array<U32>) ->
  (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>):
  (tl, bl) = left
  (tr, br) = right
  ((tl, tr), (bl, br))

def fork4.at(pair: Array<U32> & Array<U32>) ->
  (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>):
  (top, bottom) = pair
  fork4.done(Array.fork(U32, top), Array.fork(U32, bottom))

def fork4(pixels: Array<U32>) -> (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>):
  fork4.at(Array.fork(U32, pixels))

# A subtree, with the two facts a parent needs to collapse it: the colour of the first pixel
# it read, and whether every pixel under it is that colour.
type Flat is Data:
  Flat{image: Image, color: U32, uniform: Bool}

def flat.leaf(read: Array<U32> & U32) -> Flat:
  (_, +value) = read
  Flat{Pix{value}, value, True{}}

# A node's four children: one `Qua`, or one `Pix` when they agree.
def flat.join.at(image: Image, +color: U32, all: Bool, same: Bool) -> Flat:
  match all:
    case True{}:
      match same:
        case True{}:
          Flat{Pix{color}, color, True{}}
        case False{}:
          Flat{image, color, False{}}
    case False{}:
      Flat{image, color, False{}}

def flat.join.same(+ca: U32, cb: U32, cc: U32, cd: U32) -> Bool:
  Bool.and(Bool.and(U32.is_eq(ca, cb), U32.is_eq(ca, cc)), U32.is_eq(ca, cd))

def flat.join.all(ua: Bool, ub: Bool, uc: Bool, ud: Bool) -> Bool:
  Bool.and(Bool.and(ua, ub), Bool.and(uc, ud))

def flat.join.at2(image: Image, +color: U32, ua: Bool, ub: Bool, uc: Bool, ud: Bool,
  cb: U32, cc: U32, cd: U32) -> Flat:
  flat.join.at(image, color, flat.join.all(ua, ub, uc, ud),
    flat.join.same(color, cb, cc, cd))

def flat.join(a: Flat, b: Flat, c: Flat, d: Flat) -> Flat:
  Flat{ia, ca, ua} = a
  Flat{ib, cb, ub} = b
  Flat{ic, cc, uc} = c
  Flat{id, cd, ud} = d
  flat.join.at2(Qua{ia, ib, ic, id}, ca, ua, ub, uc, ud, cb, cc, cd)

# The three offsets a node's four quadrants sit at, given the half-width `shift`.
def fold.across(+base: U32, +shift: U32) -> U32:
  U32.add(base, shift)

def fold.down(+base: U32, +stride: U32, +shift: U32) -> U32:
  U32.add(base, U32.mul(shift, stride))

def fold.corner(+base: U32, +stride: U32, +shift: U32) -> U32:
  fold.across(fold.down(base, stride, shift), shift)

# One of a node's four handles. Any of them reads the same cells, so the leaf takes the
# first and the other three are dropped; a `get` moves no handle, so dropping is a refcount
# and nothing else.
def flat.leaf.handle(four: (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>)) ->
  Array<U32>:
  (left, _) = four
  (top, _) = left
  top

# One node of the quadtree, reading the `size * size` frame row-major. `base` is the flat
# index of the node's top-left pixel and `size` is the root's row stride, which every level
# keeps: the stride belongs to the array, not to the node.
def fold.go(+q: Nat, +base: U32, +size: U32,
  four: (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>)) -> Flat:
  match q:
    case 0n:
      flat.leaf(Array.get(U32, flat.leaf.handle(four), base))
    case 1n+r:
      (left, right) = four
      (tl, bl) = left
      (tr, br) = right
      a b c d = fold.go(r, base, size, fork4(tl))
        fold.go(r, fold.across(base, U32.shln((1 : U32), r)), size, fork4(tr))
        fold.go(r, fold.down(base, size, U32.shln((1 : U32), r)), size, fork4(bl))
        fold.go(r, fold.corner(base, size, U32.shln((1 : U32), r)), size, fork4(br))
      flat.join(a, b, c, d)

def image.of(flat: Flat) -> Image:
  match flat:
    case Flat{image, color, uniform}:
      image

# The frame as the quadtree `Window.frame` takes.
def fold_frame(+depth: Nat, pixels: Array<U32>) -> Image:
  image.of(fold.go(depth, (0 : U32), frame_size(depth), fork4(pixels)))

# ---------------------------------------------------------------------------
# The fold's own gate.
#
# The index arithmetic is the one part of the painter with no visible failure when it is
# wrong: a mis-addressed pixel still produces a full-depth quadtree, still fills the window,
# and still has a fingerprint. So it is checked against an array whose contents are a known
# function of the index. Every pixel `(x, y)` of the folded image must read back as
# `tint(y * size + x)`, which is what the array was filled with, so a swapped quadrant, a
# wrong stride or a wrong tree depth all show up as a mismatch at the pixel that moved.
#
# The comparison has to be per pixel rather than by fingerprint, because the fold collapses a
# uniform node to a single `Pix` and a one-colour frame therefore folds to one node, not to
# a full tree. Both are the same picture; only the shape differs, and only the picture is
# worth asserting.
# ---------------------------------------------------------------------------

def image.child.tl(image: Image) -> Image:
  match image:
    case Pix{color}:
      Pix{color}
    case Qua{tl, tr, bl, br}:
      tl

def image.child.tr(image: Image) -> Image:
  match image:
    case Pix{color}:
      Pix{color}
    case Qua{tl, tr, bl, br}:
      tr

def image.child.bl(image: Image) -> Image:
  match image:
    case Pix{color}:
      Pix{color}
    case Qua{tl, tr, bl, br}:
      bl

def image.child.br(image: Image) -> Image:
  match image:
    case Pix{color}:
      Pix{color}
    case Qua{tl, tr, bl, br}:
      br

def image.child(j: U32, image: Image) -> Image:
  match j:
    case 0:
      image.child.tl(image)
    case 1:
      image.child.tr(image)
    case 2:
      image.child.bl(image)
    case _:
      image.child.br(image)

# Which quadrant of a level-`level` node holds pixel (x, y): `window_sq` places child `j` at
# (x + j%2, y + j/2), so the index is the x bit plus twice the y bit.
def quadrant_of(+x: U32, +y: U32, +level: Nat) -> U32:
  U32.add(U32.and(U32.shrn(x, level), (1 : U32)),
    U32.shl(U32.and(U32.shrn(y, level), (1 : U32))))

# One pixel out of an `Image`, following the same child order the runtime does. The depth is
# an upper bound, not a requirement: a collapsed node is a `Pix` above it and the descent
# stops there, which is what makes a pruned tree readable at all.
def image.pixel(+x: U32, +y: U32, +depth: Nat, image: Image) -> U32:
  match depth image:
    case 0n Pix{color}:
      color
    case 0n Qua{tl, tr, bl, br}:
      image.pixel(x, y, 0n, tl)
    case 1n+r Pix{color}:
      color
    case 1n+r Qua{tl, tr, bl, br}:
      image.pixel(x, y, r, image.child(quadrant_of(x, y, r), Qua{tl, tr, bl, br}))

# The contents of the array under the check: injective in the index, so a wrong address is a
# wrong colour and not a coincidence.
def tint(i: U32) -> U32:
  U32.add(U32.mul(i, (2654435761 : U32)), (7 : U32))

def fold_check.next_x(+x: U32, +size: U32) -> U32:
  Bool.pick(U32, U32.is_lt(U32.add(x, (1 : U32)), size), U32.add(x, (1 : U32)), (0 : U32))

def fold_check.next_y(+x: U32, +y: U32, +size: U32) -> U32:
  Bool.pick(U32, U32.is_lt(U32.add(x, (1 : U32)), size), y, U32.add(y, (1 : U32)))

def fold_check.px(remaining: Nat, +x: U32, +y: U32, +size: U32, +depth: Nat, +image: Image) ->
  Bool:
  match remaining:
    case 0n:
      True{}
    case 1n+r:
      Bool.and(
        U32.is_eq(image.pixel(x, y, depth, image), tint(U32.add(U32.mul(y, size), x))),
        fold_check.px(r, fold_check.next_x(x, size), fold_check.next_y(x, y, size), size, depth,
          image))

# The array under the check, filled with `tint(index)`. `Array.map` would be the obvious way
# to write it and is the wrong one: it allocates `Array.new(U, log2(n), v)`, which is `n * n`
# slots, so at 256-square it asks for four billion of them. A loop is a few hundred
# microseconds and asks for exactly the frame.
def fill.tint(remaining: Nat, +i: U32, frame: Array<U32>) -> Array<U32>:
  match remaining:
    case 0n:
      frame
    case 1n+r:
      fill.tint(r, U32.inc(i), frame[i] <- tint(i))

def frame_of(+depth: Nat) -> Array<U32>:
  +size : U32 = frame_size(depth)
  fill.tint(U32.to_nat(U32.mul(size, size)), (0 : U32), Array.new(U32, Nat.mul(2n, depth),
    (0 : U32)))

# The fold of a `size * size` frame of `tint(index)`, read back one pixel at a time.
def fold_check.at(+depth: Nat) -> Bool:
  +size : U32 = frame_size(depth)
  fold_check.px(Nat.mul(U32.to_nat(size), U32.to_nat(size)), (0 : U32), (0 : U32), size, depth,
    fold_frame(depth, frame_of(depth)))

def fold_check(top: Nat, +depth: Nat, +first_bad: Nat) -> Nat:
  match top:
    case 0n:
      first_bad
    case 1n+r:
      fold_check(r, Nat.add(depth, 1n), Bool.pick(Nat, fold_check.at(depth), first_bad, depth))

def sampled(pixels: Array<U32>, +size: U32) -> Array<U32> & U32:
  pixels[U32.add(U32.div(size, (2 : U32)), size)]

def print_line(+line: String) -> IO(Unit):
  do IO<Unit>:
    IO.print(line)

# The fill's line: what the geometry costs on its own.
def fill_line(+label: String, +size: U32, +iterations: Nat, +started: Nat, +finished: Nat,
  +seen: U32, +tally: Counted) -> String:
  "phase=" ++ label ++ " size=" ++ U32.show(size)
    ++ " pixels=" ++ U32.show(U32.mul(size, size))
    ++ " spans=" ++ U32.show(counted_spans(tally))
    ++ " spanpixels=" ++ U32.show(counted_pixels(tally))
    ++ " iterations=" ++ Nat.show(iterations)
    ++ " fill_ms=" ++ Nat.show(Nat.sub(finished, started))
    ++ " per_fill_ms=" ++ Nat.show(Nat.div(Nat.sub(finished, started), iterations))
    ++ " sampled=" ++ U32.show(seen)

# The fill's line with the read-back beside it. `fold_ms` is the quadtree build reading the
# painter's frame, and `total_ms` is the painter's whole cost so far, before any depth test
# or ordering.
def fold_line(label: String, +size: U32, +iterations: Nat, +started: Nat, +ordered_at: Nat,
  +filled_at: Nat, +folded_at: Nat, +seen: U32, +tally: Counted) -> String:
  fill_line(label, size, iterations, started, filled_at, seen, tally)
    ++ " order_ms=" ++ Nat.show(Nat.sub(ordered_at, started))
    ++ " fold_ms=" ++ Nat.show(Nat.sub(folded_at, filled_at))
    ++ " total_ms=" ++ Nat.show(Nat.sub(folded_at, started))

# The fill and the fold, timed separately, because they are separately improvable: the fill
# is geometry-bound and the fold is allocation-bound. The sum is what a painter costs. The
# image is fingerprinted before it is released, so the fold cannot be elided.
def report_fold.print(+line: String, +uniforms: String) -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- print_line(line)
    IO.print(uniforms)

def report_fold.at(+label: String, +size: U32, +iterations: Nat, +started: Nat,
  +ordered_at: Nat, +filled_at: Nat, +folded_at: Nat, tally: Counted, +seen: U32,
  +image: Image, +uniforms: String) -> IO(Unit):
  +line : String = fold_line(label, size, iterations, started, ordered_at, filled_at, folded_at,
    seen, tally)
  +digest : U32 = Voxel.fingerprint(image)
  released : Unit = Image.drop(image)
  report_fold.print(line ++ " fingerprint=" ++ U32.show(digest), uniforms)

def report_fold(+label: String, +size: U32, +iterations: Nat, +started: Nat, +ordered_at: Nat,
  +filled_at: Nat, +folded_at: Nat, tally: Counted, done: (Image & U32) & String) -> IO(Unit):
  (answer, uniforms) = done
  (image, seen) = answer
  report_fold.at(label, size, iterations, started, ordered_at, filled_at, folded_at, tally,
    seen, image, uniforms)

# The sample read and the fold, in one def, because a destructuring statement may only
# scrutinize a parameter, so the pair has to arrive as one and be opened here.
# The fold, the sample read and the two uniformity walks all want the same frame, and a handle
# is linear, so they are given forked handles rather than a shared one. The fork's products are
# passed straight through as parameters, which is the only way to open them: a destructuring
# statement may not open a call's result. Three handles, nested two deep.
def fold_and_sample.image(+depth: Nat, +size: U32, for_fine: Array<U32>,
  for_coarse: Array<U32>, probe: Array<U32> & U32) -> (Image & U32) & String:
  (rest, seen) = probe
  ((fold_frame(depth, rest), seen), uniform_pair(for_fine, for_coarse, size))

def fold_and_sample.go(+depth: Nat, +size: U32, for_fold: Array<U32>, for_fine: Array<U32>,
  for_coarse: Array<U32>) -> (Image & U32) & String:
  fold_and_sample.image(depth, size, for_fine, for_coarse,
    for_fold[U32.add(U32.div(size, (2 : U32)), size)])

# Three handles to one frame. `Array.fork`'s product cannot be forked again where it is
# written, so the second fork happens in a def that can bind the first one's halves.
def fork3.at(left: Array<U32> & Array<U32>, right: Array<U32>) ->
  (Array<U32> & Array<U32>) & Array<U32>:
  (left, right)

def fork3.pair(pair: Array<U32> & Array<U32>) -> (Array<U32> & Array<U32>) & Array<U32>:
  (kept, spare) = pair
  fork3.at(Array.fork(U32, kept), spare)

def fork3(pixels: Array<U32>) -> (Array<U32> & Array<U32>) & Array<U32>:
  fork3.pair(Array.fork(U32, pixels))

def fold_and_sample(+depth: Nat, +size: U32,
  pair: (Array<U32> & Array<U32>) & Array<U32>) -> (Image & U32) & String:
  (walks, for_fold) = pair
  (for_fine, for_coarse) = walks
  fold_and_sample.go(depth, size, for_fold, for_fine, for_coarse)

# The camera's four basis vectors, unpacked once from the camera record. The tally's entry
# point is the same shape as the fill's, so the two folds below are called the same way.
def tally_of(faces: List<&2, Face.Face>, +camera: Voxel.Camera, +half: F32, +focal: F32,
  size: U32) -> Counted:
  count.go(faces, Face.cam_eye(camera), Face.cam_right(camera), Face.cam_up(camera),
    Face.cam_forward(camera), half, focal, size, counted.zero())

# The camera's four basis vectors for the fill, unpacked once from the camera record.
def fill.of(faces: List<&2, Face.Face>, +camera: Voxel.Camera, +half: F32, +focal: F32,
  +size: U32, frame: Array<U32>) -> Array<U32>:
  fill.go(faces, Face.cam_eye(camera), Face.cam_right(camera),
    Face.cam_up(camera), Face.cam_forward(camera), half, focal, size, frame)

# The timed fill, repeated enough times for the clock to carry digits.
def fill.rounds(rounds: Nat, +faces: List<&2, Face.Face>, +camera: Voxel.Camera, +half: F32,
  +focal: F32, +size: U32, frame: Array<U32>) -> Array<U32>:
  match rounds:
    case 0n:
      frame
    case 1n+r:
      fill.rounds(r, faces, camera, half, focal, size,
        fill.of(faces, camera, half, focal, size, frame))

# The painter at the size and camera the client renders, repeated enough times for the clock
# to carry digits: one pass at 128x128 is a couple of milliseconds. Ordering is timed once
# and not repeated, because it is a per-frame cost the client pays on a face list that only
# changes when the player does, while the fill is what scales with resolution.
def paint_at(+label: String, +size: U32, +depth: Nat, +iterations: Nat,
  +faces: List<&2, Face.Face>, +pose: Frame.Pose) -> IO(Unit):
  do IO<Unit>:
    +camera : Voxel.Camera = camera_of(pose)
    tally : Counted = tally_of(faces, camera, half_at(depth), focal_at(depth), size)
    frame : Array<U32> = Array.new(U32, slots_of(depth), Voxel.sky_color(U32.sub(size, (1 : U32))))
    started : Nat <- IO.now()
    sorted : List<&2, Face.Face> = ordered(faces, Face.cam_eye(camera),
      Face.cam_forward(camera))
    ordered_at : Nat <- IO.now()
    written : Array<U32> = fill.rounds(iterations, sorted, camera, half_at(depth),
      focal_at(depth), size, frame)
    filled : Nat <- IO.now()
    image_step : (Image & U32) & String = fold_and_sample(depth, size, fork3(written))
    folded : Nat <- IO.now()
    report_fold(label, size, iterations, started, ordered_at, filled, folded, tally, image_step)

# The client resolves the pointer's ray and the frame's spawn pose, so the probe measures
# at exactly the camera the client renders from.
def pose_of(player: Player.State) -> Frame.Pose:
  Frame.pose(player, Frame.origin_x(), Frame.origin_z())

def player_of(maybe: Maybe<&1, Player.State>) -> IO(Player.State):
  match maybe:
    case Some{player}:
      IO.pure(Player.State, player)
    case None{}:
      IO.die(Player.State, 1, "span-probe: the client spawn was refused")

def main() -> IO(Unit):
  do IO<Unit>:
    +edits : List<&2, WorldState.Edit> = WorldState.empty()
    +player : Player.State <- player_of(PlayerProbe.checked_create_player(25n, 25n, 9n))
    +faces : List<&2, Face.Face> = region_faces(edits)
    +pose : Frame.Pose = pose_of(player)
    # 128x128 is what the client ships, and it is the size the walk's cost model above was
    # measured at. 256x256 and 512x512 are the next two steps up, and 1024x1024 is the
    # resolution the goal names.
    a : Unit <- paint_at("paint_128", frame_size(7n), 7n, 200n, faces, pose)
    b : Unit <- paint_at("paint_256", frame_size(8n), 8n, 100n, faces, pose)
    c : Unit <- paint_at("paint_512", frame_size(9n), 9n, 30n, faces, pose)
    d : Unit <- paint_at("paint_1024", frame_size(10n), 10n, 10n, faces, pose)
    IO.print("span-probe=pass faces=" ++ Nat.show(U32.to_nat(Face.face_total(faces))))
    +control : U32 <- IO.pure(U32, uniform_control((8 : U32), 6n, (64 : U32)))
    IO.print("uniform_control size=64 side=8 flat=" ++ U32.show(control) ++ "/64 expect=64")
    +checked : Nat = fold_check(9n, 0n, 99n)
    IO.print("fold_check first_bad_depth=" ++ Nat.show(checked) ++ " checked=0..8")