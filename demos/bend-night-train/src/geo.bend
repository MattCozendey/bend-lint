# geo: the geometry vocabulary of the rasteriser.
#
# The reference renderer sends every vertex through a vertex shader.  Here the
# same arithmetic is plain Bend, and the shapes are explicit triangle lists.
#
#   Geo   -- a triangle in local space (position + normal), no colour.  The
#            shared primitives (box, cone, pine, gable) are built once and
#            stamped thousands of times per frame.
#   WTri  -- a triangle in world space with per-vertex colour and emissive.
#            Everything the rasteriser sees per frame is a WTri.
#
# The Place functions exist because the demo has two vertex paths that
# disagree about normals: coloredBuilder divides the normal by the scale it
# applied to the position, instProg does not.  Copying the quirk matters --
# the instanced boxes are shaded by it.
import Base

type GPt is Data:
  GPt{x: F32, y: F32, z: F32, nx: F32, ny: F32, nz: F32}


type Geo is Data:
  Geo{a: GPt, b: GPt, c: GPt}


type WVtx is Data:
  WVtx{x: F32, y: F32, z: F32, nx: F32, ny: F32, nz: F32, cr: F32, cg: F32,
    cb: F32, e: F32}


type WTri is Data:
  WTri{a: WVtx, b: WVtx, c: WVtx}


# A whole primitive's transform in one record: the scale, the translation and
# the flat colour the demo passes to b.box()/b.add().  Passed down the
# recursion as a value instead of ten loose parameters.
type Style is Data:
  Style{sx: F32, sy: F32, sz: F32, tx: F32, ty: F32, tz: F32, cr: F32, cg: F32,
    cb: F32, e: F32}


# ---- small numbers ---------------------------------------------------
# Negative F32 literals do not parse in Bend: `-0.5` is a syntax error, and
# `(0.0 - 0.5 : F32)` at every one of the demo's many minus-halves is noise.
def Ng.of(+x: F32) -> F32:
  (0.0 - x : F32)


def N.pi() -> F32:
  3.141592653589793


def N.tau() -> F32:
  6.283185307179586


# Math.hypot(...)||1 in the demo's coloredBuilder: a zero-length normal falls
# back to 1 instead of dividing by zero.
def Ng.if0(zero: Bool, +l: F32) -> F32:
  match zero:
    case True{}:
      1.0
    case False{}:
      l


def Ng.len(+x: F32, +y: F32, +z: F32) -> F32:
  +l = F32.sqrt((x * x + y * y + z * z : F32))
  Ng.if0(F32.is_eq(l, 0.0), l)


# ---- constructors ----------------------------------------------------
def Pt.at(+x: F32, +y: F32, +z: F32, +nx: F32, +ny: F32, +nz: F32) -> GPt:
  GPt{x, y, z, nx, ny, nz}


def Pt.flat(+x: F32, +y: F32, +z: F32, +nx: F32, +ny: F32, +nz: F32) -> GPt:
  GPt{x, y, z, nx, ny, nz}


def Vx.at(+x: F32, +y: F32, +z: F32, +nx: F32, +ny: F32, +nz: F32, +cr: F32,
  +cg: F32, +cb: F32, +e: F32) -> WVtx:
  WVtx{x, y, z, nx, ny, nz, cr, cg, cb, e}


# A quad, wound the way buildGrid winds one: (a,b,c) then (a,c,d).  The two
# triangles carry the same vertex attributes, so an interpolated attribute is
# continuous across them whatever the winding does.
def Geo.quad(+a: GPt, +b: GPt, +c: GPt, +d: GPt) -> List<&2, Geo>:
  Geo{a, b, c} <> [Geo{a, c, d}]


def WTri.quad(+a: WVtx, +b: WVtx, +c: WVtx, +d: WVtx) -> List<&2, WTri>:
  WTri{a, b, c} <> [WTri{a, c, d}]


# ---- accessors -------------------------------------------------------
# Bend has no field accessor syntax; every read goes through a def.  They are
# gathered here so no other file has to invent a name for the same thing.

