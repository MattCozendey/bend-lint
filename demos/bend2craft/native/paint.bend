import Base
import ./voxel.bend as Voxel
import ./face.bend as Face
import ./texture.bend as Texture
import ./sky.bend as Sky
import ./shade.bend as Shade

# Paint: the client's renderer, and why it exists
#
# `Face` resolves every pixel by casting a ray and walking the faces whose screen box
# contains it. That is exact — it is the reference `native/face_test.bend` holds itself to
# — and it costs 14.00 ms at 128x128, 44.33 ms at 256x256 and 152.50 ms at 512x512 on the
# machine named in `lab/native/2026-09-30-native-renderer-investigation.md`. The window is
# paced at 60 Hz by `window_pace`, so those are 22 and 6 frames per second.
#
# This module draws the same picture the other way: sort the faces nearest first, project
# each one once into a flat screen polygon, resolve it to an integer span per scanline, and
# let the first write win.
#
# It is not a replacement for `Face`. `Face` still answers the pointer's ray, the tests
# still hold it, and `native/paint_test.bend` holds *this* to `Face` at the same 1% gate.
# What changes is which one draws the window.
#
# ## One painter, and how it is divided
#
# A frame-wide array has one owner, so every write to it is serial and a second thread only
# adds contention. So the frame is drawn in tiles: a fork tree deals the polygons down to
# square tiles, and each tile paints its polygons into an array it creates, writes and folds
# inside one task. Tiles share nothing, and a region no polygon reaches answers its sky
# without an array at all.
#
# The tile edge is a parameter of the same code, so "the whole frame as one tile" is a
# frame this module can draw, and `native/paint_test.bend` holds the tiled frame to it node
# for node. A frame that changed with how it was divided would be a bug in the dealing, and
# that gate is what would say so.
#
# ## The near plane
#
# `Face.project` divides by `max(depth, 0.0001)` (`native/face.bend:467`). That is a clamp,
# not a clip, so a corner behind the eye projects to a coordinate of tens of millions of
# pixels and a face the eye is beside paints a full-width band over everything behind it.
#
# The first rule here was to skip any face with a corner behind the eye. It kept the frame
# right on the cameras the gate measures and it is wrong for a player: the wall you are
# standing against has corners behind you, so it was not drawn, and you walked into
# something the picture said was not there. So a face is now **clipped**: it is cut where it
# crosses a plane a little in front of the eye (`near_plane`), which turns a quad into a
# polygon of three to five corners, and that polygon is what is projected and filled. A face
# wholly in front is projected exactly as before, and a face wholly behind is dropped.
#
# ## The picture is the same picture
#
# Where this and `Face` name the same block and the same face, they write the same colour,
# because both are `Voxel.shade_color(Voxel.block_color(block), dir)`. The pixels where they
# differ are the pixels `native/paint_test.bend` counts.
#
# That is the **flat** frame, which is what the gates hold. The frame a player sees is the
# textured one, and it is the same polygons with more in each pixel: the texel, the light
# the face's corners take (`native/shade.bend`), the hour's light, and the air between the
# eye and the face (`native/sky.bend`). Behind the scene it takes a list of polygons that
# are further than every face, which is how the clouds and the sun get into the picture
# (`native/scenery.bend`) without the painter knowing what they are.

type Span is Data:
  Span{x0: U32, x1: U32}

type Rows is Data:
  Rows{first: U32, stop: U32}

def far() -> F32:
  1.0e30

def near() -> F32:
  F32.neg(1.0e30)

# Where an edge crosses a scanline, and whether it crosses it at all.
#
# The interpolation is linear in *screen* y between the two projected corners, which is an
# approximation the painter accepts: the true perspective crossing is not at that point.
# `native/paint_test.bend` measures what it costs, at 0.3% of the frame on a single cube
# with no overlap and no straddling face, and the alternative — deriving the span from the
# two renderers' actual sampling conventions — was measured and was worse.
#
# Dividing here rather than taking a precomputed slope was measured both ways and made no
# difference: `(bx - ax) / (by - ay)` is loop-invariant over a face's rows, so the C backend
# hoists it, and the measured medians were identical at every size. "A divide per row" is an
# operation count, not a cost.
def crossing_x(+y: F32, +ax: F32, +ay: F32, +bx: F32, +by: F32) -> F32:
  F32.add(ax, F32.mul(F32.div(F32.sub(y, ay), F32.sub(by, ay)), F32.sub(bx, ax)))

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

def span_bounds(+top: F32, +bottom: F32, +size: U32) -> Rows:
  +last = U32.sub(size, (1 : U32))
  +misses = Bool.or(F32.is_ge(top, F32.from_nat(U32.to_nat(size))), F32.is_le(bottom, 0.0))
  +first = Bool.pick(U32, misses, (0 : U32), F32.to_u32(F32.max(F32.floor(top), 0.0)))
  +stop = Bool.pick(U32, misses, first,
    U32.add(F32.to_u32(F32.min(F32.floor(bottom), F32.from_nat(U32.to_nat(last)))),
      (1 : U32)))
  Rows{U32.min(first, last), U32.max(stop, U32.min(first, last))}

def rows_first(r: Rows) -> U32:
  match r:
    case Rows{first, stop}:
      first

def rows_stop(r: Rows) -> U32:
  match r:
    case Rows{first, stop}:
      stop

# The scanline's two integer bounds.
#
# The walk's rule is `left <= px < right`, so the left bound rounds up and the right bound
# rounds down. `ceil` on the right was measured and is worse (the plain cube 3 -> 7, the
# eight-cube row 12 -> 26), and so is the rule derived from the two renderers' sampling
# conventions (`ceil(e4 - 0.5)` to `floor(f4 - 0.5) + 1`, which puts `spawn` at 104 wrong
# blocks instead of 0). The residual is a fraction-of-a-pixel bias on each of a quad's four
# edges, not a misplacement of the window, so moving the window trades one edge for another.
def half_open_bounds(+e4: F32, +f4: F32, +last: F32) -> Span:
  +left = F32.to_u32(F32.ceil(F32.min(F32.max(e4, 0.0), last)))
  +right = F32.to_u32(F32.max(F32.min(f4, last), 0.0))
  Span{left, U32.max(right, left)}

# A row no edge crosses has no span. `Span{1, 0}` is the empty one: its end is before its
# start, so a fill counts zero cells. Without this the bounds of a row nothing crossed
# resolve to the frame's last column, and every polygon whose top is not on a pixel row
# writes one pixel there.
def span_when(crossed: Bool, span: Span) -> Span:
  match crossed:
    case True{}:
      span
    case False{}:
      Span{1, 0}

# The span of a polygon of up to five corners on one row. A quad is the same polygon with
# its last corner repeated: the repeated edge has no height, so it never straddles a row.
def span_edges(+ax: F32, +ay: F32, +bx: F32, +by: F32, +cx: F32, +cy: F32, +dx: F32,
  +dy: F32, +ex: F32, +ey: F32, +y: F32, +size: U32) -> Span:
  +last = F32.from_nat(U32.to_nat(U32.sub(size, (1 : U32))))
  # Each edge's crossing is computed **once** and read by both the left and the right fold.
  +h1 = straddles(y, ay, by)
  +h2 = straddles(y, by, cy)
  +h3 = straddles(y, cy, dy)
  +h4 = straddles(y, dy, ey)
  +h5 = straddles(y, ey, ay)
  +c1 = crossing_x(y, ax, ay, bx, by)
  +c2 = crossing_x(y, bx, by, cx, cy)
  +c3 = crossing_x(y, cx, cy, dx, dy)
  +c4 = crossing_x(y, dx, dy, ex, ey)
  +c5 = crossing_x(y, ex, ey, ax, ay)
  +e1 = keep_left(h1, c1, far())
  +e2 = keep_left(h2, c2, e1)
  +e3 = keep_left(h3, c3, e2)
  +e4 = keep_left(h4, c4, e3)
  +e5 = keep_left(h5, c5, e4)
  +f1 = keep_right(h1, c1, near())
  +f2 = keep_right(h2, c2, f1)
  +f3 = keep_right(h3, c3, f2)
  +f4 = keep_right(h4, c4, f3)
  +f5 = keep_right(h5, c5, f4)
  span_when(Bool.or(Bool.or(h1, h2), Bool.or(h3, Bool.or(h4, h5))),
    half_open_bounds(e5, f5, last))

# How far in front of the eye a face is cut. The player's body keeps the eye further than
# this from any wall it stands against, and at this distance a one-cell face is already
# several frames wide, so nothing a player can see is nearer.
def near_plane() -> F32:
  0.1

# --- the order ---------------------------------------------------------------
#
# The faces are painted nearest first, and the order is by **cell**, not by face: a face is
# keyed by how far its block's centre is from the eye, summed along the three axes.
#
# That order is exact for blocks on a grid. A block can only hide another if it lies between
# it and the eye, and along any ray from the eye the cells get no nearer on any axis as the
# ray goes out, so the hiding block's distance is smaller on at least one axis and no larger
# on the others: its sum is smaller by at least one whole cell. Two blocks whose sums are
# closer than that cannot hide each other, so the order between them does not matter.
#
# The key this replaced was each face's own farthest corner along the view. That is a
# partial order — two faces that meet along an edge share a corner and tie — and a tie let a
# far face paint over a near one, which showed as faces a player could see through.
#
# ## What is not ordered at all
#
# Four kinds of face are dropped before they are projected, because nothing they could paint
# would be seen:
#
# - a face wholly behind the near plane, which would not be drawn;
# - a face outside the view: the frame is as wide as two thirds of the distance ahead, so
#   a block further to the side or above or below than that, with room for its own size,
#   has no pixel in the frame. With the eye in the middle of a region that is most of it;
# - a face turned away from the eye. The same block's faces that are turned toward the eye
#   cover it from nearer, so it paints nothing. That holds while the eye is outside the
#   block, which the player's body keeps it. An eye inside a solid block sees none of that
#   block's faces, and `native/paint_test.bend` has a camera there to say what that costs;
# - in the textured frame, a face past the end of the air, which would be painted in the
#   colour the sky behind it already is.

