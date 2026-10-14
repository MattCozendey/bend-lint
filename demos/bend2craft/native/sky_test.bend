import Base
import ./sky.bend as Sky
import ./paint.bend as Paint
import ./texture.bend as Texture

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "sky: " ++ message)

def red(+color: U32) -> U32:
  U32.and(U32.shrn(color, 16n), 255)

def green(+color: U32) -> U32:
  U32.and(U32.shrn(color, 8n), 255)

def blue(+color: U32) -> U32:
  U32.and(color, 255)

def brightness(+color: U32) -> U32:
  U32.add(U32.add(red(color), green(color)), blue(color))

def apart(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_gt(a, b), U32.sub(a, b), U32.sub(b, a))

# Two colours within `most` of each other on every channel.
def near(+a: U32, +b: U32, +most: U32) -> Bool:
  Bool.and(U32.is_le(apart(red(a), red(b)), most),
    Bool.and(U32.is_le(apart(green(a), green(b)), most), U32.is_le(apart(blue(a), blue(b)), most)))

# The air is two colours in one word at five bits a channel, so each comes back within the
# seven a channel loses, and a colour that already fits comes back as itself.
def the_air_is_two_colours() -> IO(Unit):
  do IO<Unit>:
    +air : U32 = Sky.air(Sky.rgb(190, 214, 238), Sky.rgb(72, 132, 222))
    Unit <- check(near(Sky.haze_of(air), Sky.rgb(190, 214, 238), 7), "the horizon's colour did not come back out of the air")
    Unit <- check(near(Sky.zenith_of(air), Sky.rgb(72, 132, 222), 7), "the zenith's colour did not come back out of the air")
    Unit <- check(U32.is_eq(Sky.haze_of(Sky.air(Sky.haze_of(air), 0)), Sky.haze_of(air)),
      "a colour the air already held changed when it was put back")
    check(U32.is_lt(air, 1073741824), "the air does not fit thirty bits")

# A level camera has the horizon across the middle of the frame, looking up puts it lower
# and looking down higher, and it is never the 0 a frame without a horizon passes.
def the_horizon_follows_the_pitch() -> IO(Unit):
  do IO<Unit>:
    +level : U32 = Sky.horizon(0.0, 256.0, 384.0)
    Unit <- check(U32.is_eq(level, U32.add(Sky.bias(), 255)), "a level camera's horizon is not the frame's middle")
    Unit <- check(U32.is_gt(Sky.horizon(0.5, 256.0, 384.0), level), "looking up did not lower the horizon")
    Unit <- check(U32.is_lt(Sky.horizon(F32.neg(0.5), 256.0, 384.0), level), "looking down did not raise the horizon")
    Unit <- check(U32.is_ne(Sky.horizon(F32.neg(1.0), 256.0, 384.0), 0), "a camera looking straight down has no horizon")
    check(U32.is_lt(Sky.horizon(1.0, 256.0, 384.0), 131072), "a camera looking straight up has a horizon past the bias")

# The sky is the air's own colour at the horizon and below it, and nearer the zenith's the
# higher the row.
def the_sky_deepens_upward() -> IO(Unit):
  do IO<Unit>:
    +air : U32 = Sky.day_air()
    +horizon : U32 = Sky.horizon(0.0, 256.0, 384.0)
    Unit <- check(U32.is_eq(Sky.color(horizon, air, 255, 512), Sky.haze_of(air)), "the sky at the horizon is not the air's colour")
    Unit <- check(U32.is_eq(Sky.color(horizon, air, 400, 512), Sky.haze_of(air)), "the sky below the horizon is not the air's colour")
    Unit <- check(U32.is_gt(blue(Sky.color(horizon, air, 0, 512)), red(Sky.color(horizon, air, 0, 512))),
      "the top of the sky is not blue")
    check(U32.is_lt(red(Sky.color(horizon, air, 0, 512)), red(Sky.color(horizon, air, 200, 512))),
      "the sky does not get deeper toward the top")

# Near things are seen as they are, and things past the end of the air are the air's colour.
# `Paint.air_of` reads a depth on the scale `Sky.fog_scale` puts it on.
def the_air_hides_what_is_far() -> IO(Unit):
  do IO<Unit>:
    +stone : U32 = 8
    Unit <- check(U32.is_eq(Paint.air_of(stone, F32.mul(4.0, Sky.fog_scale())), 0), "a block four cells away is seen through air")
    Unit <- check(U32.is_eq(Paint.air_of(stone, F32.mul(Sky.fog_end(), Sky.fog_scale())), 256),
      "a block at the end of the air is not hidden by it")
    Unit <- check(U32.is_gt(Paint.air_of(stone, F32.mul(40.0, Sky.fog_scale())), Paint.air_of(stone, F32.mul(30.0, Sky.fog_scale()))),
      "the air does not thicken with distance")
    Unit <- check(U32.is_eq(Sky.hazed(123456, 0, 654321), 123456), "a colour seen through no air changed")
    check(near(Sky.hazed(Sky.rgb(10, 200, 30), 256, Sky.rgb(190, 214, 238)), Sky.rgb(190, 214, 238), 1),
      "a colour seen through all the air is not the air's colour")

