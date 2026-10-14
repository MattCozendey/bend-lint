import Base
import ./voxel.bend as Voxel
import ./paint.bend as Paint
import ./sky.bend as Sky
import ./texture.bend as Texture
import ./hud.bend as Hud

# Body: what stands in a room's world and is not a block, as the painter draws it — the
# other players, the mobs, the villagers and the items lying on the ground.
#
# Each is a few boxes in flat colours, in the proportions the browser draws
# (`web/mob-models.js`), standing still: nothing swings, bobs or blinks. A player is legs, a
# torso, two arms, a head, its hair and two eyes; the eyes are what says which way any of
# them faces.
#
# The painter has no depth buffer. It paints nearest first, and a pixel is whatever wrote it
# first, so a body is not laid over the frame: each side of each box is a polygon handed to
# the painter **among** the faces, with how far its box is, and takes its place in the same
# buckets (`Paint.linked`). That is what puts a pig behind a wall behind it. Two things
# follow from the order being a bucket per whole cell:
#
# - within a bucket the painter keeps the order it was given, so the bodies are handed over
#   nearest body first, each one's sides nearest box first, and all of them before the faces:
#   a body is in front of the block it stands on;
# - a body right behind a block less than a cell further off can share the block's bucket,
#   and then shows through it. A player pressed against the far side of a wall one block
#   thick can be seen at its edges.
#
# A box only hands over the sides that face the eye. They are at most three, they do not
# overlap each other, and so what order they are painted in does not matter.

# Where a body's feet are, in the cells of the region the frame is painted from, the way it
# faces — `Player.direction`'s yaw, 0 toward -z — and what it is: 0 a player, 1 to 6 the
# kinds of `world/entities.bend` (pig, zombie, sheep, brute, cow, chicken), 11 and 12 a
# villager in a brown or a green robe, and 1000 and up an item on the ground, the item's id
# above the thousand. A villager turns to whoever looks at it, as the browser's does.
type Body is Data:
  Body{kind: U32, x: F32, y: F32, z: F32, yaw: F32}

def player_kind() -> U32:
  0

def villager_kind() -> U32:
  10

def drop_kind() -> U32:
  1000

def skin() -> U32:
  Sky.rgb(214, 164, 124)

def hair() -> U32:
  Sky.rgb(74, 50, 34)

def shirt() -> U32:
  Sky.rgb(42, 150, 160)

def sleeve() -> U32:
  Sky.rgb(34, 122, 132)

def pants() -> U32:
  Sky.rgb(58, 66, 122)

def eye() -> U32:
  Sky.rgb(32, 28, 44)

# The light a side takes, over 256: the top all of it, the front and the back most, the two
# flanks less and the underside least. A body has no corner levels; it is lit by where its
# sides point and by the hour.
def light_up() -> U32:
  256

def light_front() -> U32:
  215

def light_flank() -> U32:
  184

def light_down() -> U32:
  140

# A colour under a side's light at an hour's `level`, which is `Sky.level_at`'s.
def tone(+color: U32, +light: U32, +level: U32) -> U32:
  Texture.scaled(color, U32.shrn(U32.mul(light, Sky.level_light(level)), 8n))

# --- the order ---------------------------------------------------------------------

# `list` is polygons nearest first, and the answer is the list with one more in its place.
# The whole list is walked: it is a few dozen polygons, and a walk that stopped early would
# have to hand a list it had rebuilt back to itself, which the checker does not take for a
# smaller one.
def placed(list: List<&2, Paint.Drawn>, +done: Bool, +depth: F32, +quad: Paint.Quads,
  +acc: List<&2, Paint.Drawn>) -> List<&2, Paint.Drawn>:
  match list:
    case Nil{}:
      List.reverse(&2, Paint.Drawn,
        Bool.pick(List<&2, Paint.Drawn>, done, acc, Paint.Drawn{depth, quad} <> acc))
    case Paint.Drawn{+d, +q} <> rest:
      +now = Bool.and(Bool.not(done), F32.is_lt(depth, d))
      placed(rest, Bool.or(done, now), depth, quad,
        Paint.Drawn{d, q} <> Bool.pick(List<&2, Paint.Drawn>, now, Paint.Drawn{depth, quad} <> acc, acc))