def far_step(+along: F32) -> F32:
  Bool.pick(F32, F32.is_gt(along, 0.0), 1.0, 0.0)

def far_corner.x(+plane: F32, +fx: F32, +fy: F32, +fz: F32, +forward: Voxel.Vec) -> F32:
  Face.dot3(forward, Voxel.Vec{F32.add(plane, far_step(Face.vx(forward))),
    F32.add(fy, far_step(Face.vy(forward))), F32.add(fz, far_step(Face.vz(forward)))})

def far_corner.y(+plane: F32, +fx: F32, +fy: F32, +fz: F32, +forward: Voxel.Vec) -> F32:
  Face.dot3(forward, Voxel.Vec{F32.add(fx, far_step(Face.vx(forward))),
    F32.add(plane, far_step(Face.vy(forward))), F32.add(fz, far_step(Face.vz(forward)))})

def far_corner.z(+plane: F32, +fx: F32, +fy: F32, +fz: F32, +forward: Voxel.Vec) -> F32:
  Face.dot3(forward, Voxel.Vec{F32.add(fx, far_step(Face.vx(forward))),
    F32.add(fy, far_step(Face.vy(forward))), F32.add(plane, far_step(Face.vz(forward)))})

def far_corner.at(axis: Nat, +plane: F32, +fx: F32, +fy: F32, +fz: F32,
  +forward: Voxel.Vec) -> F32:
  match axis:
    case 0n:
      far_corner.x(plane, fx, fy, fz, forward)
    case 1n:
      far_corner.y(plane, fx, fy, fz, forward)
    case _:
      far_corner.z(plane, fx, fy, fz, forward)

# Whether the eye is on the open side of a face: past the plane the face lies in, on the
# side its label points to. `emit_sides` labels the sides 0/+x, 1/+y, 2/+z, 3/-x, 4/-y, 5/-z.
def faces_eye(dir: Nat, +fx: F32, +fy: F32, +fz: F32, ex: F32, ey: F32, ez: F32) -> Bool:
  match dir:
    case 0n:
      F32.is_gt(ex, F32.add(fx, 1.0))
    case 1n:
      F32.is_gt(ey, F32.add(fy, 1.0))
    case 2n:
      F32.is_gt(ez, F32.add(fz, 1.0))
    case 3n:
      F32.is_lt(ex, fx)
    case 4n:
      F32.is_lt(ey, fy)
    case _:
      F32.is_lt(ez, fz)

def cell_distance(+fx: F32, +fy: F32, +fz: F32, eye: Voxel.Vec) -> F32:
  Voxel.Vec{ex, ey, ez} = eye
  F32.add(F32.add(F32.abs(F32.sub(F32.add(fx, 0.5), ex)),
    F32.abs(F32.sub(F32.add(fy, 0.5), ey))), F32.abs(F32.sub(F32.add(fz, 0.5), ez)))

# Half a block's diagonal, rounded up: every point of a block's faces is within this of the
# block's centre, along any direction.
def block_reach() -> F32:
  0.9

# Whether a block can have a pixel in the frame, from its centre in view space: `ahead`
# along the view and `aside` across it or up it. The frame's edge is `half / focal` of the
# distance ahead, which is two thirds, and the block's own reach is allowed on both.
def in_view(+ahead: F32, +aside: F32) -> Bool:
  F32.is_le(F32.abs(aside),
    F32.add(F32.mul(F32.add(ahead, block_reach()), 0.66667), block_reach()))

def cell_seen(+c: Voxel.Vec, +right: Voxel.Vec, +up: Voxel.Vec, +forward: Voxel.Vec) -> Bool:
  Bool.and(in_view(Face.dot3(forward, c), Face.dot3(right, c)),
    in_view(Face.dot3(forward, c), Face.dot3(up, c)))

def centre_from(+fx: F32, +fy: F32, +fz: F32, eye: Voxel.Vec) -> Voxel.Vec:
  Voxel.Vec{ex, ey, ez} = eye
  Voxel.Vec{F32.sub(F32.add(fx, 0.5), ex), F32.sub(F32.add(fy, 0.5), ey),
    F32.sub(F32.add(fz, 0.5), ez)}

# Whether a block is in the frame and near enough to be seen through the air: `reach` is the
# square of how far that is, and a block past it would be painted in the colour of the air,
# which is what the sky behind it already is.
def cell_shown(+c: Voxel.Vec, +right: Voxel.Vec, +up: Voxel.Vec, +forward: Voxel.Vec,
  reach: F32) -> Bool:
  Bool.and(F32.is_le(Face.dot3(c, c), reach), cell_seen(c, right, up, forward))

# How far a face is kept, squared: to the end of the air when the scene is seen through it,
# and without end for the flat frame, which has no air.
def reach_of(textured: Bool) -> F32:
  match textured:
    case True{}:
      Sky.fog_reach()
    case False{}:
      far()

# --- the quadtree ------------------------------------------------------------
#
# A node collapses to a single `Pix` when its four children agree, because the runtime
# fills a `Pix` at any level with one colour and a uniform node is then one allocation
# instead of four.
type Flat is Data:
  Flat{image: Image, color: U32, uniform: Bool}

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

def flat.join.at2(image: Image, +color: U32, ua: Bool, ub: Bool, uc: Bool, ud: Bool,
  +cb: U32, +cc: U32, +cd: U32) -> Flat:
  flat.join.at(image, color, Bool.and(Bool.and(ua, ub), Bool.and(uc, ud)),
    Bool.and(U32.is_eq(cb, color), Bool.and(U32.is_eq(cc, color), U32.is_eq(cd, color))))

def flat.join(a: Flat, b: Flat, c: Flat, d: Flat) -> Flat:
  Flat{ia, ca, ua} = a
  Flat{ib, cb, ub} = b
  Flat{ic, cc, uc} = c
  Flat{id, cd, ud} = d
  flat.join.at2(Qua{ia, ib, ic, id}, ca, ua, ub, uc, ud, cb, cc, cd)

def image.of(flat: Flat) -> Image:
  match flat:
    case Flat{image, color, uniform}:
      image

# --- the polygons --------------------------------------------------------------
#
# What a polygon is painted with. `tex` is 0 for one flat `color`. Otherwise it is
# `block * 8 + side`, and the nine numbers are the face's own plane as three functions of a
# pixel — `d`, `u` and `v`, each `c0 + cx * x + cy * y` — such that `u / d` and `v / d` are
# where on the face the pixel looks, across and down, from 0 to 1. A division per pixel is
# what makes the texture lie on the face in perspective instead of sliding across it.
#
# `tex` also carries the four corner levels of the face above bit 11, as `Shade` packs them,
# and the hour's light above bit 27. `fog` is the plane of the face as depth: the depth a
# pixel sees is `fog / d` over a constant, which is how much air is in front of it. A
# textured ink's `color` is the colour of that air.
type Ink is Data:
  Ink{color: U32, tex: U32, d0: F32, dx: F32, dy: F32, u0: F32, ux: F32, uy: F32, v0: F32,
    vx: F32, vy: F32, fog: F32}

# A face projected once: up to five screen corners, what it is painted with, the rows it
# covers and the columns it can touch. The list is what the fork tree deals and what a tile
# walks.
type Quads is Data:
  QNil{}
  QCons{ax: F32, ay: F32, bx: F32, by: F32, cx: F32, cy: F32, dx: F32, dy: F32, ex: F32,
    ey: F32, ink: Ink, first: U32, stop: U32, left: U32, right: U32, next: Quads}

# What a node of the fork tree is handed: the quads that reach it, or its four quarters
# already dealt. They are one type because a `def` may only call itself, and dealing has to
# hand its four lists back to the def that forks on them.
type Work is Data:
  Whole{quads: Quads}
  Dealt{a: Quads, b: Quads, c: Quads, d: Quads}

# The quarters a tile's fold has finished and not yet joined, newest first.
type Stack is Data:
  PNil{}
  PCons{image: Image, color: U32, uniform: Bool, next: Stack}

type Fold is Type:
  Fold{frame: Array<U32>, stack: Stack}

# A corner in view space: across, up, and along the view.
type V is Data:
  V{x: F32, y: F32, z: F32}

type Vs is Data:
  VNil{}
  VCons{x: F32, y: F32, z: F32, next: Vs}

# The tile edge as a power of two, chosen by `lab/native/paint/run.sh` on the machine named
# in `lab/native/2026-09-30-native-renderer-investigation.md`. One 1024x1024 draw, in
# milliseconds:
#
#   edge    1 thread    8 threads
#     16      15.85        4.22
#     32      13.32        3.52
#     64      11.75        3.05
#    128      10.93        2.98
#
# 64 and 128 are within the noise of each other at 1024. 64 is kept because it is the smaller
# of the two flat ones: a 512 window is 64 tiles rather than 16, so the pool has work to
# divide at the sizes below the largest.
def tile_log() -> Nat:
  6n

