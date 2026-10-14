# rt: the rasteriser's types and its camera.
#
# The camera is the demo's: M4.lookAt(cam, cam + dir, +Y) and
# M4.perspective(fov, W/H, 0.15, 1500).  Writing the projection out by hand
# instead of multiplying matrices buys two things -- the per-vertex work is
# three dot products, and the near plane can be clipped in the same space the
# depth test will use.
#
# Screen coordinates are window coordinates: pixel (x, y) has its centre at
# (x + 0.5, y + 0.5), y growing downwards, exactly as the PPM writer wants
# them.  Depth is carried as 1/w, which is what a perspective divide makes
# linear across a triangle -- so it interpolates correctly with no correction,
# and a larger 1/w means nearer, which is what the depth test needs.
import Base
import ./geo.bend as Geo
import ./trk.bend as Trk


type VCam is Data:
  VCam{ex: F32, ey: F32, ez: F32, rx: F32, ry: F32, rz: F32, ux: F32, uy: F32,
    uz: F32, fx: F32, fy: F32, fz: F32, k: F32, hw: F32, hh: F32}


# A vertex after projection: the world vertex the fragment shader will need,
# plus where it landed on the screen and 1/w.  The world attributes stay in
# their own constructor rather than being flattened in, because Bend patterns
# name every field -- one four-field pattern here keeps the depth pass short,
# and the shading pass destructures the pair.
type Vtx is Data:
  Vtx{at: Geo.WVtx, sx: F32, sy: F32, iw: F32}


type Tri is Data:
  Tri{a: Vtx, b: Vtx, c: Vtx, bx0: F32, by0: F32, bx1: F32, by1: F32}


# A shaded fragment: the same attributes, interpolated at a pixel.
type Frag is Data:
  Frag{wx: F32, wy: F32, wz: F32, nx: F32, ny: F32, nz: F32, cr: F32, cg: F32,
    cb: F32, e: F32, iw: F32}


type P3 is Data:
  P3{dx: F32, dy: F32, dz: F32}


def S.fovy.b(tall: Bool) -> F32:
  match tall:
    case True{}:
      1.20
    case False{}:
      1.12


def S.fovy(+w: U32, +h: U32) -> F32:
  S.fovy.b(U32.is_lt(w, h))


def S.mix(+a: F32, +b: F32, +t: F32) -> F32:
  (a + (b - a) * t : F32)


def S.smooth(+a: F32, +b: F32, +x: F32) -> F32:
  +t = F32.clamp(((x - a : F32) / (b - a : F32) : F32), 0.0, 1.0)
  (t * t * (3.0 - 2.0 * t) : F32)


def S.if1(yes: Bool, +a: F32, +b: F32) -> F32:
  match yes:
    case True{}:
      a
    case False{}:
      b


# ---- the camera ------------------------------------------------------
# `side` is the distance to the left of the centreline (the demo's
# -sideOffset: 2.15 + lean*2.45, i.e. 4.6 at lean = 1), `hgt` the height above
# the rail head, `yaw` the head turn away from the track and `pitch` its tilt.
def VCam.ride(+w: U32, +h: U32, +s: F32, +side: F32, +hgt: F32, +yaw: F32,
  +pitch: F32) -> VCam:
  +base = Trk.Track.yaw(s)
  +cb = F32.cos(base)
  +sb = F32.sin(base)
  +ex = (Trk.Track.x(s) - side * cb : F32)
  +ez = (s + side * sb : F32)
  +ey = (Trk.Track.y(s) + hgt : F32)
  +ly = (base + yaw : F32)
  +cp = F32.cos(pitch)
  +fx = (F32.sin(ly) * cp : F32)
  +fy = F32.sin(pitch)
  +fz = (F32.cos(ly) * cp : F32)
  # z = cam - centre = -f ; x = normalise(cross(+Y, z)) = (z.z, 0, -z.x) ;
  # y = cross(z, x).  M4.lookAt, written out.
  +zx = (0.0 - fx : F32)
  +zy = (0.0 - fy : F32)
  +zz = (0.0 - fz : F32)
  +rl = F32.sqrt((zz * zz + zx * zx : F32))
  +rx = (zz / rl : F32)
  +rz = ((0.0 - zx : F32) / rl : F32)
  +ux = (zy * rz - zz * 0.0 : F32)
  +uy = (zz * rx - zx * rz : F32)
  +uz = (zx * 0.0 - zy * rx : F32)
  +k = ((U32.to_f32(h) * 0.5 : F32) / F32.tan((S.fovy(w, h) * 0.5 : F32)) : F32)
  VCam{ex, ey, ez, rx, 0.0, rz, ux, uy, uz, fx, fy, fz, k,
    (U32.to_f32(w) * 0.5 : F32), (U32.to_f32(h) * 0.5 : F32)}