# The top of water takes the sky sooner than a block does, and its sides do not.
def water_takes_the_sky() -> IO(Unit):
  do IO<Unit>:
    +depth : F32 = F32.mul(8.0, Sky.fog_scale())
    Unit <- check(U32.is_gt(Paint.air_of(57, depth), 0), "the top of water eight cells away shows no sky")
    Unit <- check(U32.is_eq(Paint.air_of(56, depth), 0), "the side of water takes the sky")
    check(U32.is_le(Paint.air_of(57, F32.mul(20.0, Sky.fog_scale())), 256), "water took more than all the sky")

# A face's light: every corner full at full day is the texel itself, a dark corner darkens
# the texels near it and leaves the far ones, and a dim hour darkens every texel.
def corners_and_the_hour_darken_a_texel() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(Texture.texel_lit(1, 1, 3, 9, 0, Sky.full_level()), Texture.texel(1, 1, 3, 9)),
      "a fully lit texel at full day is not the texel")
    Unit <- check(U32.is_eq(Texture.corner_light(0, 7, 7), 256), "a face with every corner lit is not at full light")
    Unit <- check(U32.is_lt(Texture.corner_light(15, 0, 0), Texture.corner_light(15, 15, 15)),
      "a dark corner does not darken the texels near it more than the far ones")
    Unit <- check(U32.is_gt(Texture.corner_light(65535, 7, 7), 60), "a face with every corner dark is black")
    Unit <- check(U32.is_lt(brightness(Texture.texel_lit(6, 1, 4, 4, 15, Sky.full_level())), brightness(Texture.texel(6, 1, 4, 4))),
      "a texel by a dark corner is not darker")
    check(U32.is_lt(brightness(Texture.texel_lit(6, 1, 4, 4, 0, 8)), brightness(Texture.texel(6, 1, 4, 4))),
      "a texel at night is not darker")

# The hour: all of the day's light at noon and none at midnight, sunset's colour only with
# the sun near the horizon, and the same air a whole day later.
def the_hour_sets_the_light() -> IO(Unit):
  do IO<Unit>:
    +noon : U32 = 10800
    +sunset : U32 = 21600
    +midnight : U32 = 32400
    Unit <- check(U32.is_eq(Sky.daylight(Sky.sun_height(noon)), 256), "noon does not have all the day's light")
    Unit <- check(U32.is_eq(Sky.daylight(Sky.sun_height(midnight)), 0), "midnight has daylight")
    Unit <- check(U32.is_eq(Sky.level_at(noon), Sky.full_level()), "noon is not at the full level")
    Unit <- check(U32.is_eq(Sky.level_at(midnight), 8), "midnight is not at the night's level")
    Unit <- check(U32.is_eq(Sky.level_light(Sky.full_level()), 256), "the full level is not a factor of one")
    Unit <- check(U32.is_gt(Sky.dusk(Sky.sun_height(sunset)), 200), "sunset has no sunset in it")
    Unit <- check(U32.is_eq(Sky.dusk(Sky.sun_height(noon)), 0), "noon has sunset in it")
    Unit <- check(U32.is_gt(red(Sky.haze_of(Sky.air_at(sunset))), blue(Sky.haze_of(Sky.air_at(sunset)))),
      "the horizon at sunset is not warm")
    Unit <- check(U32.is_lt(brightness(Sky.haze_of(Sky.air_at(midnight))), 150), "the night's air is not dark")
    Unit <- check(U32.is_eq(Sky.air_at(noon), Sky.air_at(U32.add(noon, Sky.day_ticks()))), "the air a day later is not the same air")
    check(U32.is_eq(Sky.level_at(Sky.clock_start()), Sky.full_level()), "a session does not start in full daylight")

def about(+a: U32, +b: U32) -> Bool:
  Bool.and(U32.is_le(a, U32.add(b, 20)), U32.is_le(b, U32.add(a, 20)))

# A room says how far round its day it is, as an angle in thousandths of a radian, and how
# long its day is. The angle is the clock a quarter turn is noon on, and the clock after a
# while is that many days' worth further on, however long the while.
def a_room_sets_the_hour() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(Sky.clock_of_turn(0), 0), "no turn is not sunrise")
    Unit <- check(about(Sky.clock_of_turn(1571), 10800), "a quarter turn is not noon")
    Unit <- check(about(Sky.clock_of_turn(4712), 32400), "three quarters of a turn is not midnight")
    Unit <- check(U32.is_lt(Sky.clock_of_turn(6283), Sky.day_ticks()), "a whole turn is past the day")
    Unit <- check(U32.is_eq(Sky.clock_after(100, 0, 78540), 100), "no time moved the clock")
    Unit <- check(about(Sky.clock_after(0, 19635, 78540), 10800), "a quarter of the room's day is not a quarter of the clock's")
    Unit <- check(about(U32.mod(Sky.clock_after(100, 78540, 78540), Sky.day_ticks()), 100), "a whole day later is not the same hour")
    check(about(Sky.clock_after(0, 805035, 78540), 10800), "ten days and a quarter later is not noon")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- the_air_is_two_colours()
    Unit <- the_horizon_follows_the_pitch()
    Unit <- the_sky_deepens_upward()
    Unit <- the_air_hides_what_is_far()
    Unit <- water_takes_the_sky()
    Unit <- corners_and_the_hour_darken_a_texel()
    Unit <- the_hour_sets_the_light()
    Unit <- a_room_sets_the_hour()
    IO.print("sky: the air, the horizon, the gradient, the fog, water, corner light, the hour and a room's hour passed")