def tile_of(+depth: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_lt(depth, tile_log()), depth, tile_log())

def flat_ink(color: U32) -> Ink:
  Ink{color, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}

def quads.keep(keep: Bool, ax: F32, ay: F32, bx: F32, by: F32, cx: F32, cy: F32, dx: F32,
  dy: F32, ex: F32, ey: F32, ink: Ink, first: U32, stop: U32, left: U32, right: U32,
  next: Quads) -> Quads:
  match keep:
    case True{}:
      QCons{ax, ay, bx, by, cx, cy, dx, dy, ex, ey, ink, first, stop, left, right, next}
    case False{}:
      next

def min5(+a: F32, +b: F32, +c: F32, +d: F32, +e: F32) -> F32:
  F32.min(F32.min(F32.min(a, b), F32.min(c, d)), e)

def max5(+a: F32, +b: F32, +c: F32, +d: F32, +e: F32) -> F32:
  F32.max(F32.max(F32.max(a, b), F32.max(c, d)), e)

# The rows a polygon covers and the columns it can touch. Every crossing `span_edges`
# computes lies between the leftmost and the rightmost corner, so the column box is
# conservative, and a polygon that covers no row is not kept.
def quads.boxed(+ax: F32, +ay: F32, +bx: F32, +by: F32, +cx: F32, +cy: F32, +dx: F32,
  +dy: F32, +ex: F32, +ey: F32, +rows: Rows, +size: U32, ink: Ink, next: Quads) -> Quads:
  +last = U32.to_f32(U32.sub(size, (1 : U32)))
  quads.keep(U32.is_lt(rows_first(rows), rows_stop(rows)), ax, ay, bx, by, cx, cy, dx, dy,
    ex, ey, ink, rows_first(rows), rows_stop(rows),
    F32.to_u32(F32.floor(F32.min(F32.max(min5(ax, bx, cx, dx, ex), 0.0), last))),
    F32.to_u32(F32.ceil(F32.min(F32.max(max5(ax, bx, cx, dx, ex), 0.0), last))), next)

def quads.at(+ax: F32, +ay: F32, +bx: F32, +by: F32, +cx: F32, +cy: F32, +dx: F32, +dy: F32,
  +ex: F32, +ey: F32, +size: U32, ink: Ink, next: Quads) -> Quads:
  quads.boxed(ax, ay, bx, by, cx, cy, dx, dy, ex, ey,
    span_bounds(min5(ay, by, cy, dy, ey), max5(ay, by, cy, dy, ey), size), size, ink, next)

# A face wholly in front of the near plane: its four projected corners as they are, with
# the last one repeated.
def quads.of(square: Face.Square, +size: U32, ink: Ink, next: Quads) -> Quads:
  Face.Square{a, b, c, d} = square
  Face.Q{ax, ay, _} = a
  Face.Q{bx, by, _} = b
  Face.Q{cx, cy, _} = c
  Face.Q{+dx, +dy, _} = d
  quads.at(ax, ay, bx, by, cx, cy, dx, dy, dx, dy, size, ink, next)

# A rectangle of whole pixels in one flat colour: `w` columns from `x` and `h` rows from `y`.
# This is what an overlay is made of. The corners are chosen against the span rule: a row is
# covered from the first corner's `y` up to but not including the last's, and a column from
# the left corner through the right one.
def rect.at(drawn: Bool, +x0: F32, +y0: F32, +x1: F32, +y1: F32, +size: U32, color: U32,
  next: Quads) -> Quads:
  match drawn:
    case True{}:
      quads.at(x0, y0, x1, y0, x1, y1, x0, y1, x0, y1, size, flat_ink(color), next)
    case False{}:
      next

def rect(+x: U32, +y: U32, +w: U32, +h: U32, color: U32, +size: U32, next: Quads) -> Quads:
  rect.at(Bool.and(U32.is_gt(w, 0), U32.is_gt(h, 0)), U32.to_f32(x), U32.to_f32(y),
    U32.to_f32(U32.sub(U32.add(x, w), 1)), U32.to_f32(U32.add(y, h)), size, color, next)

# Any four screen corners in one flat colour, for the parts of an overlay that are not
# upright rectangles.
def quad(+ax: F32, +ay: F32, +bx: F32, +by: F32, +cx: F32, +cy: F32, +dx: F32, +dy: F32,
  color: U32, +size: U32, next: Quads) -> Quads:
  quads.at(ax, ay, bx, by, cx, cy, dx, dy, dx, dy, size, flat_ink(color), next)

# --- the near plane ------------------------------------------------------------
#
# A projected corner back in view space. `Face.project` computed the screen position from
# exactly these three numbers, so they are read back out of it rather than derived a second
# time from the face: `centre` is `half - 0.5` and the depth it divided by is the clamped
# one.
def view_of(q: Face.Q, +centre: F32, +focal: F32) -> V:
  Face.Q{sx, sy, +depth} = q
  +safe = F32.max(depth, 0.0001)
  V{F32.div(F32.mul(F32.sub(sx, centre), safe), focal),
    F32.div(F32.mul(F32.sub(centre, sy), safe), focal), depth}

def clip.push(keep: Bool, x: F32, y: F32, z: F32, rest: Vs) -> Vs:
  match keep:
    case True{}:
      VCons{x, y, z, rest}
    case False{}:
      rest

# One edge of the polygon against the near plane: the start corner when it is in front, and
# the point where the edge crosses the plane when its two ends are on different sides.
def clip.edge(p: V, q: V, acc: Vs) -> Vs:
  V{+px, +py, +pz} = p
  V{+qx, +qy, +qz} = q
  +t = F32.div(F32.sub(near_plane(), pz), F32.sub(qz, pz))
  clip.push(Bool.xor(F32.is_gt(pz, near_plane()), F32.is_gt(qz, near_plane())),
    F32.add(px, F32.mul(t, F32.sub(qx, px))), F32.add(py, F32.mul(t, F32.sub(qy, py))),
    near_plane(), clip.push(F32.is_gt(pz, near_plane()), px, py, pz, acc))

# The quad cut by the near plane: three to five corners, or none. The order comes out
# reversed, which a span fill does not read.
def clip(+a: V, +b: V, +c: V, +d: V) -> Vs:
  clip.edge(d, a, clip.edge(c, d, clip.edge(b, c, clip.edge(a, b, VNil{}))))

def screen_x(+x: F32, +z: F32, +centre: F32, +focal: F32) -> F32:
  F32.add(centre, F32.div(F32.mul(focal, x), z))

def screen_y(+y: F32, +z: F32, +centre: F32, +focal: F32) -> F32:
  F32.sub(centre, F32.div(F32.mul(focal, y), z))

# The cut polygon's corners, projected one at a time. A polygon of fewer than five repeats
# its last corner, and one of fewer than three is not a polygon and is dropped.
def poly.fifth(vs: Vs, +ax: F32, +ay: F32, +bx: F32, +by: F32, +cx: F32, +cy: F32, +dx: F32,
  +dy: F32, +centre: F32, +focal: F32, +size: U32, ink: Ink, next: Quads) -> Quads:
  match vs:
    case VNil{}:
      quads.at(ax, ay, bx, by, cx, cy, dx, dy, dx, dy, size, ink, next)
    case VCons{+x, +y, +z, _}:
      quads.at(ax, ay, bx, by, cx, cy, dx, dy, screen_x(x, z, centre, focal),
        screen_y(y, z, centre, focal), size, ink, next)

def poly.fourth(vs: Vs, +ax: F32, +ay: F32, +bx: F32, +by: F32, +cx: F32, +cy: F32,
  +centre: F32, +focal: F32, +size: U32, ink: Ink, next: Quads) -> Quads:
  match vs:
    case VNil{}:
      quads.at(ax, ay, bx, by, cx, cy, cx, cy, cx, cy, size, ink, next)
    case VCons{+x, +y, +z, rest}:
      poly.fifth(rest, ax, ay, bx, by, cx, cy, screen_x(x, z, centre, focal),
        screen_y(y, z, centre, focal), centre, focal, size, ink, next)

def poly.third(vs: Vs, +ax: F32, +ay: F32, +bx: F32, +by: F32, +centre: F32, +focal: F32,
  +size: U32, ink: Ink, next: Quads) -> Quads:
  match vs:
    case VNil{}:
      next
    case VCons{+x, +y, +z, rest}:
      poly.fourth(rest, ax, ay, bx, by, screen_x(x, z, centre, focal),
        screen_y(y, z, centre, focal), centre, focal, size, ink, next)

def poly.second(vs: Vs, +ax: F32, +ay: F32, +centre: F32, +focal: F32, +size: U32, ink: Ink,
  next: Quads) -> Quads:
  match vs:
    case VNil{}:
      next
    case VCons{+x, +y, +z, rest}:
      poly.third(rest, ax, ay, screen_x(x, z, centre, focal), screen_y(y, z, centre, focal),
        centre, focal, size, ink, next)

def poly.first(vs: Vs, +centre: F32, +focal: F32, +size: U32, ink: Ink,
  next: Quads) -> Quads:
  match vs:
    case VNil{}:
      next
    case VCons{+x, +y, +z, rest}:
      poly.second(rest, screen_x(x, z, centre, focal), screen_y(y, z, centre, focal), centre,
        focal, size, ink, next)

def quads.clipped(square: Face.Square, +centre: F32, +focal: F32, +size: U32, ink: Ink,
  next: Quads) -> Quads:
  Face.Square{a, b, c, d} = square
  poly.first(clip(view_of(a, centre, focal), view_of(b, centre, focal),
    view_of(c, centre, focal), view_of(d, centre, focal)), centre, focal, size, ink, next)

