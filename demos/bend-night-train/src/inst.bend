# inst: the eleven instanced props of the night train, as a triangle soup.
#
# The reference draws these with instProg (night-train-webgl.html 487-576):
# one mesh per instance, the world position rebuilt from gl_InstanceID and a
# few uniforms.  Here every instance is stamped out by Geo.Geo.inst -- the
# same vertex path the shader takes, scale the position, leave the normal
# alone, then move -- with Geo.Geo.inst.yaw for kind 0, the one instance the
# shader rotates.  The per-vertex colour is constant across an instance, so it
# rides along in the Style record.
#
# The counts, steps and starts are the draw calls at lines 1214-1243; kind 4
# is never drawn and is not ported.  The shader's `cell` and `floor(id/k)` are
# computed on the float id, as the GLSL does, not on the Nat index.
#
# Kinds 8-11 (the village) share one hash cell and one house record; they are
# four draw calls over the same 35 ids, so each gets its own loop here rather
# than one pass that interleaves them.
import Base
import ./geo.bend as Geo
import ./trk.bend as Trk

# ---- helpers ---------------------------------------------------------
# The shader's `(cond ? -1.0 : 1.0)`: a computed Bool cannot be matched on, so
# it is passed to a def whose parameter is the scrutinee.
def Inst.sgn(+neg: Bool) -> F32:
  match neg:
    case True{}:
      (0.0 - 1.0 : F32)
    case False{}:
      1.0


# ---- the uniforms, per kind -----------------------------------------
# uStep / uStart, written once so the loops read like the draw calls.

def Inst.sleep.step() -> F32:
  0.62


def Inst.sleep.start() -> F32:
  Geo.Ng.of(200.0)


def Inst.pole.step() -> F32:
  44.0


def Inst.pole.start() -> F32:
  Geo.Ng.of(260.0)


def Inst.tree.step() -> F32:
  1.1


def Inst.tree.start() -> F32:
  Geo.Ng.of(320.0)


def Inst.arm.step() -> F32:
  44.0


def Inst.arm.start() -> F32:
  Geo.Ng.of(260.0)


def Inst.stone.step() -> F32:
  2.0


def Inst.stone.start() -> F32:
  Geo.Ng.of(160.0)


def Inst.grass.step() -> F32:
  0.30


def Inst.grass.start() -> F32:
  Geo.Ng.of(140.0)


def Inst.vil.step() -> F32:
  240.0


def Inst.vil.start() -> F32:
  Geo.Ng.of(480.0)