# The distance along the view axis -- the projection's w, and the quantity the
# near plane cuts on.
def VCam.w(cam: VCam, +x: F32, +y: F32, +z: F32) -> F32:
  VCam{ex, ey, ez, rx, ry, rz, ux, uy, uz, fx, fy, fz, k, hw, hh} = cam
  (fx * (x - ex) + fy * (y - ey) + fz * (z - ez) : F32)


def VCam.pv.at(+cam: VCam, +x: F32, +y: F32, +z: F32, +nx: F32, +ny: F32,
  +nz: F32, +cr: F32, +cg: F32, +cb: F32, +e: F32) -> Vtx:
  VCam{ex, ey, ez, rx, ry, rz, ux, uy, uz, fx, fy, fz, k, hw, hh} = cam
  +dx = (x - ex : F32)
  +dy = (y - ey : F32)
  +dz = (z - ez : F32)
  +xv = (rx * dx + ry * dy + rz * dz : F32)
  +yv = (ux * dx + uy * dy + uz * dz : F32)
  +wv = (fx * dx + fy * dy + fz * dz : F32)
  +iw = (1.0 / wv : F32)
  Vtx{Geo.Vx.at(x, y, z, nx, ny, nz, cr, cg, cb, e),
    (hw + k * xv * iw : F32), (hh - k * yv * iw : F32), iw}


def VCam.pv(+cam: VCam, v: Geo.WVtx) -> Vtx:
  Geo.WVtx{x, y, z, nx, ny, nz, cr, cg, cb, e} = v
  VCam.pv.at(cam, x, y, z, nx, ny, nz, cr, cg, cb, e)


# The unit ray through a pixel centre.  From the projection: the ray is
# f + right*((sx - hw)/k) + up*((hh - sy)/k), because k is exactly the number
# of pixels one unit of x/w is worth.
def VCam.ray(+cam: VCam, +px: F32, +py: F32) -> P3:
  VCam{ex, ey, ez, rx, ry, rz, ux, uy, uz, fx, fy, fz, k, hw, hh} = cam
  +ax = ((px - hw : F32) / k : F32)
  +ay = ((hh - py : F32) / k : F32)
  +dx = (fx + rx * ax + ux * ay : F32)
  +dy = (fy + ry * ax + uy * ay : F32)
  +dz = (fz + rz * ax + uz * ay : F32)
  +il = (1.0 / F32.sqrt((dx * dx + dy * dy + dz * dz : F32)) : F32)
  P3{(dx * il : F32), (dy * il : F32), (dz * il : F32)}


# ---- the camera-space vertex -----------------------------------------
# Clipping has to happen before the perspective divide, and the divide is what
# makes screen coordinates useless for it: a vertex behind the camera projects
# to a mirrored point, so the cut cannot be done on the projected triangle.
# The camera-space vertex carries what the cut needs -- the right and up
# coordinates and the depth w, all three affine in the world position, so the
# cut is a plain lerp -- plus the world vertex itself, which the fragment
# shader interpolates with the same weights.
type Cv is Data:
  Cv{xv: F32, yv: F32, w: F32, at: Geo.WVtx}


def Cv.mk(+xv: F32, +yv: F32, +w: F32, +at: Geo.WVtx) -> Cv:
  Cv{xv, yv, w, at}


# The camera is used once per vertex, and `+` on the parameter lets the caller
# hand it to three projections without rebuilding it each time.
def VCam.cv(+cam: VCam, v: Geo.WVtx) -> Cv:
  # the match order follows the binder order: cam is the first parameter.
  VCam{ex, ey, ez, rx, ry, rz, ux, uy, uz, fx, fy, fz, k, hw, hh} = cam
  Geo.WVtx{+x, +y, +z, +nx, +ny, +nz, +cr, +cg, +cb, +e} = v
  +dx = (x - ex : F32)
  +dy = (y - ey : F32)
  +dz = (z - ez : F32)
  Cv{(rx * dx + ry * dy + rz * dz : F32), (ux * dx + uy * dy + uz * dz : F32),
    (fx * dx + fy * dy + fz * dz : F32),
    Geo.Vx.at(x, y, z, nx, ny, nz, cr, cg, cb, e)}