# A side cut wholly away at the near plane, or off the frame, has no polygon.
def put(+quad: Paint.Quads, +depth: F32, +kept: List<&2, Paint.Drawn>) -> List<&2, Paint.Drawn>:
  match quad:
    case Paint.QNil{}:
      kept
    case _:
      placed(kept, False{}, depth, quad, [])

# --- a box -------------------------------------------------------------------------

def minus(+a: Voxel.Vec, +b: Voxel.Vec) -> Voxel.Vec:
  Voxel.Vec.add(a, Voxel.Vec.scale(b, F32.neg(1.0)))

def eye_of(camera: Voxel.Camera) -> Voxel.Vec:
  Voxel.Camera{eye, forward, right, up} = camera
  eye

def side.at(shown: Bool, +p: Voxel.Vec, +u: Voxel.Vec, +v: Voxel.Vec, color: U32, +depth: F32,
  +camera: Voxel.Camera, +half: F32, +focal: F32, +size: U32,
  +kept: List<&2, Paint.Drawn>) -> List<&2, Paint.Drawn>:
  match shown:
    case False{}:
      kept
    case True{}:
      put(Paint.quads.world(Voxel.Vec.add(Voxel.Vec.add(p, u), v), minus(Voxel.Vec.add(p, u), v),
          minus(minus(p, u), v), Voxel.Vec.add(minus(p, u), v), camera, half, focal, size, color,
          Paint.QNil{}),
        depth, kept)

# One side of a box whose middle is `c`: `n` reaches from there to the side's own middle, and
# `u` and `v` from that to its edges. It is handed over when the eye is on its open side.
def side(+c: Voxel.Vec, +n: Voxel.Vec, +u: Voxel.Vec, +v: Voxel.Vec, color: U32, +depth: F32,
  +camera: Voxel.Camera, +half: F32, +focal: F32, +size: U32,
  +kept: List<&2, Paint.Drawn>) -> List<&2, Paint.Drawn>:
  +p : Voxel.Vec = Voxel.Vec.add(c, n)
  side.at(F32.is_gt(Voxel.Vec.dot(n, minus(eye_of(camera), p)), 0.0), p, u, v, color, depth,
    camera, half, focal, size, kept)

# How far a point is from the eye, summed along the three axes: the painter's own measure for
# a block (`Paint.cell_distance`), so a box and a block are in one order.
def summed(d: Voxel.Vec) -> F32:
  Voxel.Vec{dx, dy, dz} = d
  F32.add(F32.add(F32.abs(dx), F32.abs(dy)), F32.abs(dz))

def away(+c: Voxel.Vec, +eye: Voxel.Vec) -> F32:
  summed(minus(c, eye))

# How much air is between the eye and a point, over 256, as a face's pixel has it.
def air_to(+c: Voxel.Vec, +eye: Voxel.Vec) -> U32:
  +d : Voxel.Vec = minus(c, eye)
  Paint.air_of(0, F32.mul(F32.sqrt(Voxel.Vec.dot(d, d)), Sky.fog_scale()))

def shade(+color: U32, +light: U32, +level: U32, +air: U32, +haze: U32) -> U32:
  Sky.hazed(tone(color, light, level), air, haze)

