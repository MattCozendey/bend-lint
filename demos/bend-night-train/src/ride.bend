# ride: where the camera sits in the train, and what lights the scene.
#
# Everything here is the demo's own per-frame state, so the two renders agree:
# the camera hangs out of a window on the left of the centreline, the lean
# breathing and the bob are its slow sine terms, and the auto-look aims at a
# point two thirds of the way up the consist.
#
# The demo eases `yawTarget` towards that angle at dt*1.4 and `yaw` towards
# `yawTarget` at dt*7, so a viewer sees the converged value within a third of a
# second.  A headless frame has no previous frame to ease from, so this takes
# the converged value directly; the breathing terms are evaluated at `t`.
import Base
import ./trk.bend as Trk
import ./rt.bend as Rt
import ./shade.bend as Shade
import ./carriage.bend as Carriage


# ---- the camera ------------------------------------------------------
def Ride.lean() -> F32:
  1.0


# The demo's "Обычная" speed, the one the live view rides at.  The dust and the
# smoke are carried by it, so the glow layer needs it too.
def Ride.speed() -> F32:
  24.5


# The demo freezes the breathing when it thinks the viewer asked for reduced
# motion; `motion` carries that switch, and a frozen frame (motion off) is what
# tools/render_reference.py renders, so it has to be selectable here too.
def Ride.motion.if(+motion: Bool, +a: F32) -> F32:
  Rt.S.if1(motion, a, 0.0)


def Ride.sway(+t: F32, +motion: Bool) -> F32:
  Ride.motion.if(motion,
    (F32.sin((t * 1.9 : F32)) * 0.022 + F32.sin((t * 3.7 : F32)) * 0.008
      : F32))


def Ride.bob(+t: F32, +motion: Bool) -> F32:
  Ride.motion.if(motion,
    (F32.sin((t * 5.3 : F32)) * 0.018 + F32.sin((t * 2.6 : F32)) * 0.016 : F32))


# sideOffset = -2.15 - lean*2.45 + sin(t*0.31)*0.12; VCam.ride takes the same
# offset with the opposite sign (it subtracts it from the centreline).
def Ride.side(+t: F32, +motion: Bool) -> F32:
  (2.15 + Ride.lean() * 2.45
    - Ride.motion.if(motion, F32.sin((t * 0.31 : F32)) * 0.12) : F32)


def Ride.hgt(+t: F32, +motion: Bool) -> F32:
  (3.05 + Ride.bob(t, motion) : F32)


def Ride.pitch(+t: F32, +motion: Bool) -> F32:
  (0.012 + Ride.sway(t, motion) * 0.1 : F32)


# atan2 lands in [-pi, pi] and the track heading is within +-pi/2, so the
# difference leaves [-3pi/2, 3pi/2]: one step each way is a full wrap.
def Ride.want.wrap(+v: F32) -> F32:
  +hi = Rt.S.if1(F32.is_gt(v, 3.141592653589793),
    (v - 6.283185307179586 : F32), v)
  Rt.S.if1(F32.is_lt(hi, (0.0 - 3.141592653589793 : F32)),
    (hi + 6.283185307179586 : F32), hi)


def Ride.want.clamp(+v: F32) -> F32:
  F32.clamp(v, (0.0 - 0.95 : F32), 0.45)


# The aim point: carIndexToS(CARS_BEHIND + round((CARS_AHEAD-1)*0.62)) with
# CARS_AHEAD = 10, so carIndex 11.  Carriage.car_s() subtracts CARS_BEHIND
# itself, so it wants the same 11, not 11 - CARS_BEHIND: passing 6 would put
# the aim five car lengths behind the camera and swing the head across the
# consist.
def Ride.want(+s: F32, +side: F32) -> F32:
  +base = Trk.Track.yaw(s)
  +cb = F32.cos(base)
  +sb = F32.sin(base)
  +camx = (Trk.Track.x(s) - side * cb : F32)
  +camz = (s + side * sb : F32)
  +aims = Carriage.Carriage.car_s(11, s)
  +ay = Trk.Track.yaw(aims)
  +aimx = (Trk.Track.x(aims) + 4.2 * F32.cos(ay) : F32)
  +aimz = (aims - 4.2 * F32.sin(ay) : F32)
  Ride.want.clamp(Ride.want.wrap((F32.atan2((aimx - camx : F32),
    (aimz - camz : F32)) - base : F32)))


