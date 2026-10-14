import Base
import ./voxel.bend as Voxel
import ./face.bend as Face
import ./paint.bend as Paint
import ./sky.bend as Sky
import ./texture.bend as Texture
import ./body.bend as Body

# Scenery: what is in the picture and is not a block, and the hour it is.
#
# The sky the painter draws is a gradient, and a gradient has nothing in it to tell a player
# which way they turned, how far they walked or how long they have been out. This puts
# things in it: clouds, which are flat squares at one height the way the game this one is
# modelled on draws them and which drift; the sun, which is a square too and crosses the sky
# in a day; and at night the moon opposite it and the stars. All of them are handed to the
# painter as flat polygons **behind** the scene, so each costs a projection and a pixel is
# still written once: wherever a block is nearer, the block is what is painted.
#
# The clouds are a rule on the world's own cells, so they stay where they are while the
# player walks and the view region moves under them. The frame is drawn in the region's
# cells, so the region's place in the world comes in as `shift_x` and `shift_z`.
#
# The hour is the client's clock, a count of ticks. `Sky` turns it into the air's colours and
# the light, and this module into where the sun is.

# --- clouds ------------------------------------------------------------------------

# A cloud cell is this many world cells across, and the clouds are at this height: above
# the tallest thing the world generates, so the player is always under them.
def cloud_cell() -> F32:
  8.0

def cloud_height() -> F32:
  34.0

# How many cloud cells are looked at to each side of the eye, and the distance over which a
# cloud fades into the air: it is whole at `cloud_near()` and the sky's own colour by the
# edge of what is looked at.
def cloud_reach() -> Nat:
  13n

def cloud_near() -> F32:
  44.0

def cloud_far() -> F32:
  104.0

# How far the clouds have drifted along x after `clock` ticks: a cell every eleven seconds.
def cloud_drift(+clock: U32) -> F32:
  F32.mul(U32.to_f32(clock), 0.012)

# A cloud's own colour at a sun height: white by day, the dark of the sky at night, and lit
# from below at sunrise and sunset.
def cloud_color(+height: F32) -> U32:
  Sky.mix(Sky.mix(Sky.rgb(30, 36, 60), Sky.rgb(238, 243, 250), Sky.daylight(height)),
    Sky.rgb(252, 176, 128), U32.shrn(U32.mul(Sky.dusk(height), 150), 8n))

# Whether a cloud cell holds cloud. Clouds come in clumps four cells across with ragged
# edges: a coarse word picks the clump and a fine one bites pieces out of it.
def cloud_at(+cx: U32, +cz: U32) -> Bool:
  +clump = U32.and(Texture.mix(U32.shrn(cx, 2n), U32.shrn(cz, 2n), 7), 7)
  +piece = U32.and(Texture.mix(cx, cz, 9), 7)
  Bool.or(Bool.and(U32.is_lt(clump, 3), U32.is_lt(piece, 6)),
    Bool.and(U32.is_eq(clump, 3), U32.is_lt(piece, 2)))

def cloud.fade(+dx: F32, +dz: F32) -> U32:
  +away = F32.sqrt(F32.add(F32.mul(dx, dx), F32.mul(dz, dz)))
  F32.to_u32(F32.min(F32.max(F32.mul(F32.div(F32.sub(away, cloud_near()),
    F32.sub(cloud_far(), cloud_near())), 256.0), 0.0), 256.0))

# One cloud cell as a square seen from below, in the region's cells.
def cloud.quad(present: Bool, +x0: F32, +z0: F32, +camera: Voxel.Camera, +half: F32,
  +focal: F32, +size: U32, +white: U32, +haze: U32, next: Paint.Quads) -> Paint.Quads:
  match present:
    case False{}:
      next
    case True{}:
      +x1 = F32.add(x0, cloud_cell())
      +z1 = F32.add(z0, cloud_cell())
      +eye = Face.cam_eye(camera)
      Paint.quads.world(Voxel.Vec{x0, cloud_height(), z0}, Voxel.Vec{x1, cloud_height(), z0},
        Voxel.Vec{x1, cloud_height(), z1}, Voxel.Vec{x0, cloud_height(), z1}, camera, half,
        focal, size,
        Sky.mix(white, haze,
          cloud.fade(F32.sub(F32.add(x0, 4.0), Face.vx(eye)), F32.sub(F32.add(z0, 4.0), Face.vz(eye)))),
        next)