def Geo.pa(g: Geo) -> GPt:
  Geo{a, b, c} = g
  a


def Geo.pb(g: Geo) -> GPt:
  Geo{a, b, c} = g
  b


def Geo.pc(g: Geo) -> GPt:
  Geo{a, b, c} = g
  c


def Pt.x(p: GPt) -> F32:
  GPt{x, y, z, nx, ny, nz} = p
  x


def Pt.y(p: GPt) -> F32:
  GPt{x, y, z, nx, ny, nz} = p
  y


def Pt.z(p: GPt) -> F32:
  GPt{x, y, z, nx, ny, nz} = p
  z


def Pt.nx(p: GPt) -> F32:
  GPt{x, y, z, nx, ny, nz} = p
  nx


def Pt.ny(p: GPt) -> F32:
  GPt{x, y, z, nx, ny, nz} = p
  ny


def Pt.nz(p: GPt) -> F32:
  GPt{x, y, z, nx, ny, nz} = p
  nz


def WTri.wa(t: WTri) -> WVtx:
  WTri{a, b, c} = t
  a


def WTri.wb(t: WTri) -> WVtx:
  WTri{a, b, c} = t
  b


def WTri.wc(t: WTri) -> WVtx:
  WTri{a, b, c} = t
  c


# ---- the shared primitives -------------------------------------------
# Every one is the demo's mesh, vertex for vertex: boxMesh() is 6 quads with a
# flat normal each; coneMesh(7) is a 7-triangle fan; pineMesh() is 5 tiers of
# 10 jittered skirt triangles; gableMesh() is 6 triangles with face normals
# from a cross product.

def G.box() -> List<&2, Geo>:
  List.concat(&2, Geo, [Geo.quad(
      Pt.at(Ng.of(0.5), Ng.of(0.5), 0.5, 0.0, 0.0, 1.0),
      Pt.at(0.5, Ng.of(0.5), 0.5, 0.0, 0.0, 1.0),
      Pt.at(0.5, 0.5, 0.5, 0.0, 0.0, 1.0),
      Pt.at(Ng.of(0.5), 0.5, 0.5, 0.0, 0.0, 1.0)),
    Geo.quad(
      Pt.at(0.5, Ng.of(0.5), Ng.of(0.5), 0.0, 0.0, Ng.of(1.0)),
      Pt.at(Ng.of(0.5), Ng.of(0.5), Ng.of(0.5), 0.0, 0.0, Ng.of(1.0)),
      Pt.at(Ng.of(0.5), 0.5, Ng.of(0.5), 0.0, 0.0, Ng.of(1.0)),
      Pt.at(0.5, 0.5, Ng.of(0.5), 0.0, 0.0, Ng.of(1.0))),
    Geo.quad(
      Pt.at(0.5, Ng.of(0.5), 0.5, 1.0, 0.0, 0.0),
      Pt.at(0.5, Ng.of(0.5), Ng.of(0.5), 1.0, 0.0, 0.0),
      Pt.at(0.5, 0.5, Ng.of(0.5), 1.0, 0.0, 0.0),
      Pt.at(0.5, 0.5, 0.5, 1.0, 0.0, 0.0)),
    Geo.quad(
      Pt.at(Ng.of(0.5), Ng.of(0.5), Ng.of(0.5), Ng.of(1.0), 0.0, 0.0),
      Pt.at(Ng.of(0.5), Ng.of(0.5), 0.5, Ng.of(1.0), 0.0, 0.0),
      Pt.at(Ng.of(0.5), 0.5, 0.5, Ng.of(1.0), 0.0, 0.0),
      Pt.at(Ng.of(0.5), 0.5, Ng.of(0.5), Ng.of(1.0), 0.0, 0.0)),
    Geo.quad(
      Pt.at(Ng.of(0.5), 0.5, 0.5, 0.0, 1.0, 0.0),
      Pt.at(0.5, 0.5, 0.5, 0.0, 1.0, 0.0),
      Pt.at(0.5, 0.5, Ng.of(0.5), 0.0, 1.0, 0.0),
      Pt.at(Ng.of(0.5), 0.5, Ng.of(0.5), 0.0, 1.0, 0.0)),
    Geo.quad(
      Pt.at(Ng.of(0.5), Ng.of(0.5), Ng.of(0.5), 0.0, Ng.of(1.0), 0.0),
      Pt.at(0.5, Ng.of(0.5), Ng.of(0.5), 0.0, Ng.of(1.0), 0.0),
      Pt.at(0.5, Ng.of(0.5), 0.5, 0.0, Ng.of(1.0), 0.0),
      Pt.at(Ng.of(0.5), Ng.of(0.5), 0.5, 0.0, Ng.of(1.0), 0.0))])