def Ride.yaw(+s: F32, +t: F32, +motion: Bool) -> F32:
  (Ride.want(s, Ride.side(t, motion)) + Ride.sway(t, motion) * 0.35 : F32)


# ---- the headlight ---------------------------------------------------
def Ride.head.centre(+s: F32) -> F32:
  Carriage.Carriage.centre(U32.from_nat(Nat.sub(Carriage.Carriage.cars_n(), 1n)),
    s)


def Ride.head.pos(+s: F32) -> Rt.P3:
  +cs = Ride.head.centre(s)
  +yaw = Trk.Track.yaw(cs)
  Rt.P3{(Trk.Track.x(cs) + 9.92 * F32.sin(yaw) : F32),
    (Trk.Track.y(cs) + 1.6 : F32), (cs + 9.92 * F32.cos(yaw) : F32)}


def Ride.head.dir(+s: F32) -> Rt.P3:
  +yaw = Trk.Track.yaw(Ride.head.centre(s))
  +dx = F32.sin(yaw)
  +dy = (0.0 - 0.075 : F32)
  +dz = F32.cos(yaw)
  +l = F32.sqrt((dx * dx + dy * dy + dz * dz : F32))
  Rt.P3{(dx / l : F32), (dy / l : F32), (dz / l : F32)}


# ---- the two uniforms ------------------------------------------------
# Ten warm points, one every two cars, on the camera's side.
def Ride.win.go(+i: Nat, +s: F32, +acc: List<&2, Rt.P3>) -> List<&2, Rt.P3>:
  match i:
    case 0n:
      acc
    case 1n+p:
      +ws = (s - 120.0 + U32.to_f32(U32.from_nat(p)) * 42.0 : F32)
      +yaw = Trk.Track.yaw(ws)
      Ride.win.go(p, s,
        Rt.P3{(Trk.Track.x(ws) - 2.4 * F32.cos(yaw) : F32),
          (Trk.Track.y(ws) + 2.9 : F32),
          (ws + 2.4 * F32.sin(yaw) : F32)} <> acc)


def Ride.win(+s: F32) -> List<&2, Rt.P3>:
  Ride.win.go(10n, s, [])


# The two points are read out of parameters, not out of the calls that built
# them: a match inspects a parameter or a pattern binder, never a computed
# value.
def Ride.lights.at(hp: Rt.P3, hd: Rt.P3, +s: F32) -> Shade.Lights:
  Rt.P3{hx, hy, hz} = hp
  Rt.P3{dx, dy, dz} = hd
  Shade.Lights{hx, hy, hz, dx, dy, dz, Ride.win(s)}


def Ride.lights(+s: F32) -> Shade.Lights:
  Ride.lights.at(Ride.head.pos(s), Ride.head.dir(s), s)


# ---- the glowing things ----------------------------------------------
# The demo draws every light a second time, as an additive billboard (its
# glowProg): a screen-facing disc of `r` world units whose alpha falls as
# (1 - d)^2.6, accumulated over the frame.  The rasteriser's sprite kind 1 is
# that same disc with that same falloff (raster.bend's Spr.alpha), depth-tested
# so the train still hides a light behind it.
#
# Two families, and both are the demo's own list: the warm glow each carriage
# throws out of its windows, and the locomotive's lamps together with the cone
# of air they light.  Each is built in the carriage's own frame and put on the
# track by the same rigid map the mesh gets (geo.bend's WTri.rigid), so a glow
# cannot drift away from the window it belongs to.
type Lamp is Data:
  Lamp{x: F32, y: F32, z: F32, r: F32, cr: F32, cg: F32, cb: F32, a: F32}


