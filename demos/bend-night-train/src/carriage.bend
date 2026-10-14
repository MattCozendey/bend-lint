# carriage: the night train's rolling stock, vertex for vertex from the
# reference demo's coloredBuilder / roofMesh / wheelMesh / carriageMesh block.
#
# The demo builds one static mesh per carriage variant, paints it with a
# builder that scales a local primitive, moves it and bakes a flat colour, then
# draws all 15 cars with one rigid model matrix each.  Here:
#
#   Carriage.put    is coloredBuilder.add()        -- local Geo -> world WTri
#   Carriage.roof   is roofMesh()                  -- the arch over the body
#   Carriage.wheel  is wheelMesh()                 -- 14 rim quads, two caps
#   Carriage.variant is carriageMesh(variant,loco) -- one whole carriage mesh
#   Carriage.emit   is the per-car uModel draw     -- rigid() on a whole mesh
#
# The meshes are built once and the per-frame cost is only Carriage.all: 15
# rigid maps over ~4000 triangles each.
import Base
import ./geo.bend as Geo
import ./trk.bend as Trk

# ---- constants -------------------------------------------------------
# CAR_LEN*0.62 is the demo's rear reference: the camera rides in the middle of
# the consist, not at the front.  carS() counts i from CARS_BEHIND, so car 0 is
# the nearest one behind the camera and the locomotive is the last index.

def Carriage.car_len() -> F32:
  24.0


def Carriage.car_gap() -> F32:
  2.6


def Carriage.car_w() -> F32:
  2.9


def Carriage.car_h() -> F32:
  4.0


def Carriage.cars_behind() -> Nat:
  5n


def Carriage.cars_n() -> Nat:
  15n


# ---- palette ---------------------------------------------------------
# brass/metal/dark plus a per-part colour, bundled so put() carries one value
# instead of three scalars.

type Col is Data:
  Col{r: F32, g: F32, b: F32}


def Carriage.col(+r: F32, +g: F32, +b: F32) -> Col:
  Col{r, g, b}


def Carriage.brass() -> Col:
  Col{0.49, 0.35, 0.18}


def Carriage.metal() -> Col:
  Col{0.13, 0.17, 0.20}


def Carriage.dark() -> Col:
  Col{0.027, 0.042, 0.052}


# ---- coloredBuilder.add -------------------------------------------------
# Position scaled then moved; normal divided by the same scale.  One flat
# colour and one emissive for the whole primitive.  `rotateX` is not ported:
# carriageMesh never passes a non-zero angle, so the demo's rotation is dead
# code.
#
# Faithfulness note: coloredBuilder then renormalises with Math.hypot(...)||1,
# which Geo.place does not do.  Positions -- and so the triangle counts and the
# model-matrix check below -- are identical; only the shading normals of a
# non-uniformly scaled primitive differ.