# ---- kind 0: sleepers, box, 620 at step 0.62 -------------------------
# s = floor((uS+uStart)/uStep)*uStep + id*uStep; yaw the box to the track.
def Inst.sleep.go(+n: Nat, +i: Nat, +s: F32, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+p:
      +id = U32.to_f32(U32.from_nat(i))
      +q = ((s + Inst.sleep.start() : F32) / Inst.sleep.step() : F32)
      +ss = (F32.floor(q) * Inst.sleep.step() + id * Inst.sleep.step() : F32)
      +yaw = Trk.Track.yaw(ss)
      +st = {Geo.Style{2.7, 0.16, 0.28, Trk.Track.x(ss),
        (Trk.Track.y(ss) - 0.30 : F32), ss, 0.070, 0.058, 0.048, 0.0}
        : Geo.Style}
      Inst.sleep.go(p, Nat.add(i, 1n), s, Geo.Geo.inst.yaw.go(Geo.G.box(), st,
        F32.cos(yaw), F32.sin(yaw), acc))


def Inst.sleepers(+s: F32, +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  Inst.sleep.go(620n, 0n, s, acc)


# ---- kind 1: catenary poles, box, 30 at step 44 ----------------------
def Inst.pole.go(+n: Nat, +i: Nat, +s: F32, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+p:
      +id = U32.to_f32(U32.from_nat(i))
      +q = ((s + Inst.pole.start() : F32) / Inst.pole.step() : F32)
      +ss = (F32.floor(q) * Inst.pole.step() + id * Inst.pole.step() : F32)
      +st = {Geo.Style{0.16, 5.4, 0.16, (Trk.Track.x(ss) - 6.4 : F32),
        (Trk.Track.y(ss) + 2.65 : F32), ss, 0.055, 0.052, 0.050, 0.0}
        : Geo.Style}
      Inst.pole.go(p, Nat.add(i, 1n), s, Geo.Geo.inst.go(Geo.G.box(), st, acc))


def Inst.poles(+s: F32, +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  Inst.pole.go(30n, 0n, s, acc)


# ---- kinds 2 and 3: trees, 1000 at step 1.1 --------------------------
# Both kinds hash the same cell; trunk is a box, crown a pine.  They are two
# draw calls, so the shared hash is recomputed in each loop.
def Inst.trunk.go(+n: Nat, +i: Nat, +s: F32, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+p:
      +id = U32.to_f32(U32.from_nat(i))
      +cell = (F32.floor(((s + Inst.tree.start() : F32) / Inst.tree.step()
        : F32)) + id : F32)
      +r1 = Trk.H.h21(cell, 3.7)
      +r2 = Trk.H.h21(cell, 9.1)
      +r3 = Trk.H.h21(cell, 17.3)
      +ts = (cell * Inst.tree.step() + r1 * Inst.tree.step() : F32)
      +side = (Inst.sgn(F32.is_lt(r2, 0.5))
        * (13.0 + F32.pow(r3, 1.5) * 210.0 : F32) : F32)
      +x = (Trk.Track.x(ts) + side : F32)
      +ground = Trk.T.terrain(x, ts)
      +scale = (0.85 + Trk.H.h21(cell, 24.7) * 1.9 : F32)
      +st = {Geo.Style{(0.24 * scale : F32), (5.0 * scale : F32),
        (0.24 * scale : F32), x, (ground + 2.5 * scale : F32), ts,
        0.035, 0.030, 0.028, 0.0}
        : Geo.Style}
      Inst.trunk.go(p, Nat.add(i, 1n), s, Geo.Geo.inst.go(Geo.G.box(), st, acc))


def Inst.trunks(+s: F32, +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  Inst.trunk.go(1000n, 0n, s, acc)


def Inst.crown.go(+n: Nat, +i: Nat, +s: F32, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+p:
      +id = U32.to_f32(U32.from_nat(i))
      +cell = (F32.floor(((s + Inst.tree.start() : F32) / Inst.tree.step()
        : F32)) + id : F32)
      +r1 = Trk.H.h21(cell, 3.7)
      +r2 = Trk.H.h21(cell, 9.1)
      +r3 = Trk.H.h21(cell, 17.3)
      +ts = (cell * Inst.tree.step() + r1 * Inst.tree.step() : F32)
      +side = (Inst.sgn(F32.is_lt(r2, 0.5))
        * (13.0 + F32.pow(r3, 1.5) * 210.0 : F32) : F32)
      +x = (Trk.Track.x(ts) + side : F32)
      +ground = Trk.T.terrain(x, ts)
      +scale = (0.85 + Trk.H.h21(cell, 24.7) * 1.9 : F32)
      +st = {Geo.Style{(4.2 * scale : F32), (7.8 * scale : F32),
        (4.2 * scale : F32), x, (ground + 4.7 * scale : F32), ts,
        Trk.S.mix(0.055, 0.105, r1), Trk.S.mix(0.095, 0.155, r1),
        Trk.S.mix(0.080, 0.125, r1), 0.0}
        : Geo.Style}
      Inst.crown.go(p, Nat.add(i, 1n), s, Geo.Geo.inst.go(Geo.G.pine(), st, acc))


def Inst.crowns(+s: F32, +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  Inst.crown.go(1000n, 0n, s, acc)


# ---- kind 5: catenary crossarms and hangers, box, 60 at step 44 ------
# floor(id/2) gives the cell; even ids are the horizontal arm, odd the hanger.
def Inst.arm.go(+n: Nat, +i: Nat, +s: F32, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+p:
      +id = U32.to_f32(U32.from_nat(i))
      +cell = (F32.floor(((s + Inst.arm.start() : F32) / Inst.arm.step()
        : F32)) + F32.floor((id / 2.0 : F32)) : F32)
      +cs = (cell * Inst.arm.step() : F32)
      +even = F32.is_lt(F32.mod(id, 2.0), 1.0)
      +st = {Geo.Style{
        Bool.pick(F32, even, 6.65, 0.065),
        Bool.pick(F32, even, 0.10, 0.55),
        Bool.pick(F32, even, 0.10, 0.065),
        Bool.pick(F32, even, (Trk.Track.x(cs) - 3.2 : F32), Trk.Track.x(cs)),
        Bool.pick(F32, even, (Trk.Track.y(cs) + 5.3 : F32),
          (Trk.Track.y(cs) + 5.0 : F32)),
        cs, 0.18, 0.20, 0.21, 0.0}
        : Geo.Style}
      Inst.arm.go(p, Nat.add(i, 1n), s, Geo.Geo.inst.go(Geo.G.box(), st, acc))


def Inst.crossarms(+s: F32, +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  Inst.arm.go(60n, 0n, s, acc)


# ---- kind 6: stones, box, 300 at step 2 ------------------------------
def Inst.stone.go(+n: Nat, +i: Nat, +s: F32, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+p:
      +id = U32.to_f32(U32.from_nat(i))
      +cell = (F32.floor(((s + Inst.stone.start() : F32) / Inst.stone.step()
        : F32)) + id : F32)
      +r = Trk.H.h21(cell, 4.21)
      +r2 = Trk.H.h21(cell, 8.71)
      +ss = (cell * Inst.stone.step() + r * Inst.stone.step() : F32)
      +x = (Trk.Track.x(ss)
        + Inst.sgn(F32.is_lt(r, 0.5)) * (5.4 + r2 * 30.0 : F32) : F32)
      +st = {Geo.Style{(0.4 + r2 : F32), (0.16 + r * 0.6 : F32),
        (0.3 + r2 : F32), x, (Trk.T.terrain(x, ss) + 0.14 : F32), ss,
        0.17, 0.19, 0.22, 0.0}
        : Geo.Style}
      Inst.stone.go(p, Nat.add(i, 1n), s, Geo.Geo.inst.go(Geo.G.box(), st, acc))


def Inst.stones(+s: F32, +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  Inst.stone.go(300n, 0n, s, acc)


# ---- kind 7: grass tufts, cone(7), 1600 at step 0.30 -----------------
def Inst.grass.go(+n: Nat, +i: Nat, +s: F32, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+p:
      +id = U32.to_f32(U32.from_nat(i))
      +cell = (F32.floor(((s + Inst.grass.start() : F32) / Inst.grass.step()
        : F32)) + id : F32)
      +r = Trk.H.h21(cell, 4.21)
      +r2 = Trk.H.h21(cell, 8.71)
      +ss = (cell * Inst.grass.step() + r * Inst.grass.step() : F32)
      +x = (Trk.Track.x(ss)
        + Inst.sgn(F32.is_lt(r, 0.5)) * (5.4 + r2 * 30.0 : F32) : F32)
      +st = {Geo.Style{(0.24 + r * 0.3 : F32), (0.5 + r2 * 0.9 : F32), 0.24,
        x, (Trk.T.terrain(x, ss) + 0.25 : F32), ss,
        Trk.S.mix(0.09, 0.22, r), Trk.S.mix(0.14, 0.23, r),
        Trk.S.mix(0.10, 0.15, r), 0.0}
        : Geo.Style}
      Inst.grass.go(p, Nat.add(i, 1n), s,
        Geo.Geo.inst.go(Geo.G.cone(7n), st, acc))


def Inst.grass(+s: F32, +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  Inst.grass.go(1600n, 0n, s, acc)


# ---- kinds 8, 9, 10, 11: the village, 35 at step 240 -----------------
# Same cell, house and hash for all four; the walls (box), roof (gable), lit
# window (box, emissive) and chimney (box) are four separate 35-wide loops.

def Inst.house.go(+n: Nat, +i: Nat, +s: F32, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+p:
      +id = U32.to_f32(U32.from_nat(i))
      +cell = (F32.floor(((s + Inst.vil.start() : F32) / Inst.vil.step()
        : F32)) + F32.floor((id / 5.0 : F32)) : F32)
      +house = F32.mod(id, 5.0)
      +r = Trk.H.h21(cell, (house + 23.0 : F32))
      +vs = (cell * Inst.vil.step() + (house - 2.0) * 17.0 : F32)
      +side = Inst.sgn(F32.is_lt(Trk.H.h21(cell, 71.0), 0.5))
      +x = (Trk.Track.x(vs) + side * (48.0 + r * 44.0) : F32)
      +y = Trk.T.terrain(x, vs)
      +w = (4.3 + r * 2.5 : F32)
      +h = (2.6 + r * 1.4 : F32)
      +d = (5.5 + r * 3.0 : F32)
      +st = {Geo.Style{w, h, d, x, (y + h * 0.5 : F32), vs,
        Trk.S.mix(0.20, 0.30, r), Trk.S.mix(0.19, 0.24, r),
        Trk.S.mix(0.18, 0.20, r), 0.0}
        : Geo.Style}
      Inst.house.go(p, Nat.add(i, 1n), s, Geo.Geo.inst.go(Geo.G.box(), st, acc))


def Inst.houses(+s: F32, +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  Inst.house.go(35n, 0n, s, acc)


def Inst.roof.go(+n: Nat, +i: Nat, +s: F32, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+p:
      +id = U32.to_f32(U32.from_nat(i))
      +cell = (F32.floor(((s + Inst.vil.start() : F32) / Inst.vil.step()
        : F32)) + F32.floor((id / 5.0 : F32)) : F32)
      +house = F32.mod(id, 5.0)
      +r = Trk.H.h21(cell, (house + 23.0 : F32))
      +vs = (cell * Inst.vil.step() + (house - 2.0) * 17.0 : F32)
      +side = Inst.sgn(F32.is_lt(Trk.H.h21(cell, 71.0), 0.5))
      +x = (Trk.Track.x(vs) + side * (48.0 + r * 44.0) : F32)
      +y = Trk.T.terrain(x, vs)
      +w = (4.3 + r * 2.5 : F32)
      +h = (2.6 + r * 1.4 : F32)
      +d = (5.5 + r * 3.0 : F32)
      +st = {Geo.Style{(w * 1.15 : F32), 1.8, (d * 1.15 : F32), x,
        (y + h + 0.9 : F32), vs, 0.13, 0.16, 0.18, 0.0}
        : Geo.Style}
      Inst.roof.go(p, Nat.add(i, 1n), s,
        Geo.Geo.inst.go(Geo.G.gable(), st, acc))


def Inst.roofs(+s: F32, +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  Inst.roof.go(35n, 0n, s, acc)


def Inst.window.go(+n: Nat, +i: Nat, +s: F32, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+p:
      +id = U32.to_f32(U32.from_nat(i))
      +cell = (F32.floor(((s + Inst.vil.start() : F32) / Inst.vil.step()
        : F32)) + F32.floor((id / 5.0 : F32)) : F32)
      +house = F32.mod(id, 5.0)
      +r = Trk.H.h21(cell, (house + 23.0 : F32))
      +vs = (cell * Inst.vil.step() + (house - 2.0) * 17.0 : F32)
      +side = Inst.sgn(F32.is_lt(Trk.H.h21(cell, 71.0), 0.5))
      +x = (Trk.Track.x(vs) + side * (48.0 + r * 44.0) : F32)
      +y = Trk.T.terrain(x, vs)
      +h = (2.6 + r * 1.4 : F32)
      +d = (5.5 + r * 3.0 : F32)
      +st = {Geo.Style{0.85, 0.85, 0.03, (x + 0.7 : F32),
        (y + h * 0.55 : F32), (vs - d * 0.5 - 0.025 : F32),
        0.95, 0.56, 0.22, 1.4}
        : Geo.Style}
      Inst.window.go(p, Nat.add(i, 1n), s,
        Geo.Geo.inst.go(Geo.G.box(), st, acc))


def Inst.windows(+s: F32, +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  Inst.window.go(35n, 0n, s, acc)


def Inst.chimney.go(+n: Nat, +i: Nat, +s: F32, +acc: List<&2, Geo.WTri>)
  -> List<&2, Geo.WTri>:
  match n:
    case 0n:
      acc
    case 1n+p:
      +id = U32.to_f32(U32.from_nat(i))
      +cell = (F32.floor(((s + Inst.vil.start() : F32) / Inst.vil.step()
        : F32)) + F32.floor((id / 5.0 : F32)) : F32)
      +house = F32.mod(id, 5.0)
      +r = Trk.H.h21(cell, (house + 23.0 : F32))
      +vs = (cell * Inst.vil.step() + (house - 2.0) * 17.0 : F32)
      +side = Inst.sgn(F32.is_lt(Trk.H.h21(cell, 71.0), 0.5))
      +x = (Trk.Track.x(vs) + side * (48.0 + r * 44.0) : F32)
      +y = Trk.T.terrain(x, vs)
      +w = (4.3 + r * 2.5 : F32)
      +h = (2.6 + r * 1.4 : F32)
      +st = {Geo.Style{0.48, 1.8, 0.48, (x - w * 0.25 : F32),
        (y + h + 1.1 : F32), (vs + 1.1 : F32), 0.20, 0.16, 0.14, 0.0}
        : Geo.Style}
      Inst.chimney.go(p, Nat.add(i, 1n), s,
        Geo.Geo.inst.go(Geo.G.box(), st, acc))


def Inst.chimneys(+s: F32, +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  Inst.chimney.go(35n, 0n, s, acc)


# ---- the whole pass --------------------------------------------------
# Kinds in the reverse of draw order: the serial emit prepends each kind's list
# to the accumulator of the ones drawn before it, so the concatenated chunk list
# must run last-kind-first to reproduce the soup exactly.  Draw order is
# visible through exact-depth ties, so this is not cosmetic.  The eleven
# per-kind loops are already independent -- no kind reads another's output --
# so the whole pass is one static eleven-way parallel let, each branch folding
# its own accumulator.
def Inst.chunks(+s: F32) -> List<&2, List<&2, Geo.WTri>>:
  c0 c1 c2 c3 c4 c5 c6 c7 c8 c9 c10 =
    Inst.houses(s, [])
    Inst.roofs(s, [])
    Inst.windows(s, [])
    Inst.chimneys(s, [])
    Inst.grass(s, [])
    Inst.stones(s, [])
    Inst.crossarms(s, [])
    Inst.crowns(s, [])
    Inst.trunks(s, [])
    Inst.poles(s, [])
    Inst.sleepers(s, [])
  [c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10]


def Inst.emit(+s: F32, +acc: List<&2, Geo.WTri>) -> List<&2, Geo.WTri>:
  +a0 = Inst.sleepers(s, acc)
  +a1 = Inst.poles(s, a0)
  +a2 = Inst.trunks(s, a1)
  +a3 = Inst.crowns(s, a2)
  +a5 = Inst.crossarms(s, a3)
  +a6 = Inst.stones(s, a5)
  +a7 = Inst.grass(s, a6)
  Inst.houses(s, Inst.roofs(s, Inst.windows(s, Inst.chimneys(s, a7))))