# `off_x` and `off_z` are what a cloud cell's own place is taken from to be the region's: the
# region's place in the world, and along x how far the clouds have drifted.
def cloud.row(remaining: Nat, +cx: U32, +cz: U32, +camera: Voxel.Camera, +half: F32,
  +focal: F32, +size: U32, +off_x: F32, +off_z: F32, +white: U32, +haze: U32,
  next: Paint.Quads) -> Paint.Quads:
  match remaining:
    case 0n:
      next
    case 1n+rest:
      cloud.quad(cloud_at(cx, cz), F32.sub(F32.mul(U32.to_f32(cx), cloud_cell()), off_x),
        F32.sub(F32.mul(U32.to_f32(cz), cloud_cell()), off_z), camera, half, focal, size, white,
        haze,
        cloud.row(rest, U32.add(cx, 1), cz, camera, half, focal, size, off_x, off_z, white, haze,
          next))

def cloud.rows(remaining: Nat, +cx: U32, +cz: U32, +across: Nat, +camera: Voxel.Camera,
  +half: F32, +focal: F32, +size: U32, +off_x: F32, +off_z: F32, +white: U32, +haze: U32,
  next: Paint.Quads) -> Paint.Quads:
  match remaining:
    case 0n:
      next
    case 1n+rest:
      cloud.row(across, cx, cz, camera, half, focal, size, off_x, off_z, white, haze,
        cloud.rows(rest, cx, U32.add(cz, 1), across, camera, half, focal, size, off_x, off_z,
          white, haze, next))

# The cloud cell a coordinate is in. World coordinates are far above zero wherever a player
# can stand, so the cell is a plain word.
def cloud_cell_of(+world: F32) -> U32:
  F32.to_u32(F32.floor(F32.div(F32.max(world, 0.0), cloud_cell())))

def clouds(+camera: Voxel.Camera, +half: F32, +focal: F32, +size: U32, +off_x: F32,
  +off_z: F32, +white: U32, +haze: U32, next: Paint.Quads) -> Paint.Quads:
  +eye = Face.cam_eye(camera)
  +across = Nat.add(Nat.mul(2n, cloud_reach()), 1n)
  +reach = U32.from_nat(cloud_reach())
  cloud.rows(across, U32.sub(cloud_cell_of(F32.add(Face.vx(eye), off_x)), reach),
    U32.sub(cloud_cell_of(F32.add(Face.vz(eye), off_z)), reach), across, camera, half, focal,
    size, off_x, off_z, white, haze, next)

# --- the sun and the moon ----------------------------------------------------------
#
# The sun goes round once a day in a plane tilted toward +z: it rises along +x, is highest
# toward +z and a little short of overhead, and sets along -x. The tilt is the side the
# painter's three face brightnesses already say the light comes from — tops brightest, the
# sides that face along z next and the ones along x least — so at midday the picture and the
# light agree.

def sun_way(+turn: F32) -> Voxel.Vec:
  Voxel.Vec{F32.cos(turn), F32.mul(0.8, F32.sin(turn)), F32.mul(0.6, F32.sin(turn))}

# Two directions across the sun's disc, at right angles to `sun_way` and to each other.
def sun_across() -> Voxel.Vec:
  Voxel.Vec{0.0, F32.neg(0.6), 0.8}

def sun_up(+turn: F32) -> Voxel.Vec:
  Voxel.Vec{F32.sin(turn), F32.neg(F32.mul(0.8, F32.cos(turn))), F32.neg(F32.mul(0.6, F32.cos(turn)))}

def far_away() -> F32:
  300.0

def disc.corner(+centre: Voxel.Vec, +turn: F32, +a: F32, +b: F32) -> Voxel.Vec:
  Voxel.Vec.add(centre, Voxel.Vec.add(Voxel.Vec.scale(sun_across(), a), Voxel.Vec.scale(sun_up(turn), b)))

# A square of half-width `reach` facing the eye from `way`, or nothing when that is under
# the horizon: the ground would not hide it, because past the region there is no ground.
def disc.at(up: Bool, +way: Voxel.Vec, +turn: F32, +reach: F32, color: U32,
  +camera: Voxel.Camera, +half: F32, +focal: F32, +size: U32, next: Paint.Quads) -> Paint.Quads:
  match up:
    case False{}:
      next
    case True{}:
      +centre : Voxel.Vec = Voxel.Vec.add(Face.cam_eye(camera), Voxel.Vec.scale(way, far_away()))
      Paint.quads.world(disc.corner(centre, turn, F32.neg(reach), F32.neg(reach)),
        disc.corner(centre, turn, reach, F32.neg(reach)), disc.corner(centre, turn, reach, reach),
        disc.corner(centre, turn, F32.neg(reach), reach), camera, half, focal, size, color, next)