# A point of the world in view space: across, up and along the view from the eye.
def seen(+p: Voxel.Vec, +camera: Voxel.Camera) -> V:
  Voxel.Vec{px, py, pz} = p
  Voxel.Camera{+eye, +forward, +right, +up} = camera
  +d : Voxel.Vec = Voxel.Vec{F32.sub(px, Face.vx(eye)), F32.sub(py, Face.vy(eye)),
    F32.sub(pz, Face.vz(eye))}
  V{Face.dot3(right, d), Face.dot3(up, d), Face.dot3(forward, d)}

# Any four points of the world, in order round the shape, in one flat colour: cut at the near
# plane and projected like a face. This is what the things that are not blocks are made of.
def quads.world(+a: Voxel.Vec, +b: Voxel.Vec, +c: Voxel.Vec, +d: Voxel.Vec,
  +camera: Voxel.Camera, +half: F32, +focal: F32, +size: U32, color: U32, next: Quads) -> Quads:
  poly.first(clip(seen(a, camera), seen(b, camera), seen(c, camera), seen(d, camera)),
    F32.sub(half, 0.5), focal, size, flat_ink(color), next)

def q_front(q: Face.Q) -> Bool:
  F32.is_gt(Face.q_depth(q), near_plane())

def square_front(+s: Face.Square) -> Bool:
  Face.Square{a, b, c, d} = s
  Bool.and(Bool.and(q_front(a), q_front(b)), Bool.and(q_front(c), q_front(d)))

def square_gone(+s: Face.Square) -> Bool:
  Face.Square{a, b, c, d} = s
  Bool.not(Bool.or(Bool.or(q_front(a), q_front(b)), Bool.or(q_front(c), q_front(d))))

# Wholly in front, the face is projected as it always was. Wholly behind, it is not drawn.
# Across the plane, it is cut.
def quads.put(front: Bool, gone: Bool, square: Face.Square, +centre: F32, +focal: F32,
  +size: U32, ink: Ink, next: Quads) -> Quads:
  match front gone:
    case True{} _:
      quads.of(square, size, ink, next)
    case False{} True{}:
      next
    case False{} False{}:
      quads.clipped(square, centre, focal, size, ink, next)

# --- the face's plane ----------------------------------------------------------
#
# A pixel looks along `(X, Y, 1)` in view space, with `X = (x - centre) / focal` and
# `Y = (centre - y) / focal`. For a face with a corner `a` and edges `e1`, `e2` from it, the
# point the pixel sees is `t * (X, Y, 1)` with `t = (n . a) / (n . (X, Y, 1))`, `n` being
# `e1 x e2`. How far along `e1` that is, is `(k * e1 - (a . e1) * n) . (X, Y, 1)` over
# `n . (X, Y, 1)`, with `k = n . a`: two functions that are linear in the pixel. A vector
# `l` dotted with `(X, Y, 1)` is `l.x / focal * x - l.y / focal * y + (l.z + (l.y - l.x) *
# centre / focal)`, which is the three coefficients an `Ink` holds for each.

def cross(+a: V, +b: V) -> V:
  V{+ax, +ay, +az} = a
  V{+bx, +by, +bz} = b
  V{F32.sub(F32.mul(ay, bz), F32.mul(az, by)), F32.sub(F32.mul(az, bx), F32.mul(ax, bz)),
    F32.sub(F32.mul(ax, by), F32.mul(ay, bx))}

def dot(a: V, b: V) -> F32:
  V{ax, ay, az} = a
  V{bx, by, bz} = b
  F32.add(F32.add(F32.mul(ax, bx), F32.mul(ay, by)), F32.mul(az, bz))

def minus(a: V, b: V) -> V:
  V{ax, ay, az} = a
  V{bx, by, bz} = b
  V{F32.sub(ax, bx), F32.sub(ay, by), F32.sub(az, bz)}

# `k * e - m * n`.
def blend(+k: F32, e: V, +m: F32, n: V) -> V:
  V{ex, ey, ez} = e
  V{nx, ny, nz} = n
  V{F32.sub(F32.mul(k, ex), F32.mul(m, nx)), F32.sub(F32.mul(k, ey), F32.mul(m, ny)),
    F32.sub(F32.mul(k, ez), F32.mul(m, nz))}

# The three vectors as one ink. `across` and `down` are which way the texture runs.
def ink.of(n: V, across: V, down: V, +centre: F32, +focal: F32, tex: U32, k: F32,
  haze: U32) -> Ink:
  V{+nx, +ny, nz} = n
  V{+ux, +uy, uz} = across
  V{+vx, +vy, vz} = down
  +scale = F32.div(centre, focal)
  Ink{haze, tex,
    F32.add(nz, F32.mul(F32.sub(ny, nx), scale)), F32.div(nx, focal), F32.neg(F32.div(ny, focal)),
    F32.add(uz, F32.mul(F32.sub(uy, ux), scale)), F32.div(ux, focal), F32.neg(F32.div(uy, focal)),
    F32.add(vz, F32.mul(F32.sub(vy, vx), scale)), F32.div(vx, focal), F32.neg(F32.div(vy, focal)),
    F32.mul(k, Sky.fog_scale())}

# Which way up a texture is. `Face.square_axis` lists a face's corners so that, from the
# first, the second is one cell along `e1` and the fourth one cell along `e2`: for a face
# across x those are up and along z, for one across z along x and up, and for a top or a
# bottom along x and along z. A texture runs across and *down*, so the upright edge is the
# one that is turned round.
def ink.turned(axis: Nat, +n: V, +along1: V, +along2: V, +centre: F32, +focal: F32,
  tex: U32, k: F32, haze: U32) -> Ink:
  match axis:
    case 0n:
      ink.of(n, along2, minus(n, along1), centre, focal, tex, k, haze)
    case 1n:
      ink.of(n, along1, along2, centre, focal, tex, k, haze)
    case _:
      ink.of(n, along1, minus(n, along2), centre, focal, tex, k, haze)

def ink.plane(axis: Nat, +a: V, +e1: V, +e2: V, +n: V, +centre: F32, +focal: F32,
  tex: U32, haze: U32) -> Ink:
  ink.turned(axis, n, blend(dot(n, a), e1, dot(a, e1), n), blend(dot(n, a), e2, dot(a, e2), n),
    centre, focal, tex, dot(n, a), haze)

def ink.edges(axis: Nat, +a: V, +e1: V, +e2: V, +centre: F32, +focal: F32, tex: U32,
  haze: U32) -> Ink:
  ink.plane(axis, a, e1, e2, cross(e1, e2), centre, focal, tex, haze)

def ink.textured(+dir: Nat, square: Face.Square, +centre: F32, +focal: F32, +block: U32,
  haze: U32, level: U32) -> Ink:
  Face.Square{a, b, c, d} = square
  +corner = view_of(a, centre, focal)
  ink.edges(Face.axis_of(dir), corner, minus(view_of(b, centre, focal), corner),
    minus(view_of(d, centre, focal), corner), centre, focal,
    U32.or(U32.or(U32.add(U32.mul(Shade.block_of(block), 8), U32.from_nat(dir)),
      U32.shln(Shade.levels_of(block), 11n)), U32.shln(level, 27n)), haze)

# A face's ink: its texture, or the one flat colour the gate reads a block and a side from.
def ink.face(textured: Bool, +dir: Nat, +square: Face.Square, +centre: F32, +focal: F32,
  +block: U32, haze: U32, level: U32) -> Ink:
  match textured:
    case True{}:
      ink.textured(dir, square, centre, focal, block, haze, level)
    case False{}:
      flat_ink(Voxel.shade_color(Voxel.block_color(Shade.block_of(block)), U32.from_nat(dir)))

def quads.rev(quads: Quads, acc: Quads) -> Quads:
  match quads:
    case QNil{}:
      acc
    case QCons{ax, ay, bx, by, cx, cy, dx, dy, ex, ey, ink, first, stop, left, right, next}:
      quads.rev(next, QCons{ax, ay, bx, by, cx, cy, dx, dy, ex, ey, ink, first, stop, left,
        right, acc})

# The overlay first, then the scene: the list is painted nearest first.
def quads.after(over: Quads, scene: Quads) -> Quads:
  match over:
    case QNil{}:
      scene
    case QCons{ax, ay, bx, by, cx, cy, dx, dy, ex, ey, ink, first, stop, left, right, next}:
      QCons{ax, ay, bx, by, cx, cy, dx, dy, ex, ey, ink, first, stop, left, right,
        quads.after(next, scene)}

def odd(n: Nat) -> Bool:
  match n:
    case 0n:
      False{}
    case 1n+p:
      Bool.not(odd(p))

# `deal` prepends, so every level of the tree reverses the order it was handed. A tile
# paints nearest first, so the root list is turned once when the number of levels is odd.
def quads.turned(turn: Bool, quads: Quads) -> Quads:
  match turn:
    case True{}:
      quads.rev(quads, QNil{})
    case False{}:
      quads

