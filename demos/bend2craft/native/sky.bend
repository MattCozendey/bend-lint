import Base

# The sky, the air between the eye and what it sees, and the hour.
#
# The sky and the air are one colour rule so that they meet: the air far away takes the
# colour the sky has at the horizon, and a hill at the edge of what is drawn fades into the
# sky behind it instead of ending against it.
#
# The sky is a gradient over the **view**, not over the screen: it is pale at the horizon and
# deep overhead, and the horizon is wherever the camera's pitch puts it. A row of the frame
# is one elevation to within the frame's own curvature, so the colour is a rule on the row
# and the row the horizon is on, in whole numbers, and a region of sky is still one colour
# per row.
#
# The hour changes both. A frame is painted under one `air`: the horizon's colour and the
# zenith's as one word, worked out once from the clock, so a pixel never asks what time it
# is.

def rgb(+r: U32, +g: U32, +b: U32) -> U32:
  U32.or(U32.shln(r, 16n), U32.or(U32.shln(g, 8n), b))

# `a` moved toward `b` by `t` over 256, each channel on its own.
def mix(+a: U32, +b: U32, +t: U32) -> U32:
  +s = U32.sub(256, t)
  +r = U32.shrn(U32.add(U32.mul(U32.and(U32.shrn(a, 16n), 255), s), U32.mul(U32.and(U32.shrn(b, 16n), 255), t)), 8n)
  +g = U32.shrn(U32.add(U32.mul(U32.and(U32.shrn(a, 8n), 255), s), U32.mul(U32.and(U32.shrn(b, 8n), 255), t)), 8n)
  +c = U32.shrn(U32.add(U32.mul(U32.and(a, 255), s), U32.mul(U32.and(b, 255), t)), 8n)
  U32.or(U32.shln(r, 16n), U32.or(U32.shln(g, 8n), c))

# --- the air as one word -------------------------------------------------------------
#
# Two colours, five bits a channel: the horizon's in the low fifteen bits and the zenith's in
# the next fifteen. Five bits is coarse for a picture and fine for the two ends of a
# gradient, because every colour between them is mixed at full depth.

def narrow(+color: U32) -> U32:
  U32.or(U32.shln(U32.shrn(U32.and(U32.shrn(color, 16n), 255), 3n), 10n),
    U32.or(U32.shln(U32.shrn(U32.and(U32.shrn(color, 8n), 255), 3n), 5n),
      U32.shrn(U32.and(color, 255), 3n)))

def wide.channel(+five: U32) -> U32:
  U32.or(U32.shln(five, 3n), U32.shrn(five, 2n))

def wide(+packed: U32) -> U32:
  rgb(wide.channel(U32.and(U32.shrn(packed, 10n), 31)), wide.channel(U32.and(U32.shrn(packed, 5n), 31)),
    wide.channel(U32.and(packed, 31)))

def air(+haze: U32, +zenith: U32) -> U32:
  U32.or(narrow(haze), U32.shln(narrow(zenith), 15n))

# The colour of the sky at the horizon, and of air thick enough to hide what is behind it.
def haze_of(+air: U32) -> U32:
  wide(U32.and(air, 32767))

# The colour of the sky overhead.
def zenith_of(+air: U32) -> U32:
  wide(U32.and(U32.shrn(air, 15n), 32767))

# --- the horizon -------------------------------------------------------------------

# Rows are counted from this, so a horizon above the frame's top is still a number.
def bias() -> U32:
  65536

# The row the horizon is on, plus `bias()`, for a camera whose forward vector rises by
# `forward_y`: the frame's middle when the view is level, lower as the camera looks up. It
# is held inside the bias on both sides, so a camera looking straight up or down is a
# horizon far off the frame and not a number that wrapped. It is never 0, which is what a
# frame with no horizon passes.
def horizon(+forward_y: F32, +half: F32, +focal: F32) -> U32:
  +level = F32.sqrt(F32.max(F32.sub(1.0, F32.mul(forward_y, forward_y)), 0.000001))
  +row = F32.add(F32.sub(half, 0.5), F32.div(F32.mul(focal, forward_y), level))
  F32.to_u32(F32.min(F32.max(F32.add(row, 65536.0), 1.0), 131071.0))

# How far up the sky a row is, over 256: 0 at the horizon and below it, and rising slowly at
# first, so the band above the horizon is the air's own colour. A hill at the far end of the
# air is painted in that colour, and against a band of it the hill is not an outline: it is
# only where the sky gets deeper, well above anything the world builds, that the blue starts.
def height(+horizon: U32, +row: U32, +size: U32) -> U32:
  +at = U32.add(row, bias())
  +above = Bool.pick(U32, U32.is_gt(horizon, at), U32.sub(horizon, at), 0)
  +linear = U32.min(U32.div(U32.mul(above, 460), size), 256)
  U32.shrn(U32.mul(linear, linear), 8n)

# The sky's colour on a row of a frame `size` rows tall whose horizon is at `horizon`.
def color(+horizon: U32, +air: U32, +row: U32, +size: U32) -> U32:
  mix(haze_of(air), zenith_of(air), height(horizon, row, size))

# --- the air between -----------------------------------------------------------------

# Where the air starts to show, and where it hides everything, in cells from the eye. The
# view region is five chunks by five with the player in the middle one, so its edge is
# between 28 and 52 cells away along an axis: the air is already a quarter of the picture at
# the nearest the edge can be and all of it before the far corners.
def fog_start() -> F32:
  22.0

def fog_end() -> F32:
  58.0

# How much air a depth is, over 256, as two numbers a pixel can use with one division: the
# amount is `scale * depth - floor`, held between 0 and 256.
def fog_scale() -> F32:
  F32.div(256.0, F32.sub(fog_end(), fog_start()))

