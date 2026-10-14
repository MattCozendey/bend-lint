# world: the ground plane and the rail ribbon, as per-frame triangle soup.
#
# groundProg and trackProg in the reference compute their geometry inside the
# vertex shader: the vertex buffer is a bare grid and every position falls out
# of trackX/trackY/terrain.  Here that grid is unrolled into triangles that
# already carry world position, normal and colour, so the rasteriser consumes
# exactly the triangles the GPU would have assembled -- no shader, no buffer.
#
# Both grids come from buildGrid() (night-train-webgl.html:664): the vertex at
# (i, j) is verts[j*(cols+1)+i], and each cell pushes idx a, c, b, b, c, d with
# a = (i, j), b = (i+1, j), c = (i, j+1), d = (i+1, j+1).  The first triangle
# below is (a, c, b), not (a, b, c): the winding is the reference's.
import Base
import ./geo.bend as Geo
import ./trk.bend as Trk


# A point on the ground grid, and (reused) a normal: both are just three F32
# and the rasteriser never needs to tell them apart.
type Gp is Data:
  Gp{x: F32, y: F32, z: F32}


# One of the eight track lanes.  The reference picks off/h/colour with an
# if/else chain on the lane number; here the chain is resolved once per strip
# and the lane carries the result.  `sag` is 0 for every lane but the two
# contact wires, so track.v can apply the sag formula unconditionally: the
# reference computes sin(fract(s/44)*PI)*0.9 inside its wire branch, and
# sin(...)*0.0 is exactly 0.0 on the other lanes.
type Lane is Data:
  Lane{off: F32, yoff: F32, sag: F32, cr: F32, cg: F32, cb: F32}


def Lane.bed(+off: F32) -> Lane:
  Lane{off, (0.0 - 0.62 : F32), 0.0, 0.085, 0.078, 0.070}


def Lane.rail(+off: F32) -> Lane:
  Lane{off, (0.0 - 0.02 : F32), 0.0, 0.38, 0.40, 0.44}


def Lane.wire(+off: F32) -> Lane:
  Lane{off, 5.15, 0.9, 0.10, 0.10, 0.11}


# ---- ground ----------------------------------------------------------
def Gp.x(p: Gp) -> F32:
  Gp{x, y, z} = p
  x


def Gp.y(p: Gp) -> F32:
  Gp{x, y, z} = p
  y


def Gp.z(p: Gp) -> F32:
  Gp{x, y, z} = p
  z


# groundProg's groundPoint(): t runs along the path, g across it.  The t^2.2
# keeps more resolution ahead of the camera than behind it; the |g|^1.7 widens
# the rows towards the frame edges.  z is the path coordinate s, so terrain
# takes (x, s), exactly as the shader's terrain(x, p.z) does.
def World.pt(+t: F32, +g: F32, +s: F32) -> Gp:
  +ahead = (F32.pow(t, 2.2) * 1250.0 - 330.0 : F32)
  +z = (s + ahead : F32)
  # At g = 0 GLSL's sign() is 0 while S.sign is +1, but |g|^1.7 is 0 there, so
  # the side is 0 either way -- the two paths agree exactly.
  +side = (Trk.S.sign(g) * F32.pow(F32.abs(g), 1.7) * 430.0 : F32)
  +x = (Trk.Track.x(z) + side : F32)
  Gp{x, Trk.T.terrain(x, z), z}


# The shader builds the normal from two perturbed ground points and flips it
# to face up.  S.sign returns -1 exactly for a negative argument, which is the
# reference's `if (n.y < 0.0) n = -n`; at n.y = 0 both keep the vector.
def World.nrm(p0: Gp, pt: Gp, pz: Gp) -> Gp:
  Gp{+x0, +y0, +z0} = p0
  Gp{+x1, +y1, +z1} = pt
  Gp{+x2, +y2, +z2} = pz
  +ux = (x2 - x0 : F32)
  +uy = (y2 - y0 : F32)
  +uz = (z2 - z0 : F32)
  +vx = (x1 - x0 : F32)
  +vy = (y1 - y0 : F32)
  +vz = (z1 - z0 : F32)
  +cx = (uy * vz - uz * vy : F32)
  +cy = (uz * vx - ux * vz : F32)
  +cz = (ux * vy - uy * vx : F32)
  +l = F32.sqrt((cx * cx + cy * cy + cz * cz : F32))
  +ny = (cy / l : F32)
  +sg = Trk.S.sign(ny)
  Gp{(cx / l * sg : F32), (ny * sg : F32), (cz / l * sg : F32)}