# coneMesh(seg): apex at +0.5, base ring at -0.5, one normal per side.
def G.cone.go(+i: Nat, +seg: Nat, +acc: List<&2, Geo>) -> List<&2, Geo>:
  match i:
    case 0n:
      acc
    case 1n+k:
      +f = U32.to_f32(U32.from_nat(k))
      +fs = U32.to_f32(U32.from_nat(seg))
      +a0 = (f / fs * N.tau() : F32)
      +a1 = ((f + 1.0 : F32) / fs * N.tau() : F32)
      +x0 = (F32.cos(a0) * 0.5 : F32)
      +z0 = (F32.sin(a0) * 0.5 : F32)
      +x1 = (F32.cos(a1) * 0.5 : F32)
      +z1 = (F32.sin(a1) * 0.5 : F32)
      +mxn = ((x0 + x1) * 0.5 : F32)
      +mzn = ((z0 + z1) * 0.5 : F32)
      +nl = F32.sqrt((mxn * mxn + 0.1225 + mzn * mzn : F32))
      +nx = (mxn / nl : F32)
      +ny = (0.35 / nl : F32)
      +nz = (mzn / nl : F32)
      G.cone.go(k, seg, Geo{Pt.at(0.0, 0.5, 0.0, nx, ny, nz),
        Pt.at(x0, Ng.of(0.5), z0, nx, ny, nz),
        Pt.at(x1, Ng.of(0.5), z1, nx, ny, nz)} <> acc)


def G.cone(+seg: Nat) -> List<&2, Geo>:
  G.cone.go(seg, seg, [])


# pineMesh(): tier 0..4, ten skirt triangles each.  The radius jitter is baked
# per-vertex here, not per instance -- exactly as the demo does it.
def G.pine.seg(+i: Nat, +tier: Nat, +radius: F32, +bottom: F32, +height: F32,
  +acc: List<&2, Geo>) -> List<&2, Geo>:
  match i:
    case 0n:
      acc
    case 1n+k:
      +fi = U32.to_f32(U32.from_nat(k))
      +ft = U32.to_f32(U32.from_nat(tier))
      +a = (fi / 10.0 * N.tau() : F32)
      +b = ((fi + 1.0 : F32) / 10.0 * N.tau() : F32)
      +ra = (radius * (1.0 + F32.sin((fi * 19.7 + ft : F32)) * 0.14) : F32)
      +rb = (radius * (1.0 + F32.sin(((fi + 1.0 : F32) * 19.7 + ft : F32)) * 0.14)
        : F32)
      +top = (bottom + height : F32)
      +nx0 = F32.cos(((a + b) * 0.5 : F32))
      +nz0 = F32.sin(((a + b) * 0.5 : F32))
      +ny0 = (radius / height : F32)
      +nl = F32.sqrt((1.0 + ny0 * ny0 : F32))
      +nx = (nx0 / nl : F32)
      +ny = (ny0 / nl : F32)
      +nz = (nz0 / nl : F32)
      G.pine.seg(k, tier, radius, bottom, height,
        Geo{Pt.at(0.0, top, 0.0, nx, ny, nz),
          Pt.at((F32.cos(a) * ra : F32), bottom, (F32.sin(a) * ra : F32), nx, ny, nz),
          Pt.at((F32.cos(b) * rb : F32), bottom, (F32.sin(b) * rb : F32), nx, ny, nz)}
        <> acc)