def disc(+way: Voxel.Vec, +turn: F32, +reach: F32, color: U32, +camera: Voxel.Camera,
  +half: F32, +focal: F32, +size: U32, next: Paint.Quads) -> Paint.Quads:
  disc.at(F32.is_gt(Face.vy(way), F32.neg(0.1)), way, turn, reach, color, camera, half, focal,
    size, next)

# The sun in front of a wider and paler square that is its glare, both turning orange as it
# nears the horizon; and the moon opposite it.
def sun_and_moon(+turn: F32, +height: F32, +camera: Voxel.Camera, +half: F32, +focal: F32,
  +size: U32, next: Paint.Quads) -> Paint.Quads:
  +low = Sky.dusk(height)
  disc(sun_way(turn), turn, 17.0, Sky.mix(Sky.rgb(255, 252, 232), Sky.rgb(255, 178, 84), low),
    camera, half, focal, size,
    disc(sun_way(turn), turn, 25.0, Sky.mix(Sky.rgb(250, 240, 200), Sky.rgb(248, 150, 92), low),
      camera, half, focal, size,
      disc(Voxel.Vec.scale(sun_way(turn), F32.neg(1.0)), turn, 12.0, Sky.rgb(226, 232, 244),
        camera, half, focal, size, next)))

# --- the stars ---------------------------------------------------------------------
#
# A star is a word: where it is in the upper half of the sky comes out of its number, and so
# does how bright it is. They are there all day and seen only when the sky is dark, so their
# colour is the sky's own by day and their own at night.

def star_count() -> Nat:
  90n

def star_way(+star: U32) -> Voxel.Vec:
  +x = F32.sub(F32.div(U32.to_f32(U32.and(Texture.mix(star, 1, 211), 1023)), 511.5), 1.0)
  +z = F32.sub(F32.div(U32.to_f32(U32.and(Texture.mix(star, 2, 223), 1023)), 511.5), 1.0)
  +y = F32.add(0.12, F32.div(U32.to_f32(U32.and(Texture.mix(star, 3, 227), 1023)), 1100.0))
  Voxel.Vec.unit(Voxel.Vec{x, y, z})

def star.quad(+way: Voxel.Vec, color: U32, +camera: Voxel.Camera, +half: F32, +focal: F32,
  +size: U32, next: Paint.Quads) -> Paint.Quads:
  +centre : Voxel.Vec = Voxel.Vec.add(Face.cam_eye(camera), Voxel.Vec.scale(way, far_away()))
  Paint.quads.world(Voxel.Vec.add(centre, Voxel.Vec{F32.neg(0.9), 0.0, F32.neg(0.9)}),
    Voxel.Vec.add(centre, Voxel.Vec{0.9, 0.0, F32.neg(0.9)}),
    Voxel.Vec.add(centre, Voxel.Vec{0.9, 1.8, 0.9}),
    Voxel.Vec.add(centre, Voxel.Vec{F32.neg(0.9), 1.8, 0.9}), camera, half, focal, size, color, next)

def stars.go(remaining: Nat, +star: U32, +lit: U32, +camera: Voxel.Camera, +half: F32,
  +focal: F32, +size: U32, next: Paint.Quads) -> Paint.Quads:
  match remaining:
    case 0n:
      next
    case 1n+rest:
      star.quad(star_way(star), lit, camera, half, focal, size,
        stars.go(rest, U32.add(star, 1), lit, camera, half, focal, size, next))