# One pass, four lists. A quad goes to every quarter its rows and its column box meet.
def deal(quads: Quads, +xm: U32, +ym: U32, a: Quads, b: Quads, c: Quads,
  d: Quads) -> Work:
  match quads:
    case QNil{}:
      Dealt{a, b, c, d}
    case QCons{+ax, +ay, +bx, +by, +cx, +cy, +dx, +dy, +ex, +ey, +ink, +first, +stop,
      +left, +right, next}:
      +top = U32.is_lt(first, ym)
      +bottom = U32.is_gt(stop, ym)
      +west = U32.is_lt(left, xm)
      +east = U32.is_ge(right, xm)
      deal(next, xm, ym,
        quads.keep(Bool.and(top, west), ax, ay, bx, by, cx, cy, dx, dy, ex, ey, ink, first,
          stop, left, right, a),
        quads.keep(Bool.and(top, east), ax, ay, bx, by, cx, cy, dx, dy, ex, ey, ink, first,
          stop, left, right, b),
        quads.keep(Bool.and(bottom, west), ax, ay, bx, by, cx, cy, dx, dy, ex, ey, ink,
          first, stop, left, right, c),
        quads.keep(Bool.and(bottom, east), ax, ay, bx, by, cx, cy, dx, dy, ex, ey, ink,
          first, stop, left, right, d))

# --- the sky -------------------------------------------------------------------
#
# The sky over a square region whose top row is `y0`, without an array. A region collapses
# to one `Pix` exactly when its rows share a colour, which is the collapse `flat.join` makes,
# so this is the tree a fold reads out of a tile nothing was painted in.
#
# `sky` is the row the horizon is on, as `Sky.horizon` counts it, and the colour of the sky
# on a row is `Sky.color`. A frame painted in flat colours passes 0 and keeps the gradient
# the ray renderers draw, `Voxel.sky_color_at`, because that frame is the one held to them.
def sky.at(legacy: Bool, +sky: U32, +air: U32, +row: U32, +size: U32) -> U32:
  match legacy:
    case True{}:
      Voxel.sky_color_at(row, size)
    case False{}:
      Sky.color(sky, air, row, size)

def sky_color(+sky: U32, +air: U32, +row: U32, +size: U32) -> U32:
  sky.at(U32.is_eq(sky, 0), sky, air, row, size)

def sky.flat(+k: Nat, +y0: U32, +size: U32, +sky: U32, +air: U32) -> Flat:
  match k:
    case 0n:
      +color = sky_color(sky, air, y0, size)
      Flat{Pix{color}, color, True{}}
    case 1n+r:
      +top : Flat = sky.flat(r, y0, size, sky, air)
      +bottom : Flat = sky.flat(r, U32.add(y0, U32.shln((1 : U32), r)), size, sky, air)
      flat.join(top, top, bottom, bottom)

# --- a tile --------------------------------------------------------------------
#
# A tile is painted **nearest first**, and a pixel is written once: a cell that already
# holds a colour is left alone. So a pixel a near face covers is never computed again for
# the faces behind it, which is what lets a pixel cost a division and a texel: painted the
# other way, farthest first, the same frame computed four pixels for every one it kept.
#
# A cell is `0` until it is painted, and a painted cell carries `painted()` above its
# colour, because black is a colour. Whatever is still `0` when the tile is folded is sky.
def painted() -> U32:
  16777216

def written(+color: U32) -> U32:
  U32.or(U32.and(color, 16777215), painted())

def put.flat(empty: Bool, frame: Array<U32>, +at: U32, +color: U32) -> Array<U32>:
  match empty:
    case True{}:
      frame[at] <- color
    case False{}:
      frame

def put.flat.at(read: Array<U32> & U32, +at: U32, +color: U32) -> Array<U32>:
  (frame, old) = read
  put.flat(U32.is_eq(old, 0), frame, at, color)

def fill_flat(remaining: Nat, +at: U32, +color: U32, frame: Array<U32>) -> Array<U32>:
  match remaining:
    case 0n:
      frame
    case 1n+r:
      fill_flat(r, (at + 1 : U32), color, put.flat.at(frame[at], at, color))

# The texel a pixel sees: where on the face it looks, as sixteenths, and the material's
# colour there. A pixel on the face's very edge can land a hair outside 0..1, which the mask
# folds back onto the face.
#
# The texel is lit by the corner levels of the face, which `tex` carries above bit 11, and
# then seen through the air in front of it: `fog / d` is the depth of the pixel as an amount
# of air, and `Sky.fog_floor` is where the air starts to show.
#
# The top of water takes more of that colour, and sooner: seen from a low angle water shows
# the sky, and the low angles are the far ones. `57` is water's top, block 7 and side 1.
def air_of(+tex: U32, +depth: F32) -> U32:
  +air = F32.max(F32.sub(depth, Sky.fog_floor()), 0.0)
  +sheen = Bool.pick(F32, U32.is_eq(U32.and(tex, 2047), 57),
    F32.min(F32.mul(depth, Sky.water_sheen()), Sky.water_sheen_most()), 0.0)
  F32.to_u32(F32.min(F32.add(air, sheen), 256.0))

#
# Above the corner levels, from bit 27, `tex` carries how bright the hour is, and `haze` is
# the colour of the air: both are the frame's, and they ride in the ink so that a pixel has
# them without asking.
def texel_of(+d: F32, +u: F32, +v: F32, +tex: U32, +fog: F32, haze: U32) -> U32:
  Sky.hazed(Texture.texel_lit(U32.and(U32.shrn(tex, 3n), 255), U32.and(tex, 7),
      U32.and(F32.to_u32(F32.max(F32.div(F32.mul(u, 16.0), d), 0.0)), 15),
      U32.and(F32.to_u32(F32.max(F32.div(F32.mul(v, 16.0), d), 0.0)), 15),
      U32.and(U32.shrn(tex, 11n), 65535), U32.shrn(tex, 27n)),
    air_of(tex, F32.div(fog, d)), haze)

def put.tex(empty: Bool, frame: Array<U32>, +at: U32, +d: F32, +u: F32, +v: F32,
  +tex: U32, +fog: F32, haze: U32) -> Array<U32>:
  match empty:
    case True{}:
      frame[at] <- written(texel_of(d, u, v, tex, fog, haze))
    case False{}:
      frame

def put.tex.at(read: Array<U32> & U32, +at: U32, +d: F32, +u: F32, +v: F32,
  +tex: U32, +fog: F32, haze: U32) -> Array<U32>:
  (frame, old) = read
  put.tex(U32.is_eq(old, 0), frame, at, d, u, v, tex, fog, haze)

# One row of a textured polygon. The three plane functions are stepped by their `x`
# coefficient from pixel to pixel, so a pixel is three additions before its division.
def fill_tex(remaining: Nat, +at: U32, +d: F32, +u: F32, +v: F32, +dx: F32, +ux: F32,
  +vx: F32, +tex: U32, +fog: F32, +haze: U32, frame: Array<U32>) -> Array<U32>:
  match remaining:
    case 0n:
      frame
    case 1n+r:
      fill_tex(r, (at + 1 : U32), F32.add(d, dx), F32.add(u, ux), F32.add(v, vx), dx, ux, vx,
        tex, fog, haze, put.tex.at(frame[at], at, d, u, v, tex, fog, haze))

def fill.inked(flat: Bool, +count: Nat, +at: U32, +x: F32, +y: F32, ink: Ink,
  frame: Array<U32>) -> Array<U32>:
  match flat ink:
    case True{} Ink{color, tex, d0, dx, dy, u0, ux, uy, v0, vx, vy, fog}:
      fill_flat(count, at, written(color), frame)
    case False{} Ink{color, +tex, +d0, +dx, +dy, +u0, +ux, +uy, +v0, +vx, +vy, +fog}:
      fill_tex(count, at, F32.add(d0, F32.add(F32.mul(dx, x), F32.mul(dy, y))),
        F32.add(u0, F32.add(F32.mul(ux, x), F32.mul(uy, y))),
        F32.add(v0, F32.add(F32.mul(vx, x), F32.mul(vy, y))), dx, ux, vx, tex, fog, color,
        frame)

def ink_flat(ink: Ink) -> Bool:
  Ink{color, tex, d0, dx, dy, u0, ux, uy, v0, vx, vy, fog} = ink
  U32.is_eq(tex, 0)

# The frame's span for this row, cut to the tile's columns.
def tile.span(span: Span, +y: U32, +x0: U32, +y0: U32, +edge: U32, +ink: Ink,
  frame: Array<U32>) -> Array<U32>:
  Span{sx0, sx1} = span
  +low = U32.max(sx0, x0)
  +high = U32.min(sx1, U32.sub(U32.add(x0, edge), (1 : U32)))
  fill.inked(ink_flat(ink),
    U32.to_nat(U32.sub(U32.max(U32.add(high, (1 : U32)), low), low)),
    U32.add(U32.mul(U32.sub(y, y0), edge), U32.sub(low, x0)), U32.to_f32(low), U32.to_f32(y),
    ink, frame)

def tile.rows(remaining: Nat, +y: U32, +ax: F32, +ay: F32, +bx: F32, +by: F32, +cx: F32,
  +cy: F32, +dx: F32, +dy: F32, +ex: F32, +ey: F32, +ink: Ink, +size: U32, +x0: U32,
  +y0: U32, +edge: U32, frame: Array<U32>) -> Array<U32>:
  match remaining:
    case 0n:
      frame
    case 1n+r:
      tile.rows(r, (y + 1 : U32), ax, ay, bx, by, cx, cy, dx, dy, ex, ey, ink, size, x0,
        y0, edge,
        tile.span(span_edges(ax, ay, bx, by, cx, cy, dx, dy, ex, ey, U32.to_f32(y), size),
          y, x0, y0, edge, ink, frame))