# ((i % 3) * 7 + w) * 7919 % 11 <= 2: the demo's own rule for which windows are
# dark, from the car's variant and the window's index alone, so the same
# windows are dark on every run and in every frame.  The product tops out at
# 20*7919, far inside U32.
def Ride.lamp.dark(+i: U32, +w: U32) -> Bool:
  +k = U32.mul(U32.add(U32.mul(U32.mod(i, 3), 7), w), 7919)
  U32.is_le(U32.mod(k, 11), 2)


# One lamp at a carriage-local point.  Ry(yaw) * Rz(roll) is expanded here
# rather than shared with WTri.rigid: the mesh walk multiplies nine
# coefficients by three vertices a triangle, this multiplies one point.
def Ride.lamp.at(+yaw: F32, +roll: F32, +px: F32, +py: F32, +pz: F32, +x: F32,
  +y: F32, +z: F32, +r: F32, +cr: F32, +cg: F32, +cb: F32, +a: F32) -> Lamp:
  +cy = F32.cos(yaw)
  +sy = F32.sin(yaw)
  +cc = F32.cos(roll)
  +ss = F32.sin(roll)
  Lamp{(px + (cy * cc * x - cy * ss * y : F32) + sy * z : F32),
    (py + ss * x + cc * y : F32),
    (pz + (sy * ss * y - sy * cc * x : F32) + cy * z : F32), r, cr, cg, cb, a}


# The window band is seven panes three metres apart, centred on the carriage's
# middle, at 1.75 m out from the centre line and 3.05 m up -- the demo's own
# (side*1.75, 3.05, (w-3)*3).
def Ride.lamp.win.one(dark: Bool, +w: Nat, +side: F32, +yaw: F32, +roll: F32,
  +px: F32, +py: F32, +pz: F32, +acc: List<&2, Lamp>) -> List<&2, Lamp>:
  match dark:
    case True{}:
      acc
    case False{}:
      Ride.lamp.at(yaw, roll, px, py, pz, (side * 1.75 : F32), 3.05,
        ((U32.to_f32(U32.from_nat(w)) - 3.0 : F32) * 3.0 : F32), 2.8, 1.0, 0.67,
        0.32, 0.14) <> acc


def Ride.lamp.win.w(+w: Nat, +i: U32, +side: F32, +yaw: F32, +roll: F32,
  +px: F32, +py: F32, +pz: F32, +acc: List<&2, Lamp>) -> List<&2, Lamp>:
  match w:
    case 0n:
      acc
    case 1n+k:
      Ride.lamp.win.w(k, i, side, yaw, roll, px, py, pz,
        Ride.lamp.win.one(Ride.lamp.dark(i, U32.from_nat(k)), k, side, yaw, roll,
          px, py, pz, acc))


def Ride.lamp.sides(+i: U32, +yaw: F32, +roll: F32, +px: F32, +py: F32, +pz: F32,
  +acc: List<&2, Lamp>) -> List<&2, Lamp>:
  Ride.lamp.win.w(7n, i, 1.0, yaw, roll, px, py, pz,
    Ride.lamp.win.w(7n, i, (0.0 - 1.0 : F32), yaw, roll, px, py, pz, acc))


# The locomotive has no lit windows; it has the lamps.
def Ride.lamp.car(loco: Bool, +i: U32, +yaw: F32, +roll: F32, +px: F32, +py: F32,
  +pz: F32, +acc: List<&2, Lamp>) -> List<&2, Lamp>:
  match loco:
    case True{}:
      acc
    case False{}:
      Ride.lamp.sides(i, yaw, roll, px, py, pz, acc)


def Ride.lamp.cars(+n: Nat, +i: U32, +s: F32, +acc: List<&2, Lamp>)
  -> List<&2, Lamp>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +cs = Carriage.Carriage.centre(i, s)
      Ride.lamp.cars(k, U32.add(i, 1), s,
        Ride.lamp.car(U32.is_eq(i, U32.from_nat(Nat.sub(Carriage.Carriage.cars_n(),
          1n))), i, Trk.Track.yaw(cs), Trk.Track.roll(cs), Trk.Track.x(cs),
          Trk.Track.y(cs), cs, acc))