# A box whose middle is `c`, reaching `r`, `u` and `f` from it to its sides: across the body,
# up it, and the way it faces.
def box(+c: Voxel.Vec, +r: Voxel.Vec, +u: Voxel.Vec, +f: Voxel.Vec, +color: U32, +level: U32,
  +haze: U32, +camera: Voxel.Camera, +half: F32, +focal: F32, +size: U32,
  +kept: List<&2, Paint.Drawn>) -> List<&2, Paint.Drawn>:
  +depth = away(c, eye_of(camera))
  +air = air_to(c, eye_of(camera))
  +back : Voxel.Vec = Voxel.Vec.scale(f, F32.neg(1.0))
  +left : Voxel.Vec = Voxel.Vec.scale(r, F32.neg(1.0))
  +under : Voxel.Vec = Voxel.Vec.scale(u, F32.neg(1.0))
  side(c, f, r, u, shade(color, light_front(), level, air, haze), depth, camera, half, focal, size,
    side(c, back, r, u, shade(color, light_front(), level, air, haze), depth, camera, half, focal, size,
      side(c, r, u, f, shade(color, light_flank(), level, air, haze), depth, camera, half, focal, size,
        side(c, left, u, f, shade(color, light_flank(), level, air, haze), depth, camera, half, focal, size,
          side(c, u, r, f, shade(color, light_up(), level, air, haze), depth, camera, half, focal, size,
            side(c, under, r, f, shade(color, light_down(), level, air, haze), depth, camera, half, focal,
              size, kept))))))

# --- the shapes --------------------------------------------------------------------

# What a part is drawn with: where the body's feet are, its unit vectors across and ahead,
# and the frame's light, air and camera.
type Pen is Data:
  Pen{feet: Voxel.Vec, r: Voxel.Vec, f: Voxel.Vec, level: U32, haze: U32, camera: Voxel.Camera,
    half: F32, focal: F32, size: U32}

# One part of a body: its middle is `across`, `up` and `ahead` of the feet, and it reaches
# `hx`, `hy` and `hz` from there.
def part(pen: Pen, +across: F32, +up: F32, +ahead: F32, +hx: F32, +hy: F32, +hz: F32, +color: U32,
  +kept: List<&2, Paint.Drawn>) -> List<&2, Paint.Drawn>:
  Pen{+feet, +r, +f, +level, +haze, +camera, +half, +focal, +size} = pen
  box(Voxel.Vec.add(Voxel.Vec.add(Voxel.Vec.add(feet, Voxel.Vec.scale(r, across)), Voxel.Vec{0.0, up, 0.0}),
      Voxel.Vec.scale(f, ahead)),
    Voxel.Vec.scale(r, hx), Voxel.Vec{0.0, hy, 0.0}, Voxel.Vec.scale(f, hz), color, level, haze,
    camera, half, focal, size, kept)

# Two eyes, `across` to each side.
def eyes(+pen: Pen, +across: F32, +up: F32, +ahead: F32, +kept: List<&2, Paint.Drawn>) -> List<&2, Paint.Drawn>:
  part(pen, across, up, ahead, 0.035, 0.035, 0.01, eye(),
    part(pen, F32.neg(across), up, ahead, 0.035, 0.035, 0.01, eye(), kept))

# Four legs under a body, `across` to each side, `fore` ahead and `hind` behind.
def legs(+pen: Pen, +across: F32, +fore: F32, +hind: F32, +hx: F32, +hy: F32, +color: U32,
  +kept: List<&2, Paint.Drawn>) -> List<&2, Paint.Drawn>:
  part(pen, across, hy, fore, hx, hy, hx, color,
    part(pen, F32.neg(across), hy, fore, hx, hy, hx, color,
      part(pen, across, hy, F32.neg(hind), hx, hy, hx, color,
        part(pen, F32.neg(across), hy, F32.neg(hind), hx, hy, hx, color, kept))))

def player(+pen: Pen, +kept: List<&2, Paint.Drawn>) -> List<&2, Paint.Drawn>:
  part(pen, 0.0, 0.375, 0.0, 0.22, 0.375, 0.1, pants(),
    part(pen, 0.0, 1.11, 0.0, 0.25, 0.36, 0.14, shirt(),
      part(pen, 0.34, 1.12, 0.0, 0.09, 0.33, 0.09, sleeve(),
        part(pen, F32.neg(0.34), 1.12, 0.0, 0.09, 0.33, 0.09, sleeve(),
          part(pen, 0.0, 1.68, 0.0, 0.23, 0.23, 0.22, skin(),
            part(pen, 0.0, 1.94, 0.0, 0.24, 0.03, 0.23, hair(),
              eyes(pen, 0.1, 1.72, 0.225, kept)))))))