def tile.quads(quads: Quads, +size: U32, +x0: U32, +y0: U32, +edge: U32,
  frame: Array<U32>) -> Array<U32>:
  match quads:
    case QNil{}:
      frame
    case QCons{ax, ay, bx, by, cx, cy, dx, dy, ex, ey, ink, first, stop, _, _, next}:
      +low = U32.max(first, y0)
      +high = U32.min(stop, U32.add(y0, edge))
      tile.quads(next, size, x0, y0, edge,
        tile.rows(U32.to_nat(U32.sub(U32.max(high, low), low)), low, ax, ay, bx, by, cx, cy,
          dx, dy, ex, ey, ink, size, x0, y0, edge, frame))

# A tile's cells: its quads, nearest first, over nothing.
#
# `Array.new`'s third argument is a **depth, not a count**: `[v : T^d]` is `2^d` slots, so a
# tile of edge `2^tile` is `2 * tile`. Passing the element count fail-stops with "an array
# past the deepest block class 31", and passing too few wraps silently, because both
# `Array.get` and `Array.swap` mask the index with `n - 1`.
def tile.painted(+tile: Nat, +x0: U32, +y0: U32, +size: U32, quads: Quads) -> Array<U32>:
  tile.quads(quads, size, x0, y0, U32.shln((1 : U32), tile),
    Array.new(U32, Nat.mul(2n, tile), 0))

# A cell as a colour: what was painted there, or the sky on its row.
def shown.at(empty: Bool, +cell: U32, +row: U32, +size: U32, +sky: U32, +air: U32) -> U32:
  match empty:
    case True{}:
      sky_color(sky, air, row, size)
    case False{}:
      U32.and(cell, 16777215)

def shown(+cell: U32, +row: U32, +size: U32, +sky: U32, +air: U32) -> U32:
  shown.at(U32.is_eq(cell, 0), cell, row, size, sky, air)

def stack.push(flat: Flat, rest: Stack) -> Stack:
  Flat{image, color, uniform} = flat
  PCons{image, color, uniform, rest}

# The four newest quarters, joined by the rule `flat.join` uses. They were pushed top-left
# first, so they come off bottom-right first.
def stack.join(stack: Stack) -> Stack:
  match stack:
    case PCons{id, cd, ud, PCons{ic, cc, uc, PCons{ib, cb, ub, PCons{ia, ca, ua, rest}}}}:
      stack.push(flat.join.at2(Qua{ia, ib, ic, id}, ca, ua, ub, uc, ud, cb, cc, cd), rest)
    case _:
      PNil{}

def fold.joined(state: Fold) -> Fold:
  Fold{frame, stack} = state
  Fold{frame, stack.join(stack)}

def fold.colored(frame: Array<U32>, +color: U32, stack: Stack) -> Fold:
  Fold{frame, PCons{Pix{color}, color, True{}, stack}}

def fold.pixel(read: Array<U32> & U32, stack: Stack, +row: U32, +size: U32, +sky: U32, +air: U32) -> Fold:
  (frame, cell) = read
  fold.colored(frame, shown(cell, row, size, sky, air), stack)

# The tile's quadtree, read out of its array by one task that threads the one handle through
# the four quarters. What it has built so far rides beside the handle, because a value
# cannot be both returned and passed on. Forking a handle and four tasks per node instead is
# what made the first painter's fold cost more than its fill: about 350,000 nodes at 1024.
# `base` is the cell's index in the tile, so its row in the frame is `y0` plus `base` over
# the tile's edge.
def tile.fold(+q: Nat, +base: U32, +tile: Nat, +y0: U32, +size: U32, +sky: U32, +air: U32,
  state: Fold) -> Fold:
  match q:
    case 0n:
      Fold{frame, stack} = state
      fold.pixel(Array.get(U32, frame, base), stack, U32.add(y0, U32.shrn(base, tile)), size, sky, air)
    case 1n+r:
      +step = U32.shln((1 : U32), r)
      +down = U32.shln(step, tile)
      fold.joined(tile.fold(r, U32.add(U32.add(base, step), down), tile, y0, size, sky, air,
        tile.fold(r, U32.add(base, down), tile, y0, size, sky, air,
          tile.fold(r, U32.add(base, step), tile, y0, size, sky, air,
            tile.fold(r, base, tile, y0, size, sky, air, state)))))

def stack.top(stack: Stack) -> Flat:
  match stack:
    case PCons{image, color, uniform, _}:
      Flat{image, color, uniform}
    case PNil{}:
      Flat{Pix{0}, 0, True{}}

def fold.flat(state: Fold) -> Flat:
  Fold{_, stack} = state
  stack.top(stack)

def tile.draw(+tile: Nat, +x0: U32, +y0: U32, +size: U32, +sky: U32, +air: U32, quads: Quads) -> Flat:
  fold.flat(tile.fold(tile, 0, tile, y0, size, sky, air,
    Fold{tile.painted(tile, x0, y0, size, quads), PNil{}}))

# --- the fork tree -------------------------------------------------------------
#
# `log` is the node's own edge as a power of two, and a node whose edge is the tile's draws.
#
# A node deals its quads and calls itself on the result, because the four lists have to
# arrive as a parameter before they can be taken apart and a `def` may only call itself. So
# `k` counts half-levels: one step from a node to its dealt quarters and one from those to
# its children, which is what lets the checker see both calls shrink.
def node(+k: Nat, +log: Nat, +x0: U32, +y0: U32, +size: U32, +sky: U32, +air: U32, work: Work) -> Flat:
  match k work:
    case _ Whole{QNil{}}:
      sky.flat(log, y0, size, sky, air)
    case 0n Whole{quads}:
      tile.draw(log, x0, y0, size, sky, air, quads)
    case 1n+r Whole{quads}:
      +half = U32.shr(U32.shln((1 : U32), log))
      node(r, log, x0, y0, size, sky, air, deal(quads, U32.add(x0, half), U32.add(y0, half), QNil{},
        QNil{}, QNil{}, QNil{}))
    case 1n+r Dealt{qa, qb, qc, qd}:
      +half = U32.shr(U32.shln((1 : U32), log))
      +xm = U32.add(x0, half)
      +ym = U32.add(y0, half)
      +kid = Nat.sub(log, 1n)
      a b c d = node(r, kid, x0, y0, size, sky, air, Whole{qa}) node(r, kid, xm, y0, size, sky, air, Whole{qb})
        node(r, kid, x0, ym, size, sky, air, Whole{qc}) node(r, kid, xm, ym, size, sky, air, Whole{qd})
      flat.join(a, b, c, d)
    case 0n Dealt{qa, qb, qc, qd}:
      sky.flat(log, y0, size, sky, air)

# The horizon of the frame: where the camera puts it when the scene is textured, and none for
# the flat frame, which keeps the sky the ray renderers draw.
def sky_of(textured: Bool, camera: Voxel.Camera, +half: F32, +focal: F32) -> U32:
  match textured:
    case True{}:
      Sky.horizon(Face.vy(Face.cam_forward(camera)), half, focal)
    case False{}:
      0

# --- the scene, a chunk at a time ------------------------------------------------
#
# The faces come in groups, one per chunk of the view region, each in its own chunk's cells
# with the chunk's place beside it. That is how the client keeps them, and it is what lets
# the front half of a frame be divided:
#
# - **A chunk that cannot be seen is not looked at.** Its box is tested once against the near
#   plane, the four sides of the view and the end of the air, and a chunk that fails is tens
#   of hundreds of faces nobody reads. Looking one way across a region of twenty-five chunks,
#   most of them fail.
# - **The chunks that can be seen are done at the same time.** Each is its own task: its
#   faces that can paint are found and projected into polygons. The one-thread part of a
#   frame used to be the walk, the sort and the projection of the whole region; it is now the
#   putting of the polygons in order, which is one pass and not a sort.
#
# A flat list of faces is one group with no box, which is the frame the tests paint.

type Group is Data:
  Group{dx: U32, dz: U32, boxed: Bool, faces: List<&2, Face.Face>}

# One face ready to paint: how far its block is, and its polygon as a list of one.
type Drawn is Data:
  Drawn{depth: F32, quad: Quads}

# What a node of the scene's tree is handed: the groups, or its two halves already split.
# They are one type for the reason `Work` is.
type Batch is Data:
  Lot{groups: List<&2, Group>}
  Halves{a: List<&2, Group>, b: List<&2, Group>}

# The least and the most `w . p` can be for a point `p` of the box from `lo` to `hi`.
def box_low(w: Voxel.Vec, lo: Voxel.Vec, hi: Voxel.Vec) -> F32:
  Voxel.Vec{+wx, +wy, +wz} = w
  Voxel.Vec{lx, ly, lz} = lo
  Voxel.Vec{hx, hy, hz} = hi
  F32.add(F32.add(F32.min(F32.mul(wx, lx), F32.mul(wx, hx)), F32.min(F32.mul(wy, ly), F32.mul(wy, hy))),
    F32.min(F32.mul(wz, lz), F32.mul(wz, hz)))

def box_high(w: Voxel.Vec, lo: Voxel.Vec, hi: Voxel.Vec) -> F32:
  Voxel.Vec{+wx, +wy, +wz} = w
  Voxel.Vec{lx, ly, lz} = lo
  Voxel.Vec{hx, hy, hz} = hi
  F32.add(F32.add(F32.max(F32.mul(wx, lx), F32.mul(wx, hx)), F32.max(F32.mul(wy, ly), F32.mul(wy, hy))),
    F32.max(F32.mul(wz, lz), F32.mul(wz, hz)))

# How far the eye is from the span `lo` to `hi` along one axis: nothing when it is inside.
def gap(+lo: F32, +hi: F32) -> F32:
  F32.max(F32.max(lo, F32.neg(hi)), 0.0)