# Two lamps a metre either side of the locomotive's centre line, each with a
# tight core and a wide halo, plus one above the front for the lit cab.  The
# offset is the track's own right-hand vector at the head, (cos yaw, 0, -sin
# yaw).
def Ride.lamp.head.lamp(+x: F32, +y: F32, +z: F32, +acc: List<&2, Lamp>)
  -> List<&2, Lamp>:
  Lamp{x, y, z, 7.0, 1.0, 0.88, 0.62, 0.32} <> (Lamp{x, y, z, 2.2, 1.0, 0.93,
    0.75, 0.95} <> acc)


def Ride.lamp.head.two(+rx: F32, +rz: F32, +hx: F32, +hy: F32, +hz: F32,
  +acc: List<&2, Lamp>) -> List<&2, Lamp>:
  Ride.lamp.head.lamp((hx - rx : F32), hy, (hz - rz : F32),
    Ride.lamp.head.lamp((hx + rx : F32), hy, (hz + rz : F32), acc))


def Ride.lamp.head.one(hp: Rt.P3, +rx: F32, +rz: F32, +acc: List<&2, Lamp>)
  -> List<&2, Lamp>:
  Rt.P3{+hx, +hy, +hz} = hp
  Ride.lamp.head.two(rx, rz, hx, hy, hz,
    Lamp{hx, (hy + 1.5 : F32), hz, 1.2, 1.0, 0.85, 0.55, 0.55} <> acc)


# The cone in the air: nine discs down the beam, each wider and fainter than
# the last, which is what makes the headlight read as a volume rather than a
# lamp.  `k` counts 0..8, so the demo's `i` is k + 1.
def Ride.lamp.cone(+k: Nat, +sHead: F32, +acc: List<&2, Lamp>)
  -> List<&2, Lamp>:
  match k:
    case 0n:
      acc
    case 1n+j:
      +i = (U32.to_f32(U32.from_nat(j)) + 1.0 : F32)
      +d = (i * 7.5 : F32)
      +fs = (sHead + d : F32)
      Ride.lamp.cone(j, sHead,
        Lamp{Trk.Track.x(fs), (Trk.Track.y(fs) + 1.2 : F32), fs,
          (2.0 + d * 0.30 : F32), 1.0, 0.86, 0.62,
          (0.055 * (1.0 - i * 0.09090909) : F32)} <> acc)


def Ride.lamp.head(on: Bool, hp: Rt.P3, +s: F32, +acc: List<&2, Lamp>)
  -> List<&2, Lamp>:
  match on:
    case False{}:
      acc
    case True{}:
      Rt.P3{+hx, +hy, +hz} = hp
      +yaw = Trk.Track.yaw(Ride.head.centre(s))
      Ride.lamp.cone(9n, hz,
        Ride.lamp.head.one(Rt.P3{hx, hy, hz}, F32.cos(yaw),
          (0.0 - F32.sin(yaw) : F32), acc))


# ---- the demo's Math.random -----------------------------------------
# The dust and the smoke are the two glow groups the demo seeds with
# Math.random, and tools/render_reference.py replaces that generator before the
# demo script runs so a reference frame is reproducible -- which means the
# renderer has to draw the same speck of dust, not merely a similar one.  It is
# a 32-bit LCG: U32.mul wraps, so the low 32 bits are exact and the mask leaves
# what the demo's `& 0x7fffffff` leaves.
def Rnd.next(+st: U32) -> U32:
  U32.and(U32.add(U32.mul(st, 1103515245), 12345), 2147483647)


# `state / 0x80000000`, a number in [0, 1).  The demo keeps it in a double and
# this rounds it to F32, a relative 1e-7 -- below anything a soft sprite can
# show, and the one place it could matter, a branch on a threshold, is a coin
# flip the demo itself never fixed.
def Rnd.f(+st: U32) -> F32:
  (U32.to_f32(st) * 4.656612873077393e-10 : F32)


# The seed tools/render_reference.py installs by default.  Unseeded, the demo
# picks its own dust on every reload and no two runs agree; fixing the seed here
# is what lets a frame of the renderer be checked against a frame of the demo.
def Rnd.seed() -> U32:
  7