def pig_skin() -> U32:
  Sky.rgb(238, 180, 184)

def pig_snout() -> U32:
  Sky.rgb(214, 140, 150)

def pig(+pen: Pen, +kept: List<&2, Paint.Drawn>) -> List<&2, Paint.Drawn>:
  part(pen, 0.0, 0.62, F32.neg(0.08), 0.32, 0.29, 0.51, pig_skin(),
    part(pen, 0.0, 0.85, 0.55, 0.26, 0.23, 0.22, pig_skin(),
      part(pen, 0.0, 0.76, 0.79, 0.1, 0.075, 0.03, pig_snout(),
        eyes(pen, 0.1, 0.9, 0.775, legs(pen, 0.2, 0.3, 0.38, 0.08, 0.2, pig_snout(), kept)))))

def zombie_skin() -> U32:
  Sky.rgb(92, 140, 84)

def zombie_shirt() -> U32:
  Sky.rgb(58, 110, 120)

def brute_skin() -> U32:
  Sky.rgb(70, 104, 70)

def brute_shirt() -> U32:
  Sky.rgb(72, 60, 52)

def brute_pants() -> U32:
  Sky.rgb(44, 44, 56)

# The two that hunt: a player's shape with the arms held out ahead, `wide` times as broad.
def undead(+pen: Pen, +wide: F32, +flesh: U32, +cloth: U32, +trousers: U32,
  +kept: List<&2, Paint.Drawn>) -> List<&2, Paint.Drawn>:
  part(pen, 0.0, 0.375, 0.0, F32.mul(0.22, wide), 0.375, 0.1, trousers,
    part(pen, 0.0, 1.11, 0.0, F32.mul(0.25, wide), 0.36, 0.14, cloth,
      part(pen, F32.mul(0.34, wide), 1.34, 0.3, 0.09, 0.09, 0.33, flesh,
        part(pen, F32.neg(F32.mul(0.34, wide)), 1.34, 0.3, 0.09, 0.09, 0.33, flesh,
          part(pen, 0.0, 1.68, 0.0, F32.mul(0.23, wide), 0.23, 0.22, flesh,
            eyes(pen, 0.1, 1.72, 0.225, kept))))))

def wool() -> U32:
  Sky.rgb(242, 238, 228)

def sheep_face() -> U32:
  Sky.rgb(196, 176, 156)

def sheep(+pen: Pen, +kept: List<&2, Paint.Drawn>) -> List<&2, Paint.Drawn>:
  part(pen, 0.0, 0.86, F32.neg(0.06), 0.35, 0.34, 0.52, wool(),
    part(pen, 0.0, 1.12, 0.6, 0.2, 0.21, 0.2, sheep_face(),
      eyes(pen, 0.09, 1.16, 0.805, legs(pen, 0.18, 0.32, 0.36, 0.07, 0.26, sheep_face(), kept))))

def cow_hide() -> U32:
  Sky.rgb(112, 78, 52)

def cow_snout() -> U32:
  Sky.rgb(222, 192, 172)

def cow(+pen: Pen, +kept: List<&2, Paint.Drawn>) -> List<&2, Paint.Drawn>:
  part(pen, 0.0, 0.88, F32.neg(0.04), 0.39, 0.37, 0.6, cow_hide(),
    part(pen, 0.0, 1.14, 0.66, 0.22, 0.22, 0.22, cow_hide(),
      part(pen, 0.0, 1.03, 0.91, 0.15, 0.1, 0.04, cow_snout(),
        eyes(pen, 0.1, 1.2, 0.885, legs(pen, 0.22, 0.38, 0.42, 0.08, 0.25, cow_hide(), kept)))))

def feather() -> U32:
  Sky.rgb(242, 238, 224)

def beak() -> U32:
  Sky.rgb(230, 160, 50)

def comb() -> U32:
  Sky.rgb(200, 40, 40)