def stars.at(dark: Bool, +lit: U32, +camera: Voxel.Camera, +half: F32, +focal: F32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  match dark:
    case False{}:
      next
    case True{}:
      stars.go(star_count(), 0, lit, camera, half, focal, size, next)

# The stars, once the day's light is under a third of itself, brightening as it goes.
def stars(+height: F32, +air: U32, +camera: Voxel.Camera, +half: F32, +focal: F32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  +day = Sky.daylight(height)
  stars.at(U32.is_lt(day, 84), Sky.mix(Sky.rgb(226, 232, 255), Sky.zenith_of(air), U32.mul(day, 3)),
    camera, half, focal, size, next)

# --- the frame ---------------------------------------------------------------------

# Everything behind the scene, nearest first: the clouds, then the sun and the moon, then
# the stars.
#
# `clock` is the client's own count of ticks, which is how far the clouds have drifted, and
# `hour` is the clock the sun is read from. Alone they are one number. In a room the hour is
# the room's, whose day is shorter, and the clouds still drift at their own pace.
def backdrop_at(+camera: Voxel.Camera, +half: F32, +focal: F32, +size: U32, +shift_x: F32,
  +shift_z: F32, +clock: U32, +hour: U32) -> Paint.Quads:
  +height = Sky.sun_height(hour)
  +air = Sky.air_at(hour)
  clouds(camera, half, focal, size, F32.add(shift_x, cloud_drift(clock)), shift_z,
    cloud_color(height), Sky.haze_of(air),
    sun_and_moon(Sky.turn(hour), height, camera, half, focal, size,
      stars(height, air, camera, half, focal, size, Paint.QNil{})))

def backdrop(+camera: Voxel.Camera, +half: F32, +focal: F32, +size: U32, +shift_x: F32,
  +shift_z: F32, +clock: U32) -> Paint.Quads:
  backdrop_at(camera, half, focal, size, shift_x, shift_z, clock, clock)

# The client's frame: the scene textured and lit, in the painter's tiles, under an overlay,
# in front of the sky's clouds, sun, moon and stars, at the hour `hour` says. `bodies` is
# the room's other players, in the region's cells, standing among the blocks.
def paint_among(groups: List<&2, Paint.Group>, +eye: Voxel.Vec, +yaw: F32, +pitch: F32,
  +depth: Nat, over: Paint.Quads, +shift_x: F32, +shift_z: F32, +clock: U32, +hour: U32,
  bodies: List<&2, Body.Body>) -> Image:
  +camera : Voxel.Camera = Voxel.Camera.look(eye, yaw, pitch)
  +half = Voxel.projection_half(depth)
  +focal = F32.mul(1.5, half)
  +size = U32.shln((1 : U32), depth)
  Paint.image.of(Paint.tiles_frame_among(groups, camera, half, focal, size, depth,
    Paint.tile_of(depth), over,
    Body.drawn(bodies, camera, half, focal, size, Sky.haze_of(Sky.air_at(hour)), Sky.level_at(hour)),
    backdrop_at(camera, half, focal, size, shift_x, shift_z, clock, hour),
    True{}, Sky.air_at(hour), Sky.level_at(hour)))

def paint(groups: List<&2, Paint.Group>, +eye: Voxel.Vec, +yaw: F32, +pitch: F32, +depth: Nat,
  over: Paint.Quads, +shift_x: F32, +shift_z: F32, +clock: U32) -> Image:
  paint_among(groups, eye, yaw, pitch, depth, over, shift_x, shift_z, clock, clock, [])

# The same frame as one tile, each cell the colour it shows: what a test or a picture reads.
def pixels_among(groups: List<&2, Paint.Group>, +eye: Voxel.Vec, +yaw: F32, +pitch: F32,
  +depth: Nat, over: Paint.Quads, +shift_x: F32, +shift_z: F32, +clock: U32, +hour: U32,
  bodies: List<&2, Body.Body>) -> Array<U32>:
  +camera : Voxel.Camera = Voxel.Camera.look(eye, yaw, pitch)
  +half = Voxel.projection_half(depth)
  +focal = F32.mul(1.5, half)
  +size = U32.shln((1 : U32), depth)
  Paint.frame_pixels_among(groups, camera, half, focal, size, depth, over,
    Body.drawn(bodies, camera, half, focal, size, Sky.haze_of(Sky.air_at(hour)), Sky.level_at(hour)),
    backdrop_at(camera, half, focal, size, shift_x, shift_z, clock, hour), True{}, Sky.air_at(hour),
    Sky.level_at(hour))

def pixels(groups: List<&2, Paint.Group>, +eye: Voxel.Vec, +yaw: F32, +pitch: F32, +depth: Nat,
  over: Paint.Quads, +shift_x: F32, +shift_z: F32, +clock: U32) -> Array<U32>:
  pixels_among(groups, eye, yaw, pitch, depth, over, shift_x, shift_z, clock, clock, [])