# ---- the grouped sprites ---------------------------------------------
# A mote, as the demo's load loop draws it: `ds` is where it sits along the path
# relative to the camera, so it sweeps back as the train moves; `warm` picks the
# tint, `drift` and `seed` give it its wobble, and `sid` is the generator state
# it was drawn at, which is what a re-roll on the live ride samples from.
type Mote is Data:
  Mote{ds: F32, side: F32, up: F32, r: F32, warm: Bool, drift: F32, seed: F32,
    sid: U32}


# A puff from the chimney.  `at` is where it was born -- for the first cycle the
# one thing that cannot be recomputed, because the demo sets it once at load up
# to 60 m behind the engine, and a still frame has to show that same plume.
type Smoke is Data:
  Smoke{life0: F32, at: F32, side: F32, seed: F32, sid: U32}


# The puff as one frame sees it: which cycle of its life it is in, how far into
# it, and where that cycle started.
type Puff is Data:
  Puff{life: F32, at: F32, side: F32, seed: F32}


# Everything the demo's load draws, and the generator as it stands after them.
# The piles are arguments rather than results because a destructuring let may
# only take apart a parameter, not a call -- so each seeding step takes the pile
# it is building and hands it back, and the generator rides along in it.
type Loaded is Data:
  Loaded{lives: List<&2, F32>, puffs: List<&2, Smoke>, motes: List<&2, Mote>,
    st: U32}


# The 44 lives come first, before the motes: the demo seeds the smoke at line
# 1011 and the motes at 1015, and one generator serves both.
def Loaded.life.add(ld: Loaded) -> Loaded:
  Loaded{+lives, +puffs, +motes, +st} = ld
  +s1 = Rnd.next(st)
  Loaded{List.append(&2, F32, lives, [Rnd.f(s1)]), puffs, motes, s1}


def Loaded.lives.go(+n: Nat, ld: Loaded) -> Loaded:
  match n:
    case 0n:
      ld
    case 1n+k:
      Loaded.lives.go(k, Loaded.life.add(ld))


# The seven draws a mote costs, in the demo's order: ds, side, up, r, warm,
# drift, seed.
def Loaded.mote.add(ld: Loaded) -> Loaded:
  Loaded{+lives, +puffs, +motes, +st} = ld
  +sid = st
  +s1 = Rnd.next(st)
  +s2 = Rnd.next(s1)
  +s3 = Rnd.next(s2)
  +s4 = Rnd.next(s3)
  +s5 = Rnd.next(s4)
  +s6 = Rnd.next(s5)
  +s7 = Rnd.next(s6)
  Loaded{lives, puffs,
    List.append(&2, Mote, motes,
      [Mote{((Rnd.f(s1) * 90.0 : F32) - 30.0 : F32),
        ((Rnd.f(s2) - 0.5 : F32) * 9.0 : F32),
        ((Rnd.f(s3) * 5.0 : F32) - 1.4 : F32),
        (0.035 + Rnd.f(s4) * 0.13 : F32), F32.is_lt(Rnd.f(s5), 0.28),
        ((Rnd.f(s6) - 0.5 : F32) * 1.6 : F32), (Rnd.f(s7) * 10.0 : F32), sid}]),
    s7}


def Loaded.motes.go(+n: Nat, ld: Loaded) -> Loaded:
  match n:
    case 0n:
      ld
    case 1n+k:
      Loaded.motes.go(k, Loaded.mote.add(ld))


# The load frame's own pass, and the state a still frame is compared on: a mote
# that starts more than 26 m behind the camera is lifted 110 m up the line with
# a fresh side and height drawn for it, and those draws come from the one
# generator, in list order.
def Loaded.wrap.add(ld: Loaded, m: Mote) -> Loaded:
  Loaded{+lives, +puffs, +motes, +st} = ld
  Mote{+ds, +side, +up, +r, +warm, +drift, +seed, +sid} = m
  +s1 = Rnd.next(st)
  +s2 = Rnd.next(s1)
  Bool.pick(Loaded, F32.is_lt(ds, (0.0 - 26.0 : F32)),
    Loaded{lives, puffs,
      List.append(&2, Mote, motes,
        [Mote{(ds + 110.0 : F32), ((Rnd.f(s1) - 0.5 : F32) * 9.0 : F32),
          ((Rnd.f(s2) * 5.0 : F32) - 1.4 : F32), r, warm, drift, seed, sid}]),
      s2},
    Loaded{lives, puffs,
      List.append(&2, Mote, motes,
        [Mote{ds, side, up, r, warm, drift, seed, sid}]), st})