def chicken(+pen: Pen, +kept: List<&2, Paint.Drawn>) -> List<&2, Paint.Drawn>:
  part(pen, 0.0, 0.36, 0.0, 0.17, 0.18, 0.22, feather(),
    part(pen, 0.0, 0.56, 0.16, 0.08, 0.1, 0.07, feather(),
      part(pen, 0.0, 0.6, 0.26, 0.05, 0.045, 0.03, beak(),
        part(pen, 0.0, 0.72, 0.14, 0.025, 0.045, 0.06, comb(),
          part(pen, 0.07, 0.09, 0.0, 0.025, 0.09, 0.025, beak(),
            part(pen, F32.neg(0.07), 0.09, 0.0, 0.025, 0.09, 0.025, beak(), kept))))))

def robe_brown() -> U32:
  Sky.rgb(120, 84, 56)

def robe_green() -> U32:
  Sky.rgb(70, 120, 70)

def villager(+pen: Pen, +robe: U32, +kept: List<&2, Paint.Drawn>) -> List<&2, Paint.Drawn>:
  part(pen, 0.0, 0.58, 0.0, 0.33, 0.56, 0.26, robe,
    part(pen, 0.36, 1.12, 0.0, 0.095, 0.31, 0.095, robe,
      part(pen, F32.neg(0.36), 1.12, 0.0, 0.095, 0.31, 0.095, robe,
        part(pen, 0.0, 1.5, 0.0, 0.21, 0.21, 0.21, skin(),
          part(pen, 0.0, 1.46, 0.26, 0.06, 0.1, 0.05, skin(),
            eyes(pen, 0.09, 1.56, 0.215, kept))))))

# An item on the ground: a small cube in the colour the hotbar shows the item in.
def drop(pen: Pen, +color: U32, +kept: List<&2, Paint.Drawn>) -> List<&2, Paint.Drawn>:
  part(pen, 0.0, 0.14, 0.0, 0.14, 0.14, 0.14, color, kept)

# Which shape a kind is, as a small number: a kind the roster does not know is a zombie, the
# one body a stranger is least likely to be mistaken for, as in the browser.
def shape_of(+kind: U32) -> Nat:
  U32.to_nat(Bool.pick(U32, U32.is_ge(kind, drop_kind()), 9,
    Bool.pick(U32, U32.is_eq(kind, 12), 8,
      Bool.pick(U32, U32.is_ge(kind, villager_kind()), 7,
        Bool.pick(U32, U32.is_gt(kind, 6), 2, kind)))))

def shaped(shape: Nat, +kind: U32, +pen: Pen, +kept: List<&2, Paint.Drawn>) -> List<&2, Paint.Drawn>:
  match shape:
    case 0n:
      player(pen, kept)
    case 1n:
      pig(pen, kept)
    case 2n:
      undead(pen, 1.0, zombie_skin(), zombie_shirt(), pants(), kept)
    case 3n:
      sheep(pen, kept)
    case 4n:
      undead(pen, 1.3, brute_skin(), brute_shirt(), brute_pants(), kept)
    case 5n:
      cow(pen, kept)
    case 6n:
      chicken(pen, kept)
    case 7n:
      villager(pen, robe_brown(), kept)
    case 8n:
      villager(pen, robe_green(), kept)
    case _:
      drop(pen, Hud.item_color(U32.sub(kind, drop_kind())), kept)

# --- the frame's bodies ------------------------------------------------------------

def feet_of(body: Body) -> Voxel.Vec:
  Body{kind, x, y, z, yaw} = body
  Voxel.Vec{x, y, z}

def kind_of(body: Body) -> U32:
  Body{kind, x, y, z, yaw} = body
  kind

# The way a body faces: its own, or toward the eye when it is a villager.
def toward(d: Voxel.Vec) -> F32:
  Voxel.Vec{dx, dy, dz} = d
  F32.atan2(dx, F32.neg(dz))

def facing(+body: Body, +eye: Voxel.Vec) -> F32:
  Body{+kind, x, y, z, yaw} = body
  Bool.pick(F32, Bool.and(U32.is_ge(kind, villager_kind()), U32.is_lt(kind, drop_kind())),
    toward(minus(eye, feet_of(body))), yaw)