# `t` counts the five tiers down, `i` is the tier index itself: a Nat pattern
# can only be 0n or 1n+k, so the counter and the index are separate.
def G.pine.tier(+t: Nat, +i: Nat, +acc: List<&2, Geo>) -> List<&2, Geo>:
  match t:
    case 0n:
      acc
    case 1n+k:
      +ft = U32.to_f32(U32.from_nat(i))
      +radius = (0.5 - ft * 0.087 : F32)
      +bottom = (Ng.of(0.5) + ft * 0.18 : F32)
      +height = (0.49 - ft * 0.025 : F32)
      G.pine.tier(k, Nat.add(i, 1n), G.pine.seg(10n, i, radius, bottom, height, acc))


def G.pine() -> List<&2, Geo>:
  G.pine.tier(5n, 0n, [])


# gableMesh(): a prism with face normals from the cross product; the winding
# of the two slopes is what makes the roof read as a roof.
def G.face(+ax: F32, +ay: F32, +az: F32, +bx: F32, +by: F32, +bz: F32, +cx: F32,
  +cy: F32, +cz: F32) -> Geo:
  +ux = (bx - ax : F32)
  +uy = (by - ay : F32)
  +uz = (bz - az : F32)
  +vx = (cx - ax : F32)
  +vy = (cy - ay : F32)
  +vz = (cz - az : F32)
  +nx0 = (uy * vz - uz * vy : F32)
  +ny0 = (uz * vx - ux * vz : F32)
  +nz0 = (ux * vy - uy * vx : F32)
  +l = Ng.len(nx0, ny0, nz0)
  +nx = (nx0 / l : F32)
  +ny = (ny0 / l : F32)
  +nz = (nz0 / l : F32)
  Geo{Pt.at(ax, ay, az, nx, ny, nz), Pt.at(bx, by, bz, nx, ny, nz),
    Pt.at(cx, cy, cz, nx, ny, nz)}


def G.gable() -> List<&2, Geo>:
  [G.face(Ng.of(0.5), Ng.of(0.5), Ng.of(0.5), 0.0, 0.5, Ng.of(0.5), 0.5,
      Ng.of(0.5), Ng.of(0.5)),
    G.face(Ng.of(0.5), Ng.of(0.5), 0.5, 0.5, Ng.of(0.5), 0.5, 0.0, 0.5, 0.5),
    G.face(Ng.of(0.5), Ng.of(0.5), Ng.of(0.5), Ng.of(0.5), Ng.of(0.5), 0.5, 0.0,
      0.5, 0.5),
    G.face(Ng.of(0.5), Ng.of(0.5), Ng.of(0.5), 0.0, 0.5, 0.5, 0.0, 0.5,
      Ng.of(0.5)),
    G.face(0.5, Ng.of(0.5), Ng.of(0.5), 0.0, 0.5, Ng.of(0.5), 0.0, 0.5, 0.5),
    G.face(0.5, Ng.of(0.5), Ng.of(0.5), 0.0, 0.5, 0.5, 0.5, Ng.of(0.5), 0.5)]


# ---- placing a mesh in the world -------------------------------------
# coloredBuilder's add(): position scaled and moved, normal divided by the
# same scale *and then renormalised* (Math.hypot(...)||1), so a squashed box
# still shades with a unit normal.
#
# The renormalisation is not cosmetic.  A carriage window pane is a box scaled
# to 12 mm across, so its side normal comes out of the division with length
# ~83; the shader's lambert term is |n|*cos(theta), and 83 times the window
# light is what painted the near carriage pure white while the reference kept
# it dark.
def Geo.vx.put(+st: Style, px: F32, py: F32, pz: F32, nx: F32, ny: F32,
  nz: F32) -> WVtx:
  Style{+sx, +sy, +sz, +tx, +ty, +tz, +cr, +cg, +cb, +e} = st
  +qx = (nx / sx : F32)
  +qy = (ny / sy : F32)
  +qz = (nz / sz : F32)
  +il = (1.0 / Ng.len(qx, qy, qz) : F32)
  Vx.at((px * sx + tx : F32), (py * sy + ty : F32), (pz * sz + tz : F32),
    (qx * il : F32), (qy * il : F32), (qz * il : F32), cr, cg, cb, e)