def Loaded.wrap.go(ms: List<&2, Mote>, ld: Loaded) -> Loaded:
  match ms:
    case []:
      ld
    case m <> rest:
      Loaded.wrap.go(rest, Loaded.wrap.add(ld, m))


# A puff has no position until the frame first draws one for it: the start is up
# to 60 m back along the line, and the seed is what makes its plume wave.
def Loaded.puff.add(ld: Loaded, life: F32, +emit_s: F32) -> Loaded:
  Loaded{+lives, +puffs, +motes, +st} = ld
  +sid = st
  +s1 = Rnd.next(st)
  +s2 = Rnd.next(s1)
  Loaded{lives,
    List.append(&2, Smoke, puffs,
      [Smoke{life, (emit_s - Rnd.f(s1) * 60.0 : F32), 0.0, (Rnd.f(s2) : F32),
        sid}]), motes, s2}


def Loaded.puffs(ls: List<&2, F32>, ld: Loaded, +emit_s: F32) -> Loaded:
  match ls:
    case []:
      ld
    case life <> rest:
      Loaded.puffs(rest, Loaded.puff.add(ld, life, emit_s), emit_s)


def Loaded.reload(ld: Loaded, +s0: F32) -> Loaded:
  Loaded{+lives, +puffs, +motes, +st} = ld
  Loaded.puffs(lives, Loaded.wrap.go(motes, Loaded{lives, puffs, [], st}),
    (Ride.head.centre(s0) - 3.0 : F32))


def Loaded.load(+s0: F32) -> Loaded:
  Loaded.reload(Loaded.motes.go(70n, Loaded.lives.go(44n,
    Loaded{[], [], [], Rnd.seed()})), s0)


# ---- the dust on the move --------------------------------------------
# A mote's drift: the demo pulls `ds` back by speed*dt*(0.85 + seed*0.03) every
# frame, so after t seconds it has gone v*t further back, and every 110 m it
# wraps and redraws side and up.  A frame rendered straight from t has no
# earlier frame to have drawn those in list order, so a wrap redraws from a
# stream of the mote's own, seeded with where the mote sat in the load order:
# the same t always gives the same dust, and the load-time state itself -- the
# one the still comparison sees -- is exact.
def Mote.evolved(+ds: F32, +r: F32, +warm: Bool, +drift: F32, +seed: F32,
  +sid: U32, +v: F32, +g: F32, +t: F32) -> Mote:
  +k = (F32.floor(g / 110.0) + 1.0 : F32)
  +h = Rnd.next(U32.add(sid, U32.mul(F32.to_u32(k), 131)))
  Mote{((ds - v * t : F32) + 110.0 * k : F32),
    ((Rnd.f(h) - 0.5 : F32) * 9.0 : F32),
    ((Rnd.f(Rnd.next(h)) * 5.0 : F32) - 1.4 : F32), r, warm, drift, seed, sid}


def Mote.evolve(m: Mote, +t: F32) -> Mote:
  Mote{+ds, +side, +up, +r, +warm, +drift, +seed, +sid} = m
  +v = (Ride.speed() * (0.85 + seed * 0.03 : F32) : F32)
  +g = (v * t - (ds + 26.0 : F32) : F32)
  Bool.pick(Mote, F32.is_le(g, 0.0),
    Mote{ds, side, up, r, warm, drift, seed, sid},
    Mote.evolved(ds, r, warm, drift, seed, sid, v, g, t))


def Ride.motes.evolve(ms: List<&2, Mote>, +t: F32, +acc: List<&2, Mote>)
  -> List<&2, Mote>:
  match ms:
    case []:
      acc
    case m <> rest:
      Ride.motes.evolve(rest, t,
        List.append(&2, Mote, acc, [Mote.evolve(m, t)]))