def Wvx.mix(a: Geo.WVtx, b: Geo.WVtx, +t: F32) -> Geo.WVtx:
  Geo.WVtx{+x1, +y1, +z1, +nx1, +ny1, +nz1, +cr1, +cg1, +cb1, +e1} = a
  Geo.WVtx{+x2, +y2, +z2, +nx2, +ny2, +nz2, +cr2, +cg2, +cb2, +e2} = b
  Geo.Vx.at((x1 + (x2 - x1) * t : F32), (y1 + (y2 - y1) * t : F32),
    (z1 + (z2 - z1) * t : F32), (nx1 + (nx2 - nx1) * t : F32),
    (ny1 + (ny2 - ny1) * t : F32), (nz1 + (nz2 - nz1) * t : F32),
    (cr1 + (cr2 - cr1) * t : F32), (cg1 + (cg2 - cg1) * t : F32),
    (cb1 + (cb2 - cb1) * t : F32), (e1 + (e2 - e1) * t : F32))


def Cv.mix(a: Cv, b: Cv, +t: F32) -> Cv:
  Cv{+x1, +y1, +w1, +at1} = a
  Cv{+x2, +y2, +w2, +at2} = b
  Cv{(x1 + (x2 - x1) * t : F32), (y1 + (y2 - y1) * t : F32),
    (w1 + (w2 - w1) * t : F32), Wvx.mix(at1, at2, t)}


def N.near() -> F32:
  0.15


# The clip parameter on an edge: w is affine in the world position, so the
# parameter that puts w on the near plane is the same one that interpolates
# every other attribute.
def Cv.t(+wa: F32, +wb: F32) -> F32:
  ((N.near() - wa : F32) / (wb - wa : F32) : F32)


# The screen mapping, applied last.  k is the number of pixels one unit of
# x/w is worth, and iw = 1/w is the depth key the rasteriser interpolates.
def VCam.to(+cam: VCam, c: Cv) -> Vtx:
  VCam{ex, ey, ez, rx, ry, rz, ux, uy, uz, fx, fy, fz, k, hw, hh} = cam
  Cv{xv, yv, w, at} = c
  +iw = (1.0 / w : F32)
  Vtx{at, (hw + k * xv * iw : F32), (hh - k * yv * iw : F32), iw}


# The screen bounding box of a projected triangle, computed once, at
# projection, and carried on the triangle.
#
# Both readers of it are hot: the quadtree's filter tests every triangle at
# every node it reaches, and the pixel's reject tests it once per pixel of the
# tile.  Rebuilt from the three Vtx records, that is three heap reads and six
# min/max per test; read off the triangle it is one record and four compares.
# Only the pair that passes the box ever needs the vertices.
def Tri.boxed(+a: Vtx, +b: Vtx, +c: Vtx) -> Tri:
  Vtx{at1, +sx1, +sy1, +iw1} = a
  Vtx{at2, +sx2, +sy2, +iw2} = b
  Vtx{at3, +sx3, +sy3, +iw3} = c
  Tri{Vtx{at1, sx1, sy1, iw1}, Vtx{at2, sx2, sy2, iw2}, Vtx{at3, sx3, sy3, iw3},
    F32.min(sx1, F32.min(sx2, sx3)), F32.min(sy1, F32.min(sy2, sy3)),
    F32.max(sx1, F32.max(sx2, sx3)), F32.max(sy1, F32.max(sy2, sy3))}


