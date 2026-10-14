import Base
import ./voxel.bend as Voxel
import ./face.bend as Face
import ./paint.bend as Paint
import ./sky.bend as Sky
import ./scenery.bend as Scenery

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "scenery: " ++ message)

def close(+a: F32, +b: F32) -> Bool:
  F32.is_lt(F32.abs(F32.sub(a, b)), 0.001)

def noon() -> U32:
  10800

def midnight() -> U32:
  32400

# The sun's direction is a unit vector, the two directions across its disc are at right
# angles to it and to each other at every hour, it rises along +x and at noon it is high and
# toward +z, which is the side the faces' brightnesses say the light comes from.
def the_sun_goes_round() -> IO(Unit):
  do IO<Unit>:
    +turn : F32 = Sky.turn(7000)
    +way : Voxel.Vec = Scenery.sun_way(turn)
    Unit <- check(close(Voxel.Vec.dot(way, way), 1.0), "the sun's direction is not a unit vector")
    Unit <- check(close(Voxel.Vec.dot(way, Scenery.sun_across()), 0.0), "the disc's first side is not across the sun's direction")
    Unit <- check(close(Voxel.Vec.dot(way, Scenery.sun_up(turn)), 0.0), "the disc's second side is not across the sun's direction")
    Unit <- check(close(Voxel.Vec.dot(Scenery.sun_across(), Scenery.sun_up(turn)), 0.0), "the disc's sides are not square to each other")
    Unit <- check(close(Face.vx(Scenery.sun_way(Sky.turn(0))), 1.0), "the sun does not rise along +x")
    Unit <- check(F32.is_gt(Face.vy(Scenery.sun_way(Sky.turn(noon()))), 0.7), "the sun is not high at noon")
    Unit <- check(F32.is_gt(Face.vz(Scenery.sun_way(Sky.turn(noon()))), 0.5), "the sun is not toward +z at noon")
    check(F32.is_lt(Face.vy(Scenery.sun_way(Sky.turn(midnight()))), F32.neg(0.7)), "the sun is not under the world at midnight")

# How many of a square of cloud cells hold cloud.
def clouds_in.row(remaining: Nat, +cx: U32, +cz: U32, +count: U32) -> U32:
  match remaining:
    case 0n:
      count
    case 1n+rest:
      clouds_in.row(rest, U32.add(cx, 1), cz, U32.add(count, Bool.to_u32(Scenery.cloud_at(cx, cz))))

def clouds_in(remaining: Nat, +cz: U32, +count: U32) -> U32:
  match remaining:
    case 0n:
      count
    case 1n+rest:
      clouds_in(rest, U32.add(cz, 1), clouds_in.row(64n, 4000, cz, count))

# The sky is partly cloud: between a fifth and a half of it, over a square of 4096 cells
# where the player's world is. A cloud cell is the same cell every time it is asked, and the
# clouds drift a cell in under twelve seconds and never backwards.
def the_sky_is_partly_cloud() -> IO(Unit):
  do IO<Unit>:
    +count : U32 = clouds_in(64n, 4000, 0)
    Unit <- check(U32.is_gt(count, 819), "under a fifth of the sky is cloud")
    Unit <- check(U32.is_lt(count, 2048), "over half of the sky is cloud")
    Unit <- check(Bool.not(Bool.xor(Scenery.cloud_at(4100, 4100), Scenery.cloud_at(4100, 4100))), "a cloud cell is two things")
    Unit <- check(close(Scenery.cloud_drift(0), 0.0), "the clouds have drifted before the first tick")
    check(F32.is_gt(Scenery.cloud_drift(700), Scenery.cloud_cell()), "the clouds have not drifted a cell in 700 ticks")

# A frame with no blocks in it, 128 pixels a side, looking along `way`.
def empty_frame(+way: Voxel.Vec, +clock: U32) -> Array<U32>:
  Voxel.Vec{+x, +y, +z} = way
  Scenery.pixels([], Voxel.Vec{40000.5, 12.0, 40000.5}, F32.atan2(x, F32.neg(z)),
    F32.asin(y), 7n, Paint.QNil{}, 0.0, 0.0, clock)

def pixel(read: Array<U32> & U32) -> U32:
  (frame, cell) = read
  cell

def centre_of(+way: Voxel.Vec, +clock: U32) -> U32:
  pixel(empty_frame(way, clock)[U32.add(U32.mul(64, 128), 64)])

# A camera looking at the sun sees the sun, in the sun's own colour at noon; one looking at
# the moon at midnight sees the moon; and at noon nothing is where the moon would be but sky.
def the_sun_and_the_moon_are_in_the_sky() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(centre_of(Scenery.sun_way(Sky.turn(noon())), noon()), Sky.rgb(255, 252, 232)),
      "a camera looking at the noon sun does not see it")
    Unit <- check(U32.is_eq(centre_of(Voxel.Vec.scale(Scenery.sun_way(Sky.turn(midnight())), F32.neg(1.0)), midnight()),
        Sky.rgb(226, 232, 244)),
      "a camera looking at the midnight moon does not see it")
    check(U32.is_ne(centre_of(Voxel.Vec.scale(Scenery.sun_way(Sky.turn(noon())), F32.neg(1.0)), noon()), Sky.rgb(226, 232, 244)),
      "the moon is in the sky under the world at noon")

# How many pixels of a frame are brighter than a level.
def bright.go(cells: List<&1, U32>, +over: U32, +count: U32) -> U32:
  match cells:
    case Nil{}:
      count
    case +cell <> rest:
      bright.go(rest, over, U32.add(count, Bool.to_u32(U32.is_gt(U32.and(cell, 255), over))))

def bright(frame: Array<U32>, +over: U32) -> U32:
  bright.go(Array.to_list(~U32, frame), over, 0)

def none(quads: Paint.Quads) -> Bool:
  match quads:
    case Paint.QNil{}:
      True{}
    case _:
      False{}

# Straight up at midnight there are stars: a few pixels far brighter than the night's sky and
# not a frame full of them. Straight up at noon, away from the sun, there are none.
def the_stars_are_out_at_night() -> IO(Unit):
  do IO<Unit>:
    +night : U32 = bright(empty_frame(Voxel.Vec{0.05, 0.99, 0.05}, midnight()), 200)
    Unit <- check(U32.is_gt(night, 0), "there are no stars overhead at midnight")
    Unit <- check(U32.is_lt(night, 400), "the night sky is more star than sky")
    check(none(Scenery.stars(Sky.sun_height(noon()), Sky.air_at(noon()), Voxel.Camera.look(Voxel.Vec{0.0, 0.0, 0.0}, 0.0, 0.0),
        64.0, 96.0, 128, Paint.QNil{})),
      "there are stars at noon")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- the_sun_goes_round()
    Unit <- the_sky_is_partly_cloud()
    Unit <- the_sun_and_the_moon_are_in_the_sky()
    Unit <- the_stars_are_out_at_night()
    IO.print("scenery: the sun's path, the clouds, the sun and moon in the frame and the stars passed")