def box_away(lo: Voxel.Vec, hi: Voxel.Vec) -> F32:
  Voxel.Vec{lx, ly, lz} = lo
  Voxel.Vec{hx, hy, hz} = hi
  +x = gap(lx, hx)
  +y = gap(ly, hy)
  +z = gap(lz, hz)
  F32.add(F32.add(F32.mul(x, x), F32.mul(y, y)), F32.mul(z, z))

# Whether every block of the box is outside one side of the view: `side` is across or up the
# view, turned to the side asked about. `in_view` keeps a block whose centre is within
# `(ahead + 0.9) * 0.66667 + 0.9` of the middle, which is `side - 0.66667 * ahead <= 1.5`.
def box_outside(+side: Voxel.Vec, +forward: Voxel.Vec, +lo: Voxel.Vec, +hi: Voxel.Vec) -> Bool:
  F32.is_gt(box_low(Voxel.Vec.add(side, Voxel.Vec.scale(forward, F32.neg(0.66667))), lo, hi), 1.6)

# Whether any face of a chunk at (`dx`, `dz`) of the region can paint: its box, from the eye,
# is not wholly behind the near plane, past the reach, or outside a side of the view.
def group_shown(+dx: U32, +dz: U32, +camera: Voxel.Camera, reach: F32) -> Bool:
  Voxel.Camera{+eye, +forward, +right, +up} = camera
  +lo : Voxel.Vec = Voxel.Vec{F32.sub(U32.to_f32(dx), Face.vx(eye)), F32.neg(Face.vy(eye)),
    F32.sub(U32.to_f32(dz), Face.vz(eye))}
  +hi : Voxel.Vec = Voxel.Vec.add(lo, Voxel.Vec{16.0, 20.0, 16.0})
  Bool.and(Bool.and(F32.is_gt(box_high(forward, lo, hi), near_plane()), F32.is_le(box_away(lo, hi), reach)),
    Bool.not(Bool.or(
      Bool.or(box_outside(right, forward, lo, hi), box_outside(Voxel.Vec.scale(right, F32.neg(1.0)), forward, lo, hi)),
      Bool.or(box_outside(up, forward, lo, hi), box_outside(Voxel.Vec.scale(up, F32.neg(1.0)), forward, lo, hi)))))

# Whether a face can paint. `cut` is the near plane on the far corner's own scale, which
# measures along the view from the world's origin rather than from the eye.
def face_kept(+dir: Nat, +fx: F32, +fy: F32, +fz: F32, +eye: Voxel.Vec, +right: Voxel.Vec,
  +up: Voxel.Vec, +forward: Voxel.Vec, cut: F32, reach: F32) -> Bool:
  Bool.and(faces_eye(dir, fx, fy, fz, Face.vx(eye), Face.vy(eye), Face.vz(eye)),
    Bool.and(F32.is_gt(far_corner.at(Face.axis_of(dir), Face.plane_of(dir, fx, fy, fz), fx,
        fy, fz, forward), cut),
      cell_shown(centre_from(fx, fy, fz, eye), right, up, forward, reach)))

# A face cut wholly away at the near plane has no polygon, and is not kept.
def drawn.put(+quad: Quads, depth: F32, rest: List<&2, Drawn>) -> List<&2, Drawn>:
  match quad:
    case QNil{}:
      rest
    case _:
      Drawn{depth, quad} <> rest

def drawn.face(keep: Bool, +dir: Nat, +fx: F32, +fy: F32, +fz: F32, +block: U32,
  +eye: Voxel.Vec, +right: Voxel.Vec, +up: Voxel.Vec, +forward: Voxel.Vec, +half: F32,
  +focal: F32, +size: U32, +textured: Bool, +haze: U32, +level: U32,
  rest: List<&2, Drawn>) -> List<&2, Drawn>:
  match keep:
    case False{}:
      rest
    case True{}:
      +square : Face.Square = Face.square_of(dir, fx, fy, fz, eye, right, up, forward, half, focal)
      drawn.put(quads.put(square_front(square), square_gone(square), square, F32.sub(half, 0.5),
          focal, size, ink.face(textured, dir, square, F32.sub(half, 0.5), focal, block, haze, level),
          QNil{}),
        cell_distance(fx, fy, fz, eye), rest)

# One group's faces that can paint, each projected. The list is built on the way down, so
# the walk is a loop however many faces a chunk has.
def drawn.faces(faces: List<&2, Face.Face>, +dx: U32, +dz: U32, +eye: Voxel.Vec,
  +right: Voxel.Vec, +up: Voxel.Vec, +forward: Voxel.Vec, +half: F32, +focal: F32, +size: U32,
  +textured: Bool, +haze: U32, +level: U32, +cut: F32, +reach: F32,
  kept: List<&2, Drawn>) -> List<&2, Drawn>:
  match faces:
    case Nil{}:
      kept
    case Face.Face{x, y, z, +dir, +block} <> rest:
      +fx = U32.to_f32(U32.add(x, dx))
      +fy = U32.to_f32(y)
      +fz = U32.to_f32(U32.add(z, dz))
      drawn.faces(rest, dx, dz, eye, right, up, forward, half, focal, size, textured, haze,
        level, cut, reach,
        drawn.face(face_kept(dir, fx, fy, fz, eye, right, up, forward, cut, reach), dir, fx, fy,
          fz, block, eye, right, up, forward, half, focal, size, textured, haze, level, kept))

# One group's polygons, in no order, or none when its chunk cannot be seen.
def drawn.group.at(shown: Bool, faces: List<&2, Face.Face>, +dx: U32, +dz: U32,
  +camera: Voxel.Camera, +half: F32, +focal: F32, +size: U32, +textured: Bool, +haze: U32,
  +level: U32, +reach: F32) -> List<&2, Drawn>:
  match shown:
    case False{}:
      []
    case True{}:
      Voxel.Camera{+eye, +forward, +right, +up} = camera
      drawn.faces(faces, dx, dz, eye, right, up, forward, half, focal, size, textured, haze,
        level, F32.add(Face.dot3(forward, eye), near_plane()), reach, [])

def drawn.group(group: Group, +camera: Voxel.Camera, +half: F32, +focal: F32, +size: U32,
  +textured: Bool, +haze: U32, +level: U32, +reach: F32) -> List<&2, Drawn>:
  Group{+dx, +dz, boxed, faces} = group
  drawn.group.at(Bool.or(Bool.not(boxed), group_shown(dx, dz, camera, reach)), faces, dx, dz,
    camera, half, focal, size, textured, haze, level, reach)

# Two lists as one, in no order: the first is walked once.
def drawn.join(a: List<&2, Drawn>, b: List<&2, Drawn>) -> List<&2, Drawn>:
  List.reverse.go(&2, Drawn, a, b)

# The groups dealt into two lists, one to each in turn.
def drawn.split(groups: List<&2, Group>, a: List<&2, Group>, b: List<&2, Group>) -> Batch:
  match groups:
    case Nil{}:
      Halves{a, b}
    case group <> rest:
      drawn.split(rest, b, group <> a)

# A list of groups, one after another: what is left when the tree runs out of levels.
def drawn.serial(groups: List<&2, Group>, +camera: Voxel.Camera, +half: F32, +focal: F32,
  +size: U32, +textured: Bool, +haze: U32, +level: U32, +reach: F32) -> List<&2, Drawn>:
  match groups:
    case Nil{}:
      []
    case group <> rest:
      drawn.join(drawn.group(group, camera, half, focal, size, textured, haze, level, reach),
        drawn.serial(rest, camera, half, focal, size, textured, haze, level, reach))

# Every group's polygons as one list, in no order. `k` counts half-levels, as `node` does:
# one step from a lot to its halves and one from the halves to the two tasks.
def drawn.tree(+k: Nat, batch: Batch, +camera: Voxel.Camera, +half: F32, +focal: F32,
  +size: U32, +textured: Bool, +haze: U32, +level: U32, +reach: F32) -> List<&2, Drawn>:
  match k batch:
    case _ Lot{Nil{}}:
      []
    case 0n Lot{groups}:
      drawn.serial(groups, camera, half, focal, size, textured, haze, level, reach)
    case 1n+r Lot{groups}:
      drawn.tree(r, drawn.split(groups, [], []), camera, half, focal, size, textured, haze,
        level, reach)
    case 0n Halves{a, b}:
      drawn.join(drawn.serial(a, camera, half, focal, size, textured, haze, level, reach),
        drawn.serial(b, camera, half, focal, size, textured, haze, level, reach))
    case 1n+r Halves{a, b}:
      x y = drawn.tree(r, Lot{a}, camera, half, focal, size, textured, haze, level, reach)
        drawn.tree(r, Lot{b}, camera, half, focal, size, textured, haze, level, reach)
      drawn.join(x, y)

# --- the order, by counting ----------------------------------------------------------
#
# The order between two blocks only matters when one can hide the other, and then their
# distances differ by a whole cell or more (see "the order" above). So the whole part of the
# distance is all the order there is: polygons are put in a bucket per whole cell of
# distance, and the buckets are read farthest first, each polygon put in front of the list so
# far. That is one pass to fill and one to read, where a sort compared every polygon a dozen
# times, and what order the polygons arrive in does not matter.

# 256 buckets: more cells than the summed distance across the widest region there is.
def bucket_depth() -> Nat:
  8n

def bucket_of(depth: F32) -> U32:
  U32.min(F32.to_u32(F32.max(depth, 0.0)), 255)