# `x <> xs` prepends one element, so a whole placed primitive is joined with
# List.concat instead.
def Carriage.cat(a: List<&2, Geo.WTri>, b: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  List.concat(&2, Geo.WTri, [a, b])


def Carriage.put(mesh: List<&2, Geo.Geo>, +tx: F32, +ty: F32, +tz: F32,
  +sx: F32, +sy: F32, +sz: F32, col: Col, +e: F32,
  +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  Col{+r, +g, +b} = col
  Carriage.cat(Geo.Geo.place(mesh,
    Geo.Style{sx, sy, sz, tx, ty, tz, r, g, b, e}), acc)


# ---- winding ---------------------------------------------------------
# The demo flips the winding of the arch caps and wheel caps by the sign of a
# computed float (end>0 / side>0).  A match may scrutinise a parameter only, so
# the sign is passed in as a Bool and the swap lives here.

def Carriage.tri(+a: Geo.GPt, +b: Geo.GPt, +c: Geo.GPt) -> Geo.Geo:
  Geo.Geo{a, b, c}


def Carriage.wind(+pos: Bool, +a: Geo.GPt, +b: Geo.GPt, +c: Geo.GPt) -> Geo.Geo:
  match pos:
    case True{}:
      Geo.Geo{a, b, c}
    case False{}:
      Geo.Geo{a, c, b}


# ---- roofMesh() ------------------------------------------------------
# A half-circle arch (i/12*PI for i in 0..12) swept along z from -0.5 to +0.5:
# the carriage body is a box and this is the rounded roof on top.  Each step is
# one quad on the shell; the two flat ends are fanned from the centre.

def Carriage.roof.side(+n: Nat, +i: Nat, +acc: List<&2, Geo.Geo>)
  -> List<&2, Geo.Geo>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +fi = U32.to_f32(U32.from_nat(i))
      +fj = U32.to_f32(U32.from_nat(Nat.add(i, 1n)))
      +ai = (fi / 12.0 * Geo.N.pi() : F32)
      +aj = (fj / 12.0 * Geo.N.pi() : F32)
      +xi = (F32.cos(ai) * 0.5 : F32)
      +yi = (F32.sin(ai) * 0.5 : F32)
      +xj = (F32.cos(aj) * 0.5 : F32)
      +yj = (F32.sin(aj) * 0.5 : F32)
      +nxi = F32.cos(ai)
      +nyi = F32.sin(ai)
      +nxj = F32.cos(aj)
      +nyj = F32.sin(aj)
      +lo = (0.0 - 0.5 : F32)
      +p0 = Geo.Pt.at(xi, yi, lo, nxi, nyi, 0.0)
      +p1 = Geo.Pt.at(xj, yj, lo, nxj, nyj, 0.0)
      +p2 = Geo.Pt.at(xi, yi, 0.5, nxi, nyi, 0.0)
      +p3 = Geo.Pt.at(xj, yj, 0.5, nxj, nyj, 0.0)
      +t1 = Carriage.tri(p0, p1, p2)
      +t2 = Carriage.tri(p2, p1, p3)
      Carriage.roof.side(k, Nat.add(i, 1n), t1 <> (t2 <> acc))


def Carriage.roof.end(+n: Nat, +i: Nat, +e: F32, +acc: List<&2, Geo.Geo>)
  -> List<&2, Geo.Geo>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +fi = U32.to_f32(U32.from_nat(i))
      +fj = U32.to_f32(U32.from_nat(Nat.add(i, 1n)))
      +ai = (fi / 12.0 * Geo.N.pi() : F32)
      +aj = (fj / 12.0 * Geo.N.pi() : F32)
      +hz = (e * 0.5 : F32)
      +p0 = Geo.Pt.at(0.0, 0.0, hz, 0.0, 0.0, e)
      +p1 = Geo.Pt.at((F32.cos(ai) * 0.5 : F32), (F32.sin(ai) * 0.5 : F32), hz,
        0.0, 0.0, e)
      +p2 = Geo.Pt.at((F32.cos(aj) * 0.5 : F32), (F32.sin(aj) * 0.5 : F32), hz,
        0.0, 0.0, e)
      Carriage.roof.end(k, Nat.add(i, 1n), e,
        Carriage.wind(F32.is_gt(e, 0.0), p0, p1, p2) <> acc)


def Carriage.roof() -> List<&2, Geo.Geo>:
  Carriage.roof.end(12n, 0n, Geo.Ng.of(1.0),
    Carriage.roof.end(12n, 0n, 1.0, Carriage.roof.side(12n, 0n, [])))


# ---- wheelMesh() -----------------------------------------------------
# 14 steps around a circle: a quad on the rim, then a triangle cap on each
# side.  The normal carries 2*y,2*z because the demo wrote it that way (the
# radius is 0.5), not a unit normal.

def Carriage.wheel.cap(+side: F32, +y: F32, +z: F32, +yy: F32, +zz: F32)
  -> Geo.Geo:
  +cx = (side * 0.5 : F32)
  +p0 = Geo.Pt.at(cx, 0.0, 0.0, side, 0.0, 0.0)
  +p1 = Geo.Pt.at(cx, y, z, side, 0.0, 0.0)
  +p2 = Geo.Pt.at(cx, yy, zz, side, 0.0, 0.0)
  Carriage.wind(F32.is_gt(side, 0.0), p0, p1, p2)


def Carriage.wheel.step(+n: Nat, +i: Nat, +acc: List<&2, Geo.Geo>)
  -> List<&2, Geo.Geo>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +fi = U32.to_f32(U32.from_nat(i))
      +fj = U32.to_f32(U32.from_nat(Nat.add(i, 1n)))
      +a = (fi / 14.0 * Geo.N.tau() : F32)
      +b = (fj / 14.0 * Geo.N.tau() : F32)
      +y = (F32.cos(a) * 0.5 : F32)
      +z = (F32.sin(a) * 0.5 : F32)
      +yy = (F32.cos(b) * 0.5 : F32)
      +zz = (F32.sin(b) * 0.5 : F32)
      +n0 = (0.0 - 0.5 : F32)
      +v0 = Geo.Pt.at(n0, y, z, 0.0, (y * 2.0 : F32), (z * 2.0 : F32))
      +v1 = Geo.Pt.at(0.5, y, z, 0.0, (y * 2.0 : F32), (z * 2.0 : F32))
      +v2 = Geo.Pt.at(n0, yy, zz, 0.0, (yy * 2.0 : F32), (zz * 2.0 : F32))
      +v3 = Geo.Pt.at(0.5, yy, zz, 0.0, (yy * 2.0 : F32), (zz * 2.0 : F32))
      +t1 = Carriage.tri(v0, v2, v1)
      +t2 = Carriage.tri(v1, v2, v3)
      +cm = Carriage.wheel.cap(Geo.Ng.of(1.0), y, z, yy, zz)
      +cp = Carriage.wheel.cap(1.0, y, z, yy, zz)
      Carriage.wheel.step(k, Nat.add(i, 1n),
        t1 <> (t2 <> (cm <> (cp <> acc))))


def Carriage.wheel() -> List<&2, Geo.Geo>:
  Carriage.wheel.step(14n, 0n, [])


# ---- the carriage body ----------------------------------------------
# Roof seams and ventilation cowls, then the two sides, the two ends, and the
# locomotive-only nose and slats -- every box and every loop of carriageMesh.

# for(z=-length/2+1; z<length/2; z+=2.2) one thin roof slice.  The demo's
# float-guarded loop is run ceil((half-z0)/step) times: the count matches the
# demo's iteration count exactly, and a Nat counter is what Bend's termination
# checker accepts.
def Carriage.seams.go(+n: Nat, +z: F32, +length: F32,
  +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +nz = (z + 2.2 : F32)
      Carriage.seams.go(k, nz, length,
        Carriage.put(Carriage.roof(), 0.0, 4.115, z, 3.04, 1.31, 0.035,
          Carriage.metal(), 0.0, acc))


def Carriage.seams(+z0: F32, +length: F32, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  +half = (length * 0.5 : F32)
  +n = F32.to_nat(F32.ceil(((half - z0 : F32) / 2.2 : F32)))
  Carriage.seams.go(n, z0, length, acc)


# for(z=-6; z<=6; z+=4) the four ventilation cowls
def Carriage.cowls(+n: Nat, +i: Nat, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +fi = U32.to_f32(U32.from_nat(i))
      +z = (0.0 - 6.0 + fi * 4.0 : F32)
      Carriage.cowls(k, Nat.add(i, 1n),
        Carriage.put(Geo.G.box(), 0.0, 4.79, z, 0.52, 0.17, 0.86,
          Carriage.metal(), 0.0, acc))


# for(y=1.27; y<1.7; y+=.105) the shallow body corrugations
def Carriage.corr.go(+n: Nat, +y: F32, +side: F32, +length: F32,
  +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +ny = (y + 0.105 : F32)
      Carriage.corr.go(k, ny, side, length,
        Carriage.put(Geo.G.box(), (side * 1.462 : F32), y, 0.0, 0.022, 0.025,
          (length - 0.2 : F32), Carriage.col(0.19, 0.25, 0.26), 0.0, acc))


def Carriage.corr(+side: F32, +length: F32, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  +n = F32.to_nat(F32.ceil(((1.7 - 1.27 : F32) / 0.105 : F32)))
  Carriage.corr.go(n, 1.27, side, length, acc)


# The half-drawn curtain: only a lit compartment has one, and every third
# compartment's curtain is drawn wider (w%3==0 ? 0.56 : 0.24).
def Carriage.curtain(+lit: Bool, +side: F32, +z: F32, +w: Nat,
  +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  match lit:
    case False{}:
      acc
    case True{}:
      +fw = U32.to_f32(U32.from_nat(w))
      +wz = Bool.pick(F32, F32.is_lt(F32.mod(fw, 3.0), 0.5), 0.56, 0.24)
      Carriage.put(Geo.G.box(), (side * 1.533 : F32), 3.05, z, 0.01, 0.94, wz,
        Carriage.col(0.28, 0.20, 0.14), 0.25, acc)


# The window band: brass frame, dark recess, lit or dark glass, curtain, then
# the door hardware.  `lit` is the demo's integer hash
# ((variant*7+w)*7919)%11>2, which only the curtains also depend on.
def Carriage.windows(+n: Nat, +w: Nat, +variant: Nat, +side: F32, +loco: Bool,
  +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +fw = U32.to_f32(U32.from_nat(w))
      +fv = U32.to_f32(U32.from_nat(variant))
      +z = Bool.pick(F32, loco, (6.0 + fw * 1.15 : F32),
        ((fw - 3.0) * 3.0 : F32))
      # ((variant*7+w)*7919)%11>2, in F32: the largest product is 20*7919, well
      # inside F32's exact-integer range, and F32.mod is a native law.  The Nat
      # form is not usable -- Nat.mul unfolds its 7919 literal at elaboration
      # and overflows the compiler stack.
      +lit = F32.is_gt(F32.mod(((fv * 7.0 + fw : F32) * 7919.0 : F32), 11.0),
        2.0)
      +gr = Bool.pick(F32, lit, 0.94, 0.07)
      +gg = Bool.pick(F32, lit, 0.62, 0.13)
      +gb = Bool.pick(F32, lit, 0.29, 0.19)
      +ge = Bool.pick(F32, lit, 0.62, 0.02)
      +a1 = Carriage.put(Geo.G.box(), (side * 1.475 : F32), 3.05, z, 0.045, 1.24,
        1.83, Carriage.brass(), 0.0, acc)
      +a2 = Carriage.put(Geo.G.box(), (side * 1.503 : F32), 3.05, z, 0.025, 1.08,
        1.66, Carriage.dark(), 0.0, a1)
      +a3 = Carriage.put(Geo.G.box(), (side * 1.522 : F32), 3.05, z, 0.012, 0.94,
        1.51, Carriage.col(gr, gg, gb), ge, a2)
      +a4 = Carriage.curtain(lit, side, (z - 0.57 : F32), w, a3)
      +a5 = Carriage.put(Geo.G.box(), (side * 1.544 : F32), 3.05, z, 0.022, 1.0,
        0.032, Carriage.metal(), 0.0, a4)
      +a6 = Carriage.put(Geo.G.box(), (side * 1.544 : F32), 3.37, z, 0.022, 0.032,
        1.5, Carriage.metal(), 0.0, a5)
      +a7 = Carriage.put(Geo.G.box(), (side * 1.55 : F32), 2.47, z, 0.14, 0.065,
        1.9, Carriage.metal(), 0.0, a6)
      Carriage.windows(k, Nat.add(w, 1n), variant, side, loco, a7)


# for(y=1; y<1.5; y+=.22) the handrails at each side end
def Carriage.rail.go(+n: Nat, +y: F32, +side: F32, +z: F32,
  +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +ny = (y + 0.22 : F32)
      Carriage.rail.go(k, ny, side, z,
        Carriage.put(Geo.G.box(), (side * 1.62 : F32), y, z, 0.38, 0.065, 1.28,
          Carriage.metal(), 0.0, acc))


def Carriage.rail(+side: F32, +z: F32, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  +n = F32.to_nat(F32.ceil(((1.5 - 1.0 : F32) / 0.22 : F32)))
  Carriage.rail.go(n, 1.0, side, z, acc)


# The two side ends: door panels, a step and a handrail.
def Carriage.side.ends(+n: Nat, +ei: Nat, +side: F32, +length: F32,
  +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +fe = U32.to_f32(U32.from_nat(ei))
      +end = (fe * 2.0 - 1.0 : F32)
      +z = (end * (length * 0.5 - 1.0) : F32)
      +a1 = Carriage.put(Geo.G.box(), (side * 1.47 : F32), 2.5, z, 0.025, 2.65,
        1.3, Carriage.dark(), 0.0, acc)
      +a2 = Carriage.put(Geo.G.box(), (side * 1.49 : F32), 2.5, z, 0.022, 2.50,
        1.18, Carriage.col(0.14, 0.21, 0.22), 0.0, a1)
      +a3 = Carriage.put(Geo.G.box(), (side * 1.514 : F32), 3.13, z, 0.02, 0.77,
        0.69, Carriage.col(0.11, 0.16, 0.19), 0.0, a2)
      +a4 = Carriage.put(Geo.G.box(), (side * 1.56 : F32), 2.23, (z + 0.4 : F32),
        0.07, 0.10, 0.21, Carriage.brass(), 0.0, a3)
      +a5 = Carriage.rail(side, z, a4)
      +a6 = Carriage.put(Geo.G.box(), (side * 1.59 : F32), 2.34,
        (z - 0.78 : F32), 0.065, 1.75, 0.055, Carriage.brass(), 0.0, a5)
      Carriage.side.ends(k, Nat.add(ei, 1n), side, length, a6)


def Carriage.sides.go(+n: Nat, +si: Nat, +variant: Nat, +loco: Bool,
  +length: F32, +wcount: Nat, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +fs = U32.to_f32(U32.from_nat(si))
      +side = (fs * 2.0 - 1.0 : F32)
      +a1 = Carriage.put(Geo.G.box(), (side * 1.464 : F32), 1.78, 0.0, 0.025,
        0.055, length, Carriage.brass(), 0.0, acc)
      +a2 = Carriage.put(Geo.G.box(), (side * 1.464 : F32), 3.92, 0.0, 0.025,
        0.045, length, Carriage.brass(), 0.0, a1)
      +a3 = Carriage.corr(side, length, a2)
      +a4 = Carriage.windows(wcount, 0n, variant, side, loco, a3)
      +a5 = Carriage.side.ends(2n, 0n, side, length, a4)
      Carriage.sides.go(k, Nat.add(si, 1n), variant, loco, length, wcount, a5)


def Carriage.sides(+variant: Nat, +loco: Bool, +length: F32, +wcount: Nat,
  +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  Carriage.sides.go(2n, 0n, variant, loco, length, wcount, acc)


# for(z=0; z<5; z++) the end-wall ribs
def Carriage.end.plates(+n: Nat, +zi: Nat, +end: F32, +length: F32,
  +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +fi = U32.to_f32(U32.from_nat(zi))
      +z = (end * (length * 0.5 + 0.08 + fi * 0.105) : F32)
      Carriage.end.plates(k, Nat.add(zi, 1n), end, length,
        Carriage.put(Geo.G.box(), 0.0, 2.5, z, 1.75, 2.6, 0.04,
          Carriage.metal(), 0.0, acc))


# One wheel pair either side of one axle: the big dark wheel and the brass
# hub disc just outboard of it.
def Carriage.wheels(+n: Nat, +si: Nat, +az: F32, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +fs = U32.to_f32(U32.from_nat(si))
      +side = (fs * 2.0 - 1.0 : F32)
      +a1 = Carriage.put(Carriage.wheel(), (side * 1.20 : F32), 0.46, az, 0.22,
        0.91, 0.91, Carriage.col(0.21, 0.23, 0.24), 0.0, acc)
      +a2 = Carriage.put(Carriage.wheel(), (side * 1.34 : F32), 0.46, az, 0.05,
        0.33, 0.33, Carriage.brass(), 0.0, a1)
      Carriage.wheels(k, Nat.add(si, 1n), az, a2)


# for(axle of [-1,1]) one axle box plus its two wheel pairs
def Carriage.axles(+n: Nat, +ai: Nat, +bogie: F32, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +fa = U32.to_f32(U32.from_nat(ai))
      +axle = (fa * 2.0 - 1.0 : F32)
      +az = (bogie + axle * 1.15 : F32)
      +a1 = Carriage.put(Geo.G.box(), 0.0, 0.48, az, 2.75, 0.17, 0.17,
        Carriage.metal(), 0.0, acc)
      +a2 = Carriage.wheels(2n, 0n, az, a1)
      Carriage.axles(k, Nat.add(ai, 1n), bogie, a2)


# The two end assemblies: buffer beam, end wall, coupler and the bogie.
def Carriage.ends.go(+n: Nat, +ei: Nat, +length: F32,
  +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +fe = U32.to_f32(U32.from_nat(ei))
      +end = (fe * 2.0 - 1.0 : F32)
      +zbase = (end * (length * 0.5 + 0.2) : F32)
      +a1 = Carriage.put(Geo.G.box(), 0.0, 2.5, zbase, 1.65, 2.5, 0.4,
        Carriage.dark(), 0.0, acc)
      +a2 = Carriage.end.plates(5n, 0n, end, length, a1)
      +a3 = Carriage.put(Geo.G.box(), 0.0, 0.76,
        (end * (length * 0.5 + 0.45) : F32), 0.32, 0.25, 0.9, Carriage.metal(),
        0.0, a2)
      +bogie = (end * length * 0.33 : F32)
      +a4 = Carriage.put(Geo.G.box(), 0.0, 0.64, bogie, 2.65, 0.48, 3.6,
        Carriage.dark(), 0.0, a3)
      +a5 = Carriage.axles(2n, 0n, bogie, a4)
      Carriage.ends.go(k, Nat.add(ei, 1n), length, a5)


def Carriage.ends(+length: F32, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  Carriage.ends.go(2n, 0n, length, acc)


# for(i=0;i<8;i++) the locomotive's side louvres
def Carriage.loco.slats(+n: Nat, +i: Nat, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +fi = U32.to_f32(U32.from_nat(i))
      +z = (0.0 - 5.0 + fi * 0.65 : F32)
      Carriage.loco.slats(k, Nat.add(i, 1n),
        Carriage.put(Geo.G.box(), (0.0 - 1.48 : F32), 2.8, z, 0.04, 0.72, 0.12,
          Carriage.dark(), 0.0, acc))


def Carriage.loco.extra(+loco: Bool, +length: F32, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  match loco:
    case False{}:
      acc
    case True{}:
      +a1 = Carriage.put(Geo.G.box(), 0.0, 3.35, (length * 0.5 + 0.015 : F32),
        2.2, 0.75, 0.06, Carriage.col(0.29, 0.39, 0.41), 0.15, acc)
      +a2 = Carriage.put(Geo.G.box(), 0.0, 4.9, (0.0 - 3.0 : F32), 0.6, 0.65,
        0.7, Carriage.dark(), 0.0, a1)
      Carriage.loco.slats(8n, 0n, a2)


# The hull: body box, underframe, the arch roof, its seams and the cowls.
def Carriage.hull(+length: F32, +cr: F32, +cg: F32, +cb: F32,
  +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  +a1 = Carriage.put(Geo.G.box(), 0.0, 2.6, 0.0, Carriage.car_w(), 3.0, length,
    Carriage.col(cr, cg, cb), 0.0, acc)
  +a2 = Carriage.put(Geo.G.box(), 0.0, 1.04, 0.0, 2.8, 0.28, length,
    Carriage.dark(), 0.0, a1)
  +a3 = Carriage.put(Carriage.roof(), 0.0, 4.1, 0.0, 3.02, 1.3,
    (length + 0.12 : F32), Carriage.col(0.21, 0.25, 0.28), 0.0, a2)
  +half = (length * 0.5 : F32)
  +start = (0.0 - half + 1.0 : F32)
  +a4 = Carriage.seams(start, length, a3)
  Carriage.cowls(4n, 0n, a4)


# carriageMesh(variant, loco): one whole carriage, local coordinates.
def Carriage.variant(+variant: Nat, +loco: Bool) -> List<&2, Geo.WTri>:
  +length = Bool.pick(F32, loco, 19.7, 24.0)
  +cg = Bool.pick(F32, loco, 0.19, 0.20)
  +cb = Bool.pick(F32, loco, 0.20, 0.22)
  +wcount = Bool.pick(Nat, loco, 3n, 7n)
  Carriage.loco.extra(loco, length,
    Carriage.ends(length,
      Carriage.sides(variant, loco, length, wcount,
        Carriage.hull(length, 0.12, cg, cb, []))))


# ---- the consist -----------------------------------------------------
# Cars is just the four static meshes, built once at load time: three
# passenger variants and the locomotive.

type Cars is Data:
  Cars{v0: List<&2, Geo.WTri>, v1: List<&2, Geo.WTri>, v2: List<&2, Geo.WTri>,
    loco: List<&2, Geo.WTri>}


def Carriage.cars() -> Cars:
  Cars{Carriage.variant(0n, False{}), Carriage.variant(1n, False{}),
    Carriage.variant(2n, False{}), Carriage.variant(0n, True{})}


# carIndexToS(i): i counts forward from the camera's carriage; carS(i) shifts
# the origin CARS_BEHIND cars back so index 0 is the rearmost.  The centre of a
# car sits CAR_LEN*0.5 further along than its rear reference point.
#
# i is F32, not U32: carS(0..4) evaluates i-CARS_BEHIND negative, and U32.sub
# would wrap it to 4.29e9 and park the rear of the train 10^11 m down the line.
def Carriage.index_to_s(+i: F32, +s: F32) -> F32:
  (s - Carriage.car_len() * 0.62 + i * (Carriage.car_len()
      + Carriage.car_gap()) : F32)


def Carriage.car_s(+i: U32, +s: F32) -> F32:
  Carriage.index_to_s((U32.to_f32(i) - U32.to_f32(
    U32.from_nat(Carriage.cars_behind())) : F32), s)


def Carriage.centre(+i: U32, +s: F32) -> F32:
  +cs = Carriage.car_s(i, s)
  (cs + Carriage.car_len() * 0.5 : F32)


# Variant pick: i mod 3 selects v0/v1/v2 by counting down (Nat patterns are
# only 0n and 1n+k), so the shift is split across two defs.
def Carriage.mesh3.tail(+k: Nat, v1: List<&2, Geo.WTri>,
  v2: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  match k:
    case 0n:
      v1
    case 1n+j:
      v2


def Carriage.mesh3(+m: Nat, v0: List<&2, Geo.WTri>, v1: List<&2, Geo.WTri>,
  v2: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  match m:
    case 0n:
      v0
    case 1n+k:
      Carriage.mesh3.tail(k, v1, v2)


def Cars.mesh.pick(+is_loco: Bool, loco: List<&2, Geo.WTri>,
  other: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  match is_loco:
    case True{}:
      loco
    case False{}:
      other


def Cars.mesh(cars: Cars, +i: U32, +m: Nat) -> List<&2, Geo.WTri>:
  Cars{+v0, +v1, +v2, +loco} = cars
  Cars.mesh.pick(U32.is_eq(i, U32.from_nat(Nat.sub(Carriage.cars_n(), 1n))),
    loco, Carriage.mesh3(m, v0, v1, v2))


# One carriage: place its mesh at the track point cs, yawed and rolled with the
# curve, and prepend its triangles to the frame.
def Carriage.emit(+i: U32, +s: F32, cars: Cars, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  +cs = Carriage.centre(i, s)
  +yaw = Trk.Track.yaw(cs)
  +roll = Trk.Track.roll(cs)
  +mesh = Cars.mesh(cars, i, U32.to_nat(U32.mod(i, 3)))
  Carriage.cat(Geo.WTri.rigid(mesh, yaw, roll, Trk.Track.x(cs), Trk.Track.y(cs),
    cs), acc)


def Carriage.all.go(+n: Nat, +i: U32, +s: F32, +cars: Cars,
  +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+k:
      Carriage.all.go(k, U32.add(i, 1), s, cars, Carriage.emit(i, s, cars, acc))


# The 15 cars split into five runs of three: all.go already takes an explicit
# start index, so a run is just a different (n, i) pair with its own empty
# accumulator.  The runs come back highest-index-first because the serial fold
# prepends each car, leaving the consist in descending index order; joining the
# chunks in that order reproduces it, which matters because draw order is
# visible through exact-depth ties.  The five runs are the arity of the parallel
# let; the cars mesh is built once by the caller and shared into all branches.
def Carriage.chunks(+s: F32, +cars: Cars) -> List<&2, List<&2, Geo.WTri>>:
  r0 r1 r2 r3 r4 =
    Carriage.all.go(3n, 12, s, cars, [])
    Carriage.all.go(3n, 9, s, cars, [])
    Carriage.all.go(3n, 6, s, cars, [])
    Carriage.all.go(3n, 3, s, cars, [])
    Carriage.all.go(3n, 0, s, cars, [])
  [r0, r1, r2, r3, r4]


def Carriage.all(+s: F32, cars: Cars, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  Carriage.all.go(Carriage.cars_n(), 0, s, cars, acc)