def fog_floor() -> F32:
  F32.mul(fog_start(), fog_scale())

# The square of how far a block can be and still be seen: the end of the air, and a block's
# own reach past it.
def fog_reach() -> F32:
  F32.mul(F32.add(fog_end(), 1.0), F32.add(fog_end(), 1.0))

def hazed.at(clear: Bool, +color: U32, +amount: U32, haze: U32) -> U32:
  match clear:
    case True{}:
      color
    case False{}:
      mix(color, haze, amount)

# A colour seen through `amount` of air over 256, the air being `haze`. Near things are seen
# through none, and those are most of a frame, so that case does no arithmetic.
def hazed(+color: U32, +amount: U32, haze: U32) -> U32:
  hazed.at(U32.is_eq(amount, 0), color, amount, haze)

# How fast the top of water takes the sky with depth, on the scale `fog_scale` puts a depth
# on, and the most it takes: a little over half, so water far off is still water.
def water_sheen() -> F32:
  0.55

def water_sheen_most() -> F32:
  150.0

# --- the hour ----------------------------------------------------------------------
#
# The clock counts ticks, sixty a second. A day is twelve minutes of them: the sun comes up
# at tick 0 of a day, is highest a quarter of the way through, sets at the half and is
# lowest at three quarters. Everything below is a rule on how high the sun is.

def day_ticks() -> U32:
  43200

# The client's first tick: mid-morning, with the whole day ahead.
def clock_start() -> U32:
  4800

# How far round the day the clock is, as an angle: 0 at sunrise, a quarter turn at noon.
def turn(+clock: U32) -> F32:
  F32.div(F32.mul(U32.to_f32(U32.mod(clock, day_ticks())), 6.2831853), U32.to_f32(day_ticks()))

# How high the sun is: 1 overhead, 0 on the horizon, negative below it.
def sun_height(+clock: U32) -> F32:
  F32.sin(turn(clock))

# --- a room's hour -------------------------------------------------------------------
#
# A multiplayer room has a clock of its own, and its day is not twelve minutes. It says how
# far round its day it is, as an angle in thousandths of a radian from the morning the day
# starts on, and how long a day lasts in milliseconds (`server/native-bridge.mjs`, from
# `web/daylight.js`). Both become this clock, on which a quarter of a day is noon, so a
# room's noon is noon in the frame.

def clock_of_turn(+milli: U32) -> U32:
  U32.mod(F32.to_u32(F32.div(F32.mul(U32.to_f32(milli), U32.to_f32(day_ticks())), 6283.1853)),
    day_ticks())

# The clock `elapsed` milliseconds after it read `start`, in a room whose day is `length`
# milliseconds. Whole days are dropped first, so a long while is not a large number.
def clock_after(+start: U32, +elapsed: U32, +length: U32) -> U32:
  U32.add(start, F32.to_u32(F32.div(F32.mul(U32.to_f32(U32.mod(elapsed, length)),
    U32.to_f32(day_ticks())), U32.to_f32(length))))

def eased(+t: F32) -> F32:
  F32.mul(F32.mul(t, t), F32.sub(3.0, F32.mul(2.0, t)))

def between(+value: F32, +low: F32, +high: F32) -> F32:
  F32.min(F32.max(F32.div(F32.sub(value, low), F32.sub(high, low)), 0.0), 1.0)

# How much of the day's light there is, over 256: all of it once the sun is a little up,
# none once it is a little down, and a smooth slide between.
def daylight(+height: F32) -> U32:
  F32.to_u32(F32.mul(eased(between(height, F32.neg(0.14), 0.24)), 256.0))

# How much of sunrise or sunset there is, over 256: the most with the sun on the horizon and
# none once it is well clear of it either way.
def dusk(+height: F32) -> U32:
  F32.to_u32(F32.mul(eased(F32.sub(1.0, between(F32.abs(height), 0.0, 0.32))), 256.0))

def day_haze() -> U32:
  rgb(190, 214, 238)

def day_zenith() -> U32:
  rgb(72, 132, 222)

def night_haze() -> U32:
  rgb(18, 24, 46)

def night_zenith() -> U32:
  rgb(6, 9, 24)

def dusk_haze() -> U32:
  rgb(244, 156, 96)

def dusk_zenith() -> U32:
  rgb(74, 84, 150)

# The air at a sun height: night's colours moved to the day's by the daylight, and both
# toward sunset's by the dusk, the horizon much more than the zenith.
def air_under(+height: F32) -> U32:
  air(mix(mix(night_haze(), day_haze(), daylight(height)), dusk_haze(), U32.shrn(U32.mul(dusk(height), 200), 8n)),
    mix(mix(night_zenith(), day_zenith(), daylight(height)), dusk_zenith(), U32.shrn(U32.mul(dusk(height), 110), 8n)))

def air_at(+clock: U32) -> U32:
  air_under(sun_height(clock))

# The air of full day, which is what a frame with no clock is painted under.
def day_air() -> U32:
  air(day_haze(), day_zenith())

# How bright the world's own colours are, 0 to 31: 31 by day and never under 8, so a night
# is dark and still a place a player can see across.
def level_under(+height: F32) -> U32:
  U32.add(8, U32.shrn(U32.mul(daylight(height), 23), 8n))

def level_at(+clock: U32) -> U32:
  level_under(sun_height(clock))

def full_level() -> U32:
  31

# A level as a factor over 256: 31 is 256, which leaves a colour as it is.
def level_light(+level: U32) -> U32:
  U32.mul(U32.add(level, 1), 8)