# A polygon put in front of a list.
def relink(quad: Quads, next: Quads) -> Quads:
  match quad:
    case QNil{}:
      next
    case QCons{ax, ay, bx, by, cx, cy, dx, dy, ex, ey, ink, first, stop, left, right, _}:
      QCons{ax, ay, bx, by, cx, cy, dx, dy, ex, ey, ink, first, stop, left, right, next}

def buckets.put(read: Array<Quads> & Quads, +at: U32, quad: Quads) -> Array<Quads>:
  (buckets, held) = read
  Array.set(Quads, buckets, at, relink(quad, held))

def buckets.fill(drawn: List<&2, Drawn>, buckets: Array<Quads>) -> Array<Quads>:
  match drawn:
    case Nil{}:
      buckets
    case Drawn{depth, quad} <> rest:
      +at = bucket_of(depth)
      buckets.fill(rest, buckets.put(Array.swap(Quads, buckets, at, QNil{}), at, quad))

# The buckets read farthest first. `read` is bucket `remaining - 1` and what it holds, and
# `acc` is every polygon further than it, nearest first.
def buckets.link(+remaining: Nat, read: Array<Quads> & Quads, acc: Quads) -> Quads:
  match remaining:
    case 0n:
      acc
    case 1n+below:
      (buckets, held) = read
      buckets.link(below, Array.swap(Quads, buckets, U32.sub(U32.from_nat(below), 1), QNil{}),
        quads.rev(held, acc))

# `behind` is what the list ends with: polygons further than every face, painted last.
def linked(drawn: List<&2, Drawn>, behind: Quads) -> Quads:
  buckets.link(256n,
    Array.swap(Quads, buckets.fill(drawn, Array.new(Quads, bucket_depth(), QNil{})), 255, QNil{}),
    behind)

# Five levels of halving is thirty-two tasks, which is more than the region's chunks.
def scene_levels() -> Nat:
  10n

# The frame's polygons, nearest first: the overlay, then the faces, then what is behind them.
#
# `among` is what stands in the scene and is not a block — `native/body.bend`'s players —
# as polygons with how far each is, nearest first. They go into the same buckets as the
# faces, ahead of them: within a bucket the order handed over is the order painted.
def frame_quads(groups: List<&2, Group>, +camera: Voxel.Camera, +half: F32, +focal: F32,
  +size: U32, over: Quads, among: List<&2, Drawn>, behind: Quads, +textured: Bool, air: U32,
  level: U32) -> Quads:
  quads.after(over,
    linked(drawn.join(List.reverse(&2, Drawn, among),
      drawn.tree(scene_levels(), Lot{groups}, camera, half, focal, size, textured,
        Sky.haze_of(air), level, reach_of(textured))), behind))

# A flat list of faces as the one group it is.
def one_group(faces: List<&2, Face.Face>) -> List<&2, Group>:
  [Group{0, 0, False{}, faces}]

# The frame with tiles of edge `2^tile`, under an overlay. `tile = depth` is the whole frame
# as one tile.
#
# `air` is the sky's two colours as `Sky.air` packs them and `level` how bright the hour is,
# `among` is what stands in the scene with the faces, and `behind` is what is further than
# every face. `tiles_frame_all` is the frame with nothing among its faces, and
# `tiles_frame_with` the one with nothing behind them either, at full day, which is the
# frame the tests hold.
def tiles_frame_among(groups: List<&2, Group>, +camera: Voxel.Camera, +half: F32,
  +focal: F32, +size: U32, +depth: Nat, +tile: Nat, over: Quads, among: List<&2, Drawn>,
  behind: Quads, +textured: Bool, +air: U32, level: U32) -> Flat:
  +levels = Nat.sub(depth, tile)
  node(Nat.mul(2n, levels), depth, 0, 0, size, sky_of(textured, camera, half, focal), air,
    Whole{quads.turned(odd(levels),
      frame_quads(groups, camera, half, focal, size, over, among, behind, textured, air, level))})

def tiles_frame_all(groups: List<&2, Group>, +camera: Voxel.Camera, +half: F32,
  +focal: F32, +size: U32, +depth: Nat, +tile: Nat, over: Quads, behind: Quads,
  +textured: Bool, +air: U32, level: U32) -> Flat:
  tiles_frame_among(groups, camera, half, focal, size, depth, tile, over, [], behind, textured,
    air, level)

def tiles_frame_with(faces: List<&2, Face.Face>, +camera: Voxel.Camera, +half: F32,
  +focal: F32, +size: U32, +depth: Nat, +tile: Nat, over: Quads, +textured: Bool) -> Flat:
  tiles_frame_all(one_group(faces), camera, half, focal, size, depth, tile, over, QNil{},
    textured, Sky.day_air(), Sky.full_level())

def tiles_frame_at(faces: List<&2, Face.Face>, +camera: Voxel.Camera, +half: F32,
  +focal: F32, +size: U32, +depth: Nat, +tile: Nat) -> Flat:
  tiles_frame_with(faces, camera, half, focal, size, depth, tile, QNil{}, False{})

def tiles_frame(faces: List<&2, Face.Face>, +camera: Voxel.Camera, +half: F32, +focal: F32,
  +size: U32, +depth: Nat) -> Flat:
  tiles_frame_at(faces, camera, half, focal, size, depth, tile_of(depth))

# Every cell of a one-tile frame as the colour it shows.
def resolved.done(read: Array<U32> & U32) -> Array<U32>:
  (frame, cell) = read
  frame

def resolved.next(read: Array<U32> & U32, +at: U32, +size: U32, +sky: U32, +air: U32) -> Array<U32> & U32:
  (frame, cell) = read
  (frame[at] <- shown(cell, U32.div(at, size), size, sky, air))[U32.mod(U32.add(at, 1), U32.mul(size, size))]

def resolved(remaining: Nat, +at: U32, +size: U32, +sky: U32, +air: U32, read: Array<U32> & U32) -> Array<U32>:
  match remaining:
    case 0n:
      resolved.done(read)
    case 1n+r:
      resolved(r, U32.add(at, 1), size, sky, air, resolved.next(read, at, size, sky, air))

# The whole frame's pixels in one array, row-major: the one-tile frame, each cell as the
# colour it shows. This is what the gate reads a pixel from.
def frame_pixels_among(groups: List<&2, Group>, +camera: Voxel.Camera, +half: F32,
  +focal: F32, +size: U32, +depth: Nat, over: Quads, among: List<&2, Drawn>, behind: Quads,
  +textured: Bool, +air: U32, level: U32) -> Array<U32>:
  resolved(U32.to_nat(U32.mul(size, size)), 0, size, sky_of(textured, camera, half, focal), air,
    tile.painted(depth, 0, 0, size,
      frame_quads(groups, camera, half, focal, size, over, among, behind, textured, air, level))[0])

def frame_pixels_all(groups: List<&2, Group>, +camera: Voxel.Camera, +half: F32,
  +focal: F32, +size: U32, +depth: Nat, over: Quads, behind: Quads,
  +textured: Bool, +air: U32, level: U32) -> Array<U32>:
  frame_pixels_among(groups, camera, half, focal, size, depth, over, [], behind, textured, air,
    level)

def frame_pixels_with(faces: List<&2, Face.Face>, +camera: Voxel.Camera, +half: F32,
  +focal: F32, +size: U32, +depth: Nat, over: Quads, +textured: Bool) -> Array<U32>:
  frame_pixels_all(one_group(faces), camera, half, focal, size, depth, over, QNil{}, textured,
    Sky.day_air(), Sky.full_level())

def frame_pixels(faces: List<&2, Face.Face>, +camera: Voxel.Camera, +half: F32, +focal: F32,
  +size: U32, +depth: Nat) -> Array<U32>:
  frame_pixels_with(faces, camera, half, focal, size, depth, QNil{}, False{})

# The client's frame: the scene textured, in 64-pixel tiles, under an overlay.
def paint_scene_at(faces: List<&2, Face.Face>, +eye: Voxel.Vec, +yaw: F32, +pitch: F32,
  +depth: Nat, over: Quads) -> Image:
  +camera : Voxel.Camera = Voxel.Camera.look(eye, yaw, pitch)
  +half = Voxel.projection_half(depth)
  +focal = F32.mul(1.5, half)
  +size = U32.shln((1 : U32), depth)
  image.of(tiles_frame_with(faces, camera, half, focal, size, depth, tile_of(depth), over,
    True{}))

# The frame in flat colours at an explicit depth, in tiles and as one tile, which is what
# `lab/native/paint/run.sh` prices against each other.
def paint_tiles_at(faces: List<&2, Face.Face>, +eye: Voxel.Vec, +yaw: F32, +pitch: F32,
  +depth: Nat) -> Image:
  +camera : Voxel.Camera = Voxel.Camera.look(eye, yaw, pitch)
  +half = Voxel.projection_half(depth)
  +focal = F32.mul(1.5, half)
  +size = U32.shln((1 : U32), depth)
  image.of(tiles_frame(faces, camera, half, focal, size, depth))

def paint_whole_at(faces: List<&2, Face.Face>, +eye: Voxel.Vec, +yaw: F32, +pitch: F32,
  +depth: Nat) -> Image:
  +camera : Voxel.Camera = Voxel.Camera.look(eye, yaw, pitch)
  +half = Voxel.projection_half(depth)
  +focal = F32.mul(1.5, half)
  +size = U32.shln((1 : U32), depth)
  image.of(tiles_frame_at(faces, camera, half, focal, size, depth, depth))