# Back-face culling, WebGL's own rule, taken in world space: a triangle faces
# the eye when its winding normal, cross(b - a, c - a), points back along
# eye - a.  The projected signed area has the same sign, so this is the test
# the device would make, one step earlier -- once per triangle, before the
# tree ever filters it, and without projecting what is about to be thrown away.
#
# It is not an optimisation here, it is half the picture.  The reference's
# ground is a sheet wound face-down, so WebGL drops it and the demo's lower
# half is the sky's below-horizon haze rather than grass.  Drawing that ground
# is what the rasteriser did before this test, and it is the largest single
# disagreement the two renderers had.
#
# The track ribbon is the one mesh the demo draws with `gl.disable(CULL_FACE)`,
# so it is the one mesh that does not come through here -- both of its faces are
# drawn, exactly as the device draws them.
def Tri.faces(t: Geo.WTri, +ex: F32, +ey: F32, +ez: F32) -> Bool:
  Geo.WTri{a, b, c} = t
  Geo.WVtx{+ax, +ay, +az, anx, any, anz, acr, acg, acb, ae} = a
  Geo.WVtx{+bx, +by, +bz, bnx, bny, bnz, bcr, bcg, bcb, be} = b
  Geo.WVtx{+cx, +cy, +cz, cnx, cny, cnz, ccr, ccg, ccb, ce} = c
  +ux = (bx - ax : F32)
  +uy = (by - ay : F32)
  +uz = (bz - az : F32)
  +vx = (cx - ax : F32)
  +vy = (cy - ay : F32)
  +vz = (cz - az : F32)
  +nx = (uy * vz - uz * vy : F32)
  +ny = (uz * vx - ux * vz : F32)
  +nz = (ux * vy - uy * vx : F32)
  F32.is_gt((nx * (ex - ax) + ny * (ey - ay) + nz * (ez - az) : F32), 0.0)