# Per-vertex colour from groundProg: wet gravel near the rails, darker grass
# away from them, multiplied by the fbm blotch.  Colour is a vertex attribute,
# so it is evaluated at p, not interpolated from a face.
def World.wvtx(p: Gp, +nx: F32, +ny: F32, +nz: F32) -> Geo.WVtx:
  Gp{+x, +y, +z} = p
  +wet = Trk.S.smooth(0.0, 26.0, F32.abs((x - Trk.Track.x(z) : F32)))
  +cr = Trk.S.mix(0.105, 0.070, wet)
  +cg = Trk.S.mix(0.125, 0.092, wet)
  +cb = Trk.S.mix(0.108, 0.120, wet)
  +blotch = Trk.H.fbm((x * 0.03 : F32), (z * 0.03 : F32))
  +k = (0.75 + blotch * 0.6 : F32)
  Geo.Vx.at(x, y, z, nx, ny, nz, (cr * k : F32), (cg * k : F32),
    (cb * k : F32), 0.0)


def World.gvtx(+t: F32, +g: F32, +s: F32) -> Geo.WVtx:
  +p = World.pt(t, g, s)
  +pt = World.pt((t + 0.0015 : F32), g, s)
  +pz = World.pt(t, (g + 0.004 : F32), s)
  +n = World.nrm(p, pt, pz)
  World.wvtx(p, Gp.x(n), Gp.y(n), Gp.z(n))