# One body's polygons, nearest first.
def one(+body: Body, +yaw: F32, +level: U32, +haze: U32, +camera: Voxel.Camera, +half: F32,
  +focal: F32, +size: U32) -> List<&2, Paint.Drawn>:
  shaped(shape_of(kind_of(body)), kind_of(body),
    Pen{feet_of(body), Voxel.Vec{F32.cos(yaw), 0.0, F32.sin(yaw)},
      Voxel.Vec{F32.sin(yaw), 0.0, F32.neg(F32.cos(yaw))}, level, haze, camera, half, focal, size},
    [])

# How far a body is, by the painter's measure, from its middle.
def body_away(+body: Body, +eye: Voxel.Vec) -> F32:
  away(Voxel.Vec.add(feet_of(body), Voxel.Vec{0.0, 0.9, 0.0}), eye)

def forward_of(camera: Voxel.Camera) -> Voxel.Vec:
  Voxel.Camera{eye, forward, right, up} = camera
  forward

# Whether a body can be in the frame: near enough to be seen through the air, and not
# behind the eye by more than its own reach.
def within(+body: Body, +camera: Voxel.Camera) -> Bool:
  +d : Voxel.Vec = minus(Voxel.Vec.add(feet_of(body), Voxel.Vec{0.0, 0.9, 0.0}), eye_of(camera))
  Bool.and(F32.is_le(Voxel.Vec.dot(d, d), Sky.fog_reach()),
    F32.is_gt(Voxel.Vec.dot(d, forward_of(camera)), F32.neg(2.0)))

# The bodies that can be in the frame, farthest first: `list` is in that order already and
# the answer is the list with one more in its place. The whole list is walked, as `placed`
# walks its own.
def ranked(list: List<&2, Body>, +done: Bool, +body: Body, +eye: Voxel.Vec,
  +acc: List<&2, Body>) -> List<&2, Body>:
  match list:
    case Nil{}:
      List.reverse(&2, Body, Bool.pick(List<&2, Body>, done, acc, body <> acc))
    case +head <> rest:
      +now = Bool.and(Bool.not(done), F32.is_gt(body_away(body, eye), body_away(head, eye)))
      ranked(rest, Bool.or(done, now), body, eye,
        head <> Bool.pick(List<&2, Body>, now, body <> acc, acc))

def rank.at(kept: Bool, +body: Body, +eye: Voxel.Vec, +so_far: List<&2, Body>) -> List<&2, Body>:
  match kept:
    case False{}:
      so_far
    case True{}:
      ranked(so_far, False{}, body, eye, [])

def rank.go(bodies: List<&2, Body>, +camera: Voxel.Camera, +so_far: List<&2, Body>) -> List<&2, Body>:
  match bodies:
    case Nil{}:
      so_far
    case +body <> rest:
      rank.go(rest, camera, rank.at(within(body, camera), body, eye_of(camera), so_far))

# `bodies` is farthest first, so each one's polygons go in front of the ones so far.
def drawn.go(bodies: List<&2, Body>, +level: U32, +haze: U32, +camera: Voxel.Camera, +half: F32,
  +focal: F32, +size: U32, +kept: List<&2, Paint.Drawn>) -> List<&2, Paint.Drawn>:
  match bodies:
    case Nil{}:
      kept
    case +body <> rest:
      drawn.go(rest, level, haze, camera, half, focal, size,
        List.append(&2, Paint.Drawn,
          one(body, facing(body, eye_of(camera)), level, haze, camera, half, focal, size), kept))

# Every body's polygons, nearest first, each with how far its box is: what the painter takes
# among the faces. `haze` is the colour of the air and `level` how bright the hour is.
#
# The bodies are put in order first, and then each one's boxes among themselves, so a body
# is never sorted against another's boxes: forty of them are forty short lists and not one
# long one.
def drawn(bodies: List<&2, Body>, +camera: Voxel.Camera, +half: F32, +focal: F32, +size: U32,
  +haze: U32, +level: U32) -> List<&2, Paint.Drawn>:
  drawn.go(rank.go(bodies, camera, []), level, haze, camera, half, focal, size, [])