def Geo.place.go(ms: List<&2, Geo>, +st: Style, +acc: List<&2, WTri>)
  -> List<&2, WTri>:
  match ms:
    case []:
      acc
    case g <> rest:
      Geo{+a, +b, +c} = g
      +na = Geo.vx.put(st, Pt.x(a), Pt.y(a), Pt.z(a), Pt.nx(a), Pt.ny(a),
        Pt.nz(a))
      +nb = Geo.vx.put(st, Pt.x(b), Pt.y(b), Pt.z(b), Pt.nx(b), Pt.ny(b),
        Pt.nz(b))
      +nc = Geo.vx.put(st, Pt.x(c), Pt.y(c), Pt.z(c), Pt.nx(c), Pt.ny(c),
        Pt.nz(c))
      Geo.place.go(rest, st, WTri{na, nb, nc} <> acc)


def Geo.place(ms: List<&2, Geo>, st: Style) -> List<&2, WTri>:
  Geo.place.go(ms, st, [])


# instProg's path: the position is scaled and moved, the normal is left alone
# (the fragment shader normalises it).  A squashed instanced box therefore
# shades with the normal of the unscaled box -- the demo's behaviour, kept.
def Geo.inst.go(ms: List<&2, Geo>, +st: Style, +acc: List<&2, WTri>)
  -> List<&2, WTri>:
  match ms:
    case []:
      acc
    case g <> rest:
      Geo{+a, +b, +c} = g
      Style{+sx, +sy, +sz, +tx, +ty, +tz, +cr, +cg, +cb, +e} = st
      +na = Vx.at((Pt.x(a) * sx + tx : F32), (Pt.y(a) * sy + ty : F32),
        (Pt.z(a) * sz + tz : F32), Pt.nx(a), Pt.ny(a), Pt.nz(a), cr, cg, cb, e)
      +nb = Vx.at((Pt.x(b) * sx + tx : F32), (Pt.y(b) * sy + ty : F32),
        (Pt.z(b) * sz + tz : F32), Pt.nx(b), Pt.ny(b), Pt.nz(b), cr, cg, cb, e)
      +nc = Vx.at((Pt.x(c) * sx + tx : F32), (Pt.y(c) * sy + ty : F32),
        (Pt.z(c) * sz + tz : F32), Pt.nx(c), Pt.ny(c), Pt.nz(c), cr, cg, cb, e)
      Geo.inst.go(rest, st, WTri{na, nb, nc} <> acc)


def Geo.inst(ms: List<&2, Geo>, st: Style) -> List<&2, WTri>:
  Geo.inst.go(ms, st, [])


# The sleepers are the one instanced kind the demo rotates: p *= scale, then
# a yaw, then the move.
def Geo.inst.yaw.go(ms: List<&2, Geo>, +st: Style, +cc: F32, +ss: F32,
  +acc: List<&2, WTri>) -> List<&2, WTri>:
  match ms:
    case []:
      acc
    case g <> rest:
      Geo{+a, +b, +c} = g
      Style{+sx, +sy, +sz, +tx, +ty, +tz, +cr, +cg, +cb, +e} = st
      +ax = (Pt.x(a) * sx : F32)
      +ay = (Pt.y(a) * sy : F32)
      +az = (Pt.z(a) * sz : F32)
      +bx = (Pt.x(b) * sx : F32)
      +by = (Pt.y(b) * sy : F32)
      +bz = (Pt.z(b) * sz : F32)
      +cx = (Pt.x(c) * sx : F32)
      +cy = (Pt.y(c) * sy : F32)
      +cz = (Pt.z(c) * sz : F32)
      +na = Vx.at((ax * cc + az * ss + tx : F32), (ay + ty : F32),
        ((0.0 - ax * ss : F32) + az * cc + tz : F32),
        (Pt.nx(a) * cc + Pt.nz(a) * ss : F32), Pt.ny(a),
        ((0.0 - Pt.nx(a) * ss : F32) + Pt.nz(a) * cc : F32), cr, cg, cb, e)
      +nb = Vx.at((bx * cc + bz * ss + tx : F32), (by + ty : F32),
        ((0.0 - bx * ss : F32) + bz * cc + tz : F32),
        (Pt.nx(b) * cc + Pt.nz(b) * ss : F32), Pt.ny(b),
        ((0.0 - Pt.nx(b) * ss : F32) + Pt.nz(b) * cc : F32), cr, cg, cb, e)
      +nc = Vx.at((cx * cc + cz * ss + tx : F32), (cy + ty : F32),
        ((0.0 - cx * ss : F32) + cz * cc + tz : F32),
        (Pt.nx(c) * cc + Pt.nz(c) * ss : F32), Pt.ny(c),
        ((0.0 - Pt.nx(c) * ss : F32) + Pt.nz(c) * cc : F32), cr, cg, cb, e)
      Geo.inst.yaw.go(rest, st, cc, ss, WTri{na, nb, nc} <> acc)