# One grid cell: a = (i, j), b = (i+1, j), c = (i, j+1), d = (i+1, j+1), so
# (a, c, b) then (b, c, d).  `n` counts the 96 columns down; k is therefore the
# column index i.  `+j` is the row index, carried unchanged.
def World.ground.cell(+n: Nat, +j: Nat, +s: F32, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +fi = U32.to_f32(U32.from_nat(k))
      +fj = U32.to_f32(U32.from_nat(j))
      +t = (fi / 96.0 : F32)
      +t2 = ((fi + 1.0 : F32) / 96.0 : F32)
      +g = (0.0 - 1.0 + fj * 2.0 / 120.0 : F32)
      +g2 = (0.0 - 1.0 + (fj + 1.0 : F32) * 2.0 / 120.0 : F32)
      +va = World.gvtx(t, g, s)
      +vb = World.gvtx(t2, g, s)
      +vc = World.gvtx(t, g2, s)
      +vd = World.gvtx(t2, g2, s)
      World.ground.cell(k, j, s,
        Geo.WTri{va, vc, vb} <> (Geo.WTri{vb, vc, vd} <> acc))


# `n` counts the 120 rows down, so k is the row index j.  96n columns per row.
def World.ground.row(+n: Nat, +s: F32, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+k:
      World.ground.row(k, s, World.ground.cell(96n, k, s, acc))


# buildGrid(96, 120, 0.0, 1.0, -1.0, 1.0): 96*120*2 = 23040 triangles.
def World.ground(+s: F32, +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  World.ground.row(120n, s, acc)


# A run of rows with an explicit start index: it walks the rows downward from
# `j`, so the prepend fold leaves the run in ascending order j-n+1 .. j, exactly
# as the full descending World.ground.row fold leaves that slice.  A run needs
# a start because each branch owns its own accumulator.
def World.ground.run(+n: Nat, +j: Nat, +s: F32, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+k:
      World.ground.run(k, Nat.sub(j, 1n), s,
        World.ground.cell(96n, j, s, acc))


# ---- track -----------------------------------------------------------
# trackProg's vertex: the lane's offset is applied across the curve normal
# (cos/sin of the yaw), and h is trackY plus the lane's offset and sag.
def World.track.v(lane: Lane, +t: F32, +s: F32) -> Geo.WVtx:
  Lane{+off, +yoff, +sag, +cr, +cg, +cb} = lane
  +yaw = Trk.Track.yaw(s)
  +x = (Trk.Track.x(s) + off * F32.cos(yaw) : F32)
  +z = (s - off * F32.sin(yaw) : F32)
  +k = Trk.S.fract((s / 44.0 : F32))
  +h = (Trk.Track.y(s) + yoff - F32.sin((k * 3.14159 : F32)) * sag : F32)
  Geo.Vx.at(x, h, z, 0.0, 1.0, 0.0, cr, cg, cb, 0.0)


# One cell of one strip: v(row, t), v(row+1, t), v(row, t2), v(row+1, t2),
# wound (a, c, b) then (b, c, d) as on the ground, with `a` the lower lane.
def World.track.cell(+n: Nat, +la: Lane, +lb: Lane, +s: F32,
  +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +fi = U32.to_f32(U32.from_nat(k))
      +t = (fi / 420.0 : F32)
      +t2 = ((fi + 1.0 : F32) / 420.0 : F32)
      +sa = (s - 330.0 + F32.pow(t, 1.9) * 1100.0 : F32)
      +sb = (s - 330.0 + F32.pow(t2, 1.9) * 1100.0 : F32)
      +va = World.track.v(la, t, sa)
      +vb = World.track.v(lb, t, sa)
      +vc = World.track.v(la, t2, sb)
      +vd = World.track.v(lb, t2, sb)
      World.track.cell(k, la, lb, s,
        Geo.WTri{va, vb, vc} <> (Geo.WTri{vc, vb, vd} <> acc))


# buildGrid(420, 7, 0, 1, 0, 7) draws only the strips (0,1), (2,3), (4,5),
# (6,7): the ballast edges, the two rails, then the contact wire.  Four 420-cell
# ribbons, two triangles each, is 3360 triangles.
def World.track(+s: F32, +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  +a0 = World.track.cell(420n, Lane.bed((0.0 - 4.6 : F32)), Lane.bed(4.6), s,
    acc)
  +a1 = World.track.cell(420n, Lane.rail((0.0 - 0.79 : F32)),
    Lane.rail((0.0 - 0.65 : F32)), s, a0)
  +a2 = World.track.cell(420n, Lane.rail(0.65), Lane.rail(0.79), s, a1)
  World.track.cell(420n, Lane.wire((0.0 - 0.14 : F32)), Lane.wire(0.14), s, a2)


# The world's eight independent pieces as chunks: four track ribbons and four
# runs of 30 ground rows.  The parallel let hands the pieces to the worker
# threads as one static split, each branch folding its own accumulator, and the
# chunk list's concatenation is byte-for-byte the serial soup: the track lanes
# are ordered wire, rail-right, rail-left, bed because that is the order the
# serial track fold prepends them, and the ground runs are ordered so their
# ascending slices join into rows 0 .. 119.  Draw order is visible through
# exact-depth ties, so reproducing it matters for the digest.  The serial
# World.ground.row / World.track folds behind the single-accumulator entry
# points are deliberately left alone.
#
# The four ribbons here are the part of the world the cull leaves alone; the
# ground's four chunks come from World.ground.chunks, and the two lists are
# kept apart because Raster.frame culls one and not the other.
def World.chunks(+s: F32) -> List<&2, List<&2, Geo.WTri>>:
  t0 t1 t2 t3 =
    World.track.cell(420n, Lane.wire((0.0 - 0.14 : F32)), Lane.wire(0.14), s, [])
    World.track.cell(420n, Lane.rail(0.65), Lane.rail(0.79), s, [])
    World.track.cell(420n, Lane.rail((0.0 - 0.79 : F32)),
      Lane.rail((0.0 - 0.65 : F32)), s, [])
    World.track.cell(420n, Lane.bed((0.0 - 4.6 : F32)), Lane.bed(4.6), s, [])
  [t0, t1, t2, t3]


# The ground in the same four runs, whose ascending slices join into rows
# 0 .. 119.  It is a chunk list of its own so the chunked driver can cull it
# without disturbing the track.
def World.ground.chunks(+s: F32) -> List<&2, List<&2, Geo.WTri>>:
  g0 g1 g2 g3 =
    World.ground.run(30n, 29n, s, [])
    World.ground.run(30n, 59n, s, [])
    World.ground.run(30n, 89n, s, [])
    World.ground.run(30n, 119n, s, [])
  [g0, g1, g2, g3]


def World.emit(+s: F32, +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  World.track(s, World.ground(s, acc))