def Ride.lamp.mote.one(m: Mote, +s: F32, +t: F32, +acc: List<&2, Lamp>)
  -> List<&2, Lamp>:
  # every binder is `+`, and the warm/cool pair is picked rather than matched:
  # a match has to consume its scrutinee in the order the fields were bound, and
  # `warm` sits between the fields the position needs and the radius it picks.
  Mote{+ds, +side, +up, +r, +warm, +drift, +seed, +sid} = m
  +ms = (s + ds : F32)
  +yaw = Trk.Track.yaw(ms)
  +off = ((0.0 - 3.1 : F32) + side * 0.55
    + F32.sin((t * 3.1 + seed * 6.0 : F32)) * drift : F32)
  +x = (Trk.Track.x(ms) + off * F32.cos(yaw) : F32)
  +z = (ms - off * F32.sin(yaw) : F32)
  +y = (Trk.Track.y(ms) + 2.2 + up : F32)
  +near = (1.0 - F32.min(1.0, F32.abs(ds) / 26.0) : F32)
  Lamp{x, y, z, Bool.pick(F32, warm, (r * 2.4 : F32), (r * 2.0 : F32)),
    Bool.pick(F32, warm, 1.0, 0.72), 0.80,
    Bool.pick(F32, warm, 0.52, 0.95),
    Bool.pick(F32, warm, (0.22 * near : F32), (0.12 * near : F32))} <> acc


def Ride.lamp.motes(ms: List<&2, Mote>, +s: F32, +t: F32, +acc: List<&2, Lamp>)
  -> List<&2, Lamp>:
  match ms:
    case []:
      acc
    case m <> rest:
      Ride.lamp.motes(rest, s, t, Ride.lamp.mote.one(m, s, t, acc))


# ---- the plume on the move -------------------------------------------
# life(t) = fract(life0 + 0.30t), and the cycle it is in is what decides where
# it was born: the first cycle at the load-time chimney, later ones at the
# chimney as it stood when that cycle turned over, which is the head's position
# |t - t_res| seconds earlier.
def Smoke.reborn(+life0: F32, +side: F32, +seed: F32, +sid: U32, +n: U32,
  +x: F32, +s0: F32) -> Puff:
  +tres = ((U32.to_f32(n) - life0 : F32) / 0.30 : F32)
  +emit = (Ride.head.centre((s0 + Ride.speed() * tres : F32)) - 3.0 : F32)
  +h = Rnd.next(U32.add(sid, U32.mul(n, 131)))
  Puff{(x - F32.floor(x) : F32), emit, ((Rnd.f(h) - 0.5 : F32) * 0.5 : F32),
    Rnd.f(Rnd.next(h))}


def Smoke.puff(p: Smoke, +s0: F32, +t: F32) -> Puff:
  Smoke{+life0, +at, +side, +seed, +sid} = p
  +x = (life0 + 0.30 * t : F32)
  +n = F32.to_u32(F32.floor(x))
  Bool.pick(Puff, U32.is_eq(n, 0),
    Puff{(x - F32.floor(x) : F32), at, side, seed},
    Smoke.reborn(life0, side, seed, sid, n, x, s0))


def Ride.puffs.smoke(ps: List<&2, Smoke>, +s0: F32, +t: F32,
  +acc: List<&2, Puff>) -> List<&2, Puff>:
  match ps:
    case []:
      acc
    case p <> rest:
      Ride.puffs.smoke(rest, s0, t,
        List.append(&2, Puff, acc, [Smoke.puff(p, s0, t)]))


def Ride.lamp.smoke.one(p: Puff, +acc: List<&2, Lamp>) -> List<&2, Lamp>:
  Puff{+life, +at, +side, +seed} = p
  +ps = (at - life * 46.0 : F32)
  +x = (Trk.Track.x(ps) + side
    + F32.sin((seed * 12.0 + life * 3.0 : F32)) * life * 3.5 : F32)
  +y = (Trk.Track.y(ps) + 4.6 + life * 7.5 : F32)
  +a = F32.max(0.0, (0.30 * (1.0 - life) * F32.min(1.0, life * 6.0) : F32))
  Lamp{x, y, ps, (2.0 + life * 11.0 : F32), 0.62, 0.63, 0.70, a} <> acc