def Geo.inst.yaw(ms: List<&2, Geo>, st: Style, +cc: F32, +ss: F32)
  -> List<&2, WTri>:
  Geo.inst.yaw.go(ms, st, cc, ss, [])


# ---- the carriage transform ------------------------------------------
# M4.rigid(px, py, pz, yaw, roll, 1, 1, 1): R = Ry(yaw) * Rz(roll).  The
# carriage meshes are built once in local coordinates and every frame is just
# this map -- 15 carriages of ~4000 triangles is most of the frame's geometry.
def WTri.rigid.v(v: WVtx, +m00: F32, +m01: F32, +m02: F32, +m10: F32,
  +m11: F32, +m12: F32, +m20: F32, +m21: F32, +m22: F32, +tx: F32, +ty: F32,
  +tz: F32) -> WVtx:
  WVtx{+x, +y, +z, +nx, +ny, +nz, +cr, +cg, +cb, +e} = v
  Vx.at((m00 * x + m01 * y + m02 * z + tx : F32),
    (m10 * x + m11 * y + m12 * z + ty : F32),
    (m20 * x + m21 * y + m22 * z + tz : F32),
    (m00 * nx + m01 * ny + m02 * nz : F32),
    (m10 * nx + m11 * ny + m12 * nz : F32),
    (m20 * nx + m21 * ny + m22 * nz : F32), cr, cg, cb, e)


def WTri.rigid.go(ms: List<&2, WTri>, +m00: F32, +m01: F32, +m02: F32,
  +m10: F32, +m11: F32, +m12: F32, +m20: F32, +m21: F32, +m22: F32, +tx: F32,
  +ty: F32, +tz: F32, +acc: List<&2, WTri>) -> List<&2, WTri>:
  match ms:
    case []:
      acc
    case t <> rest:
      WTri{+a, +b, +c} = t
      +na = WTri.rigid.v(a, m00, m01, m02, m10, m11, m12, m20, m21, m22, tx, ty,
        tz)
      +nb = WTri.rigid.v(b, m00, m01, m02, m10, m11, m12, m20, m21, m22, tx, ty,
        tz)
      +nc = WTri.rigid.v(c, m00, m01, m02, m10, m11, m12, m20, m21, m22, tx, ty,
        tz)
      WTri.rigid.go(rest, m00, m01, m02, m10, m11, m12, m20, m21, m22, tx, ty,
        tz, WTri{na, nb, nc} <> acc)


def WTri.rigid(ms: List<&2, WTri>, +yaw: F32, +roll: F32, +px: F32, +py: F32,
  +pz: F32) -> List<&2, WTri>:
  +cy = F32.cos(yaw)
  +sy = F32.sin(yaw)
  +cr = F32.cos(roll)
  +sr = F32.sin(roll)
  WTri.rigid.go(ms, (cy * cr : F32), ((0.0 - cy * sr : F32)), sy, sr, cr, 0.0,
    ((0.0 - sy * cr : F32)), (sy * sr : F32), cy, px, py, pz, [])