def Tri.cull.one(faces: Bool, t: Geo.WTri, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  match faces:
    case True{}:
      t <> acc
    case False{}:
      acc


def Tri.cull.go(ws: List<&2, Geo.WTri>, +ex: F32, +ey: F32, +ez: F32,
  +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  match ws:
    case []:
      acc
    case +t <> rest:
      Tri.cull.go(rest, ex, ey, ez,
        Tri.cull.one(Tri.faces(t, ex, ey, ez), t, acc))


def Tri.cull(ws: List<&2, Geo.WTri>, +cam: VCam,
  +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  VCam{ex, ey, ez, rx, ry, rz, ux, uy, uz, fx, fy, fz, k, hw, hh} = cam
  Tri.cull.go(ws, ex, ey, ez, acc)


# The same cull over a chunk list: each chunk is filtered on its own, and the
# chunks keep their order -- the projected list has to stay the serial one, or
# exact-depth ties would resolve differently.
def Tri.cull.chunks(cs: List<&2, List<&2, Geo.WTri>>, +cam: VCam,
  +acc: List<&2, List<&2, Geo.WTri>>) -> List<&2, List<&2, Geo.WTri>>:
  match cs:
    case []:
      acc
    case c <> rest:
      Tri.cull.chunks(rest, cam,
        List.append(&2, List<&2, Geo.WTri>, acc, [Tri.cull(c, cam, [])]))


def Tri.one(+cam: VCam, a: Cv, b: Cv, c: Cv) -> List<&2, Tri>:
  +va = VCam.to(cam, a)
  +vb = VCam.to(cam, b)
  +vc = VCam.to(cam, c)
  [Tri.boxed(va, vb, vc)]


# One vertex outside: cut the two edges that leave it, keep the corner.  Two
# outside: cut both edges into the surviving vertex.  The `+` on the three
# camera vertices is what the duplicated corner costs in the cut case -- a
# handful of triangles per frame, the ones the camera is standing on.
def Tri.cut(ia: Bool, ib: Bool, ic: Bool, +a: Cv, +b: Cv, +c: Cv, +wa: F32,
  +wb: F32, +wc: F32, +cam: VCam) -> List<&2, Tri>:
  match ia ib ic:
    case True{} True{} True{}:
      Tri.one(cam, a, b, c)
    case True{} True{} False{}:
      +p = Cv.mix(a, c, Cv.t(wa, wc))
      +q = Cv.mix(b, c, Cv.t(wb, wc))
      List.append(&2, Tri, Tri.one(cam, a, b, q), Tri.one(cam, a, q, p))
    case True{} False{} True{}:
      +p = Cv.mix(a, b, Cv.t(wa, wb))
      +q = Cv.mix(c, b, Cv.t(wc, wb))
      List.append(&2, Tri, Tri.one(cam, a, q, c), Tri.one(cam, a, p, q))
    case False{} True{} True{}:
      +p = Cv.mix(b, a, Cv.t(wb, wa))
      +q = Cv.mix(c, a, Cv.t(wc, wa))
      List.append(&2, Tri, Tri.one(cam, b, c, q), Tri.one(cam, b, q, p))
    case _ _ _:
      []


# The cut.  All three inside is the common case and costs nothing; the others
# hand the two or three points where the edges cross the near plane to the same
# projection.  Ordering the cases inside-first means the overlap test itself is
# done once, by the sum of the edge functions.
def Tri.cut.ca(ca: Cv, cb: Cv, cc: Cv, +cam: VCam) -> List<&2, Tri>:
  Cv{ax, ay, +aw, aat} = ca
  Cv{bx, by, +bw, bat} = cb
  Cv{cx, cy, +cw, cat} = cc
  Tri.cut(F32.is_ge(aw, N.near()), F32.is_ge(bw, N.near()),
    F32.is_ge(cw, N.near()), Cv.mk(ax, ay, aw, aat), Cv.mk(bx, by, bw, bat),
    Cv.mk(cx, cy, cw, cat), aw, bw, cw, cam)


def Tri.place(w: Geo.WTri, +cam: VCam) -> List<&2, Tri>:
  Geo.WTri{a, b, c} = w
  Tri.cut.ca(VCam.cv(cam, a), VCam.cv(cam, b), VCam.cv(cam, c), cam)


# A whole world-space mesh projected, one triangle at a time.
def Tri.emit.go(ws: List<&2, Geo.WTri>, +cam: VCam, +acc: List<&2, Tri>)
  -> List<&2, Tri>:
  match ws:
    case []:
      acc
    case t <> rest:
      Tri.emit.go(rest, cam, List.append(&2, Tri, Tri.place(t, cam), acc))


def Tri.emit(ws: List<&2, Geo.WTri>, +cam: VCam) -> List<&2, Tri>:
  Tri.emit.go(ws, cam, [])


# ---- the chunked projection -----------------------------------------
# The scene arrives as a short list of independent pieces of geometry.  Each
# chunk is emitted exactly as a whole soup would be, so the triangles (and their
# relative order) are the serial ones; the chunk list is then halved
# recursively and the two halves projected on separate workers.  The list is
# only ten to thirty entries, which is why List.take -- not tail recursive -- is
# safe here and must never be lifted onto a per-triangle list.
def Tri.chunk.len(xs: List<&2, List<&2, Geo.WTri>>, +acc: Nat) -> Nat:
  match xs:
    case []:
      acc
    case h <> rest:
      Tri.chunk.len(rest, Nat.add(acc, 1n))


# The depth is what makes termination checkable: the split itself is on a
# computed half, which the checker cannot see shrink, but the recursion argument
# `d` is a structural subterm (`k`).  Five levels cover up to 32 leaves, more
# than the 24 chunks the scene builds (world 8 + instanced 11 + consist 5); if a
# caller ever passes a longer list, anything still unsplit at the leaf is
# emitted serially, so nothing is dropped -- only the split is coarser.
def Tri.emit.chunks.all(cs: List<&2, List<&2, Geo.WTri>>, +cam: VCam)
  -> List<&2, Tri>:
  match cs:
    case []:
      []
    case c <> rest:
      List.append(&2, Tri, Tri.emit.chunks.all(rest, cam), Tri.emit(c, cam))


# The split's two halves come back in a constructor, not concatenated at the
# fork.  Joining them there -- `List.concat([b, a])`, the obvious way -- costs
# the fork its parallelism: a branch whose value is consumed by a strict fold at
# the fork site is evaluated on the fork's own thread, while one the caller
# forces later, out of a constructor field, is handed to another worker.  With
# the concat the whole projection of the world ran at 118% CPU; the flattening
# pass below is where the pieces are finally forced.
type Emit is Data:
  EmitOne{xs: List<&2, Tri>}
  EmitCat{l: Emit, r: Emit}


# Emitting walks a list left to right prepending, so emitting `left <> right`
# is emitting right first and then left; the halves are flattened in that order
# to keep the projected list identical to the serial one.
def Tri.emit.chunks.go(+d: Nat, +cs: List<&2, List<&2, Geo.WTri>>, +cam: VCam)
  -> Emit:
  match d:
    case 0n:
      EmitOne{Tri.emit.chunks.all(cs, cam)}
    case 1n+k:
      +n = Tri.chunk.len(cs, 0n)
      +half = Nat.div(n, 2n)
      +left = List.take(&2, List<&2, Geo.WTri>, cs, half)
      +right = List.drop(&2, List<&2, Geo.WTri>, cs, half)
      a b = Tri.emit.chunks.go(k, left, cam)
        Tri.emit.chunks.go(k, right, cam)
      EmitCat{a, b}


def Tri.emit.flat(e: Emit, +acc: List<&2, Tri>) -> List<&2, Tri>:
  match e:
    case EmitOne{xs}:
      List.append(&2, Tri, xs, acc)
    case EmitCat{l, r}:
      Tri.emit.flat(r, Tri.emit.flat(l, acc))


def Tri.emit.chunks(+cs: List<&2, List<&2, Geo.WTri>>, +cam: VCam)
  -> List<&2, Tri>:
  Tri.emit.flat(Tri.emit.chunks.go(5n, cs, cam), [])


# ---- additive billboards ---------------------------------------------
# The demo draws two more passes after the geometry: 1100 twinkling stars on
# a sphere of radius 900, and up to 440 glow sprites (window lights, the
# headlight and its beam, signals, fireflies, smoke).  Both are quads facing
# the camera whose fragment shader only looks at the distance from the centre,
# so each one is a screen-space disc: centre, radius in pixels, depth.
#
# kind 0 is a star -- drawn before the geometry, so it never occludes it and
# shows wherever nothing was rasterised.  kind 1 is a glow -- drawn after the
# geometry with the depth test on, so the train still hides the light behind
# it.
type Spr is Data:
  Spr{cx: F32, cy: F32, r: F32, iw: F32, cr: F32, cg: F32, cb: F32, a: F32,
    kind: U32}


def Spr.at.w(ok: Bool, +wv: F32, +xv: F32, +yv: F32, +radius: F32, +cr: F32,
  +cg: F32, +cb: F32, +a: F32, +kind: U32, +k: F32, +hw: F32, +hh: F32) -> Spr:
  match ok:
    case True{}:
      +iw = (1.0 / wv : F32)
      Spr{(hw + k * xv * iw : F32), (hh - k * yv * iw : F32),
        (k * radius * iw : F32), iw, cr, cg, cb, a, kind}
    case False{}:
      # behind the camera: a zero radius puts it out of reach of every pixel
      Spr{(0.0 - 100000.0 : F32), (0.0 - 100000.0 : F32), 0.0, (0.0 - 1.0 : F32),
        cr, cg, cb, a, kind}


# A billboard's quad is `radius` world units along the camera's right and up,
# so its screen radius is k*radius/w -- the same k that turns x/w into pixels.
def Spr.at(+cam: VCam, +x: F32, +y: F32, +z: F32, +radius: F32, +cr: F32,
  +cg: F32, +cb: F32, +a: F32, +kind: U32) -> Spr:
  VCam{ex, ey, ez, rx, ry, rz, ux, uy, uz, fx, fy, fz, k, hw, hh} = cam
  +dx = (x - ex : F32)
  +dy = (y - ey : F32)
  +dz = (z - ez : F32)
  +wv = (fx * dx + fy * dy + fz * dz : F32)
  Spr.at.w(F32.is_ge(wv, N.near()), wv, (rx * dx + ry * dy + rz * dz : F32),
    (ux * dx + uy * dy + uz * dz : F32), radius, cr, cg, cb, a, kind, k, hw, hh)


# A star sits at uCam + dir*900, so its depth is 900*(dir . f) and the disc is
# `size` units across there.
def Spr.star(+cam: VCam, +dx: F32, +dy: F32, +dz: F32, +size: F32, +cr: F32,
  +cg: F32, +cb: F32, +a: F32) -> Spr:
  # the camera is read for its eye and handed on whole, so it is destructured
  # once and rebuilt for the projection rather than read twice
  VCam{+ex, +ey, +ez, rx, ry, rz, ux, uy, uz, fx, fy, fz, k, hw, hh} = cam
  Spr.at(VCam{ex, ey, ez, rx, ry, rz, ux, uy, uz, fx, fy, fz, k, hw, hh},
    (ex + dx * 900.0 : F32), (ey + dy * 900.0 : F32), (ez + dz * 900.0 : F32),
    size, cr, cg, cb, a, 0)


def Fr.iw(f: Frag) -> F32:
  Frag{wx, wy, wz, nx, ny, nz, cr, cg, cb, e, iw} = f
  iw


# The "nothing has been hit" fragment the per-pixel fold starts from.
def Frag.zero() -> Frag:
  Frag{0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}