def Ride.lamp.smoke(ps: List<&2, Puff>, +acc: List<&2, Lamp>)
  -> List<&2, Lamp>:
  match ps:
    case []:
      acc
    case p <> rest:
      Ride.lamp.smoke(rest, Ride.lamp.smoke.one(p, acc))


# ---- the wayside lights ----------------------------------------------
# The signals and the fireflies are the two groups the demo places as a pure
# function of the camera's own `s`, with no generator in them at all: eight
# masts every 176 m, then twenty-eight fireflies blinking half a dozen metres
# off the line.
def Ride.lamp.signal(+k: Nat, +base: F32, +acc: List<&2, Lamp>)
  -> List<&2, Lamp>:
  match k:
    case 0n:
      acc
    case 1n+j:
      +gs = ((base + U32.to_f32(U32.from_nat(j)) : F32) * 176.0 : F32)
      +gx = (Trk.Track.x(gs) - 6.4 : F32)
      +gy = (Trk.Track.y(gs) + 3.8 : F32)
      Ride.lamp.signal(j, base,
        Lamp{gx, gy, gs, 1.2, 0.20, 1.0, 0.43, 0.18} <> (Lamp{gx, gy, gs, 0.26,
          0.30, 1.0, 0.57, 0.9} <> acc))


def Ride.lamp.fly(+k: Nat, +cell0: F32, +t: F32, +acc: List<&2, Lamp>)
  -> List<&2, Lamp>:
  match k:
    case 0n:
      acc
    case 1n+j:
      +cell = (cell0 + U32.to_f32(U32.from_nat(j)) : F32)
      +gs = (cell * 8.0 : F32)
      +x = (Trk.Track.x(gs) - 12.0 - F32.sin(cell * 6.3) * 5.0 : F32)
      +y = (Trk.Track.y(gs) + 1.1 + F32.sin(cell) * 0.7 : F32)
      +blink = F32.pow(F32.max(0.0, F32.sin((t * 0.75 + cell * 3.1 : F32))), 3.0)
      Ride.lamp.fly(j, cell0, t,
        Lamp{x, y, gs, 0.28, 0.73, 0.95, 0.37, (blink * 0.26 : F32)} <> acc)


# The generated groups in the demo's own emission order after the cars and the
# lamps: the dust, the signals, the fireflies, then the plume.  `s0` is where
# the ride began -- the chimney a puff born at t = 0 came from -- and `s` is
# where the camera is now.
def Ride.lamp.world(ld: Loaded, +s: F32, +s0: F32, +t: F32,
  +acc: List<&2, Lamp>) -> List<&2, Lamp>:
  Loaded{+lives, +puffs, +motes, +st} = ld
  +base = (F32.floor(s / 176.0) - 2.0 : F32)
  +cell0 = (F32.floor(s / 8.0) - 8.0 : F32)
  Ride.lamp.signal(8n, base,
    Ride.lamp.fly(28n, cell0, t,
      Ride.lamp.smoke(Ride.puffs.smoke(puffs, s0, t, []),
        Ride.lamp.motes(Ride.motes.evolve(motes, t, []), s, t, acc))))


def Ride.glows.at(ls: List<&2, Lamp>, +cam: Rt.VCam) -> List<&2, Rt.Spr>:
  match ls:
    case []:
      []
    case l <> rest:
      Lamp{x, y, z, r, cr, cg, cb, a} = l
      Rt.Spr.at(cam, x, y, z, r, cr, cg, cb, a, 1) <> Ride.glows.at(rest, cam)


# `s0` is where the ride began; the camera is at `s` now, t seconds later.
def Ride.glows(cam: Rt.VCam, +s: F32, +s0: F32, +head_on: Bool, +t: F32)
  -> List<&2, Rt.Spr>:
  Ride.glows.at(Ride.lamp.cars(Carriage.Carriage.cars_n(), 0, s,
    Ride.lamp.head(head_on, Ride.head.pos(s), s,
      Ride.lamp.world(Loaded.load(s0), s, s0, t, []))), cam)
