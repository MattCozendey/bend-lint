import Base
import ../world/player.bend as Player
import ../world/world.bend as World
import ../world/world_state.bend as WorldState
import ./voxel.bend as Voxel
import ./player.bend as PlayerProbe

# One frame of a native client, as data. `player` is the state the next tick
# reads, `pose` is the camera basis this frame was drawn from, `digest` is the
# fingerprint of what was shown and `rendered` says whether this tick paid for a
# draw. The record is affine: a frame is consumed once, by the next frame.
type Frame is Data:
  Frame{player: Player.State, pose: Pose, digest: U32, rendered: Bool}

# The camera basis, expressed in the render chunk's own cells. The player state
# counts domain cells and the render grid is one chunk, so the eye is rebased
# before it can index anything.

type Pose is Data:
  Pose{eye: Voxel.Vec, yaw: F32, pitch: F32}

# The tick's events folded into what `Player.step` reads: the held-key mask and
# the two look deltas.

type Keys is Data:
  Keys{keys: U32, turn: F32, tilt: F32}

# Input and the player transition applied, before the frame decides whether it
# has to draw. A frame that skips the render still answers one of these.

type Staged is Data:
  Staged{player: Player.State, pose: Pose, changed: Bool}

# Where the player is created and where `Player.step` respawns it. The region is
# anchored at its minimum chunk, so the spawn has to sit one chunk inside it.

type Spawn is Data:
  Spawn{x: Nat, z: Nat, height: Nat}

def seed() -> Nat:
  1337n

def chunk_x() -> Nat:
  1n

def chunk_z() -> Nat:
  1n

# Two chunks per axis, so the player has a seam to cross and the collision
# probes walk the longer region list `Player.region_block` really has. The bound
# `PlayerProbe.grid_is_sound` allows is sixteen chunks in total; this is four.

def columns() -> Nat:
  2n

def rows() -> Nat:
  2n

# The view region: the chunks the renderer reads and the player collides with.
#
# It is five chunks per axis, and it **follows the player**. `Home` is its first chunk, and
# the region is the twenty-five chunks from there. It starts two chunks before `chunk_x`,
# the chunk the pose is counted from, so the chunk the player spawns in is the middle one
# and there are two chunks of world on every side of it.
#
# `Home` is in **window chunks**: chunks of the player's own movement window, which counts
# from 32768 cells before the world's origin (`PlayerProbe.window_origin_chunk` is world
# chunk 0). A window chunk is a plain number on both sides of the origin, so the region can
# follow the player west and north of it. Storage spells a chunk before the origin from
# `World.negative_origin` instead, and `PlayerProbe.stored_chunk` is the one place a window
# chunk becomes that spelling.
#
# The view was one chunk while the ray walk drew the window, because a two-by-two region
# cost 19.10 ms a frame there. The painter's cost per face is small enough that the region
# is no longer what the frame is spent on; `lab/native/paint/README.md` has the numbers.
type Home is Data:
  Home{x: Nat, z: Nat}

# The view region is five chunks by five, eighty cells a side, with the player in the middle
# chunk: there are at least thirty-two cells of world in every direction, which is as far as
# the air lets a player see (`native/sky.bend`). It was three by three, and the world ended
# sixteen cells away.
def view_columns() -> Nat:
  5n

def view_rows() -> Nat:
  5n

# How many chunks come before the middle one, on either axis.
def view_middle() -> Nat:
  Nat.div(view_columns(), 2n)

# The region at the start: the spawn chunk is world chunk 1, and it is the middle one.
def home_start() -> Home:
  Home{Nat.sub(Nat.add(PlayerProbe.window_origin_chunk(), 1n), view_middle()),
    Nat.sub(Nat.add(PlayerProbe.window_origin_chunk(), 1n), view_middle())}

def home_x(home: Home) -> Nat:
  Home{x, z} = home
  x

def home_z(home: Home) -> Nat:
  Home{x, z} = home
  z

def same_home(a: Home, b: Home) -> Bool:
  Home{ax, az} = a
  Home{bx, bz} = b
  Bool.and(Nat.is_eq(ax, bx), Nat.is_eq(az, bz))

# How far past the middle chunk's edge the player walks before the region moves. Without
# it a player standing on a chunk boundary would move the region on every step back and
# forth across it, and moving the region rebuilds it.
def home_margin() -> Nat:
  4n

# The region's first window chunk on one axis, for a player in window cell `cell`. While
# the player is inside the middle chunk, or within the margin of it, the region stays where
# it is; past that it moves so the player's chunk is the middle one again.
def home_axis(+origin: Nat, +cell: Nat) -> Nat:
  +size = World.chunk_size()
  +low = Nat.mul(size, Nat.add(origin, view_middle()))
  +high = Nat.mul(size, Nat.add(Nat.add(origin, view_middle()), 1n))
  Bool.pick(Nat, Bool.and(Nat.is_ge(Nat.add(cell, home_margin()), low),
      Nat.is_lt(cell, Nat.add(high, home_margin()))),
    origin, Nat.sub(Nat.div(cell, size), view_middle()))

# The collision region's first window chunk on one axis. It is two chunks per axis, not
# three: the player only collides with, and reaches, what is within a few cells, and a
# region rebuilt in half the time is a shorter frame every time a block is dug. It is placed
# so the player is at least six cells inside it on every side: it stays while the player is
# between the sixth and the twenty-sixth of its thirty-two cells, and past that it moves so
# the player is in its middle sixteen again.
def den_axis(+origin: Nat, +cell: Nat) -> Nat:
  +size = World.chunk_size()
  +low = Nat.mul(size, origin)
  Bool.pick(Nat, Bool.and(Nat.is_ge(cell, Nat.add(low, 6n)), Nat.is_lt(cell, Nat.add(low, 26n))),
    origin, Nat.div(Nat.sub(cell, 8n), size))

# A player coordinate as the window cell it is in. The player's own coordinates are
# already in the window.
def window_cell_of(+coordinate: F32) -> Nat:
  U32.to_nat(F32.to_u32(F32.floor(F32.max(coordinate, 0.0))))

def home_at(home: Home, +x: F32, +z: F32) -> Home:
  Home{hx, hz} = home
  Home{home_axis(hx, window_cell_of(x)), home_axis(hz, window_cell_of(z))}

def den_at(den: Home, +x: F32, +z: F32) -> Home:
  Home{dx, dz} = den
  Home{den_axis(dx, window_cell_of(x)), den_axis(dz, window_cell_of(z))}

# `den` is the collision region's first chunk, as `Home` is the view region's.
def den_for(den: Home, player: Player.State) -> Home:
  Player.State{x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall,
    poison} = player
  den_at(den, x, z)

def home_for(home: Home, player: Player.State) -> Home:
  Player.State{x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall,
    poison} = player
  home_at(home, x, z)

# The eye in the view region's own cells. The pose counts the eye from `origin` — the
# window cell of chunk (`chunk_x`, `chunk_z`) — and the region starts at `home`, so the
# difference between the two, in cells, is what the renderer adds. It is signed: a region
# that has followed the player past the pose's chunk starts after it.
def view_shift(+origin: Nat, +home_chunk: Nat) -> F32:
  F32.sub(F32.from_nat(origin), F32.from_nat(Nat.mul(home_chunk, World.chunk_size())))

def spawn() -> Spawn:
  Spawn{25n, 25n, 9n}

# One tick is 1/60 s of held input, the same dt `native/player-probe` measured.

def tick_dt() -> F32:
  0.016

# The distance from the player's feet to the camera. `Player.State` is the body
# and carries no eye, so the eye belongs to the adapter that turns a player into
# a camera, and it lives here.

def eye_height() -> F32:
  1.62

# Just under a quarter turn, so no look event can flip the camera over.

def pitch_limit() -> F32:
  1.5533

# Radians of turn per pixel of pointer movement.
#
# The value is chosen against the field of view: `projection_half` with `focal = 1.5 * half`
# puts the horizontal field of view near 67 degrees, so 0.0012 turns 35 degrees per 512
# pixels of mouse travel.
def look_sensitivity() -> F32:
  0.0012

# --- looking by key ------------------------------------------------------------
#
# The arrow keys turn the camera too, and they are the look that needs nothing from the
# pointer: not the runtime's grab, not the host script `native/pointer.bend` starts under
# WSL. They were the only look that reached the client under WSLg while the pointer was read
# from the display, which delivers no relative motion there.
#
# The keys are the runtime's own translation of the arrow keysyms (`window.c:507`), not raw
# X keycodes: 63232 up, 63233 down, 63234 left, 63235 right. Those four are stable across
# keyboard layouts in a way a hardware keycode is not, and the runtime is what chose them.
#
# Turning is a **rate**, not a per-press jump, so holding a key sweeps at a constant pace
# and a tap moves a little. 1.6 rad/s is 92 degrees a second — a full sweep of the 67-degree
# field of view in about two thirds of a second, which is the pace a held key needs to feel
# like a held key. Pitch is half that, because a sweep of the horizon is a much larger change
# to where you are looking than the same angle of yaw.
def turn_rate() -> F32:
  1.6

def tilt_rate() -> F32:
  0.8

def arrow_up() -> U32:
  63232

def arrow_down() -> U32:
  63233

def arrow_left() -> U32:
  63234

def arrow_right() -> U32:
  63235

# Signed contribution of one axis, in radians per second: `+1` when the positive key is held,
# `-1` when the negative one is, and `0` for both or neither. Both or neither is `0` rather
# than a sum, because a player who rolls their fingers onto left and right means "hold still",
# and a sum would leave them drifting.
# Both held is `0` and not a sum: `1.6 + 1.6` would be 3.2 radians a second, a spin, when
# what a player rolling both fingers onto Left and Right means is hold still.
def axis_one(both: Bool, positive: Bool, negative: Bool) -> F32:
  Bool.pick(F32, both, 0.0, Bool.pick(F32, positive, 1.0,
    Bool.pick(F32, negative, F32.neg(1.0), 0.0)))

def axis_way(+negative: Bool, +positive: Bool) -> F32:
  axis_one(Bool.and(negative, positive), positive, negative)

def axis.at(way: F32, +rate: F32) -> F32:
  F32.mul(way, rate)

def axis(negative: Bool, positive: Bool, +rate: F32) -> F32:
  axis.at(axis_way(negative, positive), rate)

def held(keys: U32, +code: U32) -> Bool:
  U32.is_eq(U32.and(keys, code), code)

# `Player.step` reads these masks through `Player.held`, so the fold below maps a
# key code onto the bit the player transition tests rather than onto a key name.
#
# The bit numbers are a contract with `world/player.bend`, not a local choice: the strafe is
# `input_axis(held(keys, 8), held(keys, 2))`, so 8 is the positive strafe, which is the
# player's right at yaw 0 where forward is -z. `web/game-state.js:326` spells the same two
# keys the same way round. The first version of this table had A on 8 and D on 2, which is
# a strafe that goes left when the player presses right -- noticed by playing, not by a test.
# A code that is not in the table reads as 0, which is "no key held", so every key
# a client reacts to has to be in the table: the dig, place, save and quit keys are
# read from the same mask as the movement keys, and a code missing from here would
# read as always down.

#
# Control and Shift arrive as the runtime's own codes for them (`window.c:511`: 65595 and
# 65598 for the two Controls, 65592 and 65596 for the two Shifts), not as 17 and 16. They
# hold the sprint bit and the sneak bit, as in the game this one is modelled on, and a
# screen reads the sneak bit as Shift.
def shift_bit() -> U32:
  64

# The keys the client acts on, by the runtime's own codes. `F` digs from the keyboard and the
# left button digs from the mouse; `R` places and so does the right button; `T` saves; `E` is
# the inventory's key (`Screen.key`), as in the game this one is modelled on.
def dig_code() -> U32:
  102

def place_code() -> U32:
  114

def save_code() -> U32:
  116

def escape_code() -> U32:
  27

# The diagnostics overlay's key, F3, as the runtime's own code for it.
#
# Not X11's keysym for F3 (0xFFC0, 65472): the runtime never hands that on. Its
# `window_key` translates the function keys itself, `63236 + (ks - XK_F1)`, so F1 is 63236
# and F3 is 63238 - and the macOS path lands on the same numbers through the function
# key's character. The four arrow codes above come from the same table. This number was
# read out of `vendor/bend/bend2/effs/window.c` rather than guessed: a keysym that never
# arrives is a key that does nothing and reports no error, which is the worst kind of
# wrong.
def debug_code() -> U32:
  63238

def key_bit(+code: U32) -> U32:
  Bool.pick(U32, U32.is_eq(code, 119), 1,
    Bool.pick(U32, U32.is_eq(code, 115), 4,
      Bool.pick(U32, U32.is_eq(code, 97), 2,
        Bool.pick(U32, U32.is_eq(code, 100), 8,
          Bool.pick(U32, U32.is_eq(code, 32), 16,
            Bool.pick(U32, U32.is_eq(code, 16), 32,
              Bool.pick(U32, U32.is_eq(code, 17), 64,
                Bool.pick(U32, U32.is_eq(code, escape_code()), 128,
                  Bool.pick(U32, U32.is_eq(code, 101), 256,
                    Bool.pick(U32, U32.is_eq(code, place_code()), 512,
                      Bool.pick(U32, U32.is_eq(code, save_code()), 1024,
                        Bool.pick(U32, U32.is_eq(code, arrow_up()), 2048,
                          Bool.pick(U32, U32.is_eq(code, arrow_down()), 4096,
                            Bool.pick(U32, U32.is_eq(code, arrow_left()), 8192,
                              Bool.pick(U32, U32.is_eq(code, arrow_right()), 16384,
                                Bool.pick(U32, U32.is_eq(code, dig_code()), 131072,
                                  Bool.pick(U32, U32.is_eq(code, debug_code()), 262144,
                                    Bool.pick(U32, Bool.or(U32.is_eq(code, 65595), U32.is_eq(code, 65598)), 32,
                                      Bool.pick(U32, Bool.or(U32.is_eq(code, 65592), U32.is_eq(code, 65596)), 64,
                                        0)))))))))))))))))))

def key_turn(+keys: U32) -> F32:
  axis(held(keys, key_bit(arrow_left())), held(keys, key_bit(arrow_right())), turn_rate())

# The pitch sign is the mouse's, not a guess: the mouse reports y growing downward and a
# downward pitch must spend, so the Down arrow — which points the view down — is the negative
# key. This is the convention `fold_tilt` states, measured against the picture.
def key_tilt(+keys: U32) -> F32:
  axis(held(keys, key_bit(arrow_down())), held(keys, key_bit(arrow_up())), tilt_rate())

# The turn a key look adds over a tick: the rate scaled by the tick's own length, so the
# sweep is the same number of degrees per second whether the frame took 8 ms or 16 ms. It is
# applied to the yaw the fold produced rather than folded in beside it, because the fold sums
# per-event deltas and a rate is not a delta.
def key_look_turn(+keys: U32, +dt: F32) -> F32:
  F32.mul(key_turn(keys), dt)

def key_look_tilt(+keys: U32, +dt: F32) -> F32:
  F32.mul(key_tilt(keys), dt)

def key_set(+keys: U32, +code: U32, down: Bool) -> U32:
  +bit = key_bit(code)
  +cleared = U32.and(keys, U32.xor(keys, bit))
  Bool.pick(U32, down, U32.or(cleared, bit), cleared)

# A `match` may only scrutinize a parameter or a field, and `event` is a list
# binder, so each event is routed by a def that receives it as its parameter.

# The mouse buttons are two more held keys, on bits of their own. The runtime numbers them
# 0 for the left, 1 for the right and 2 for the middle (`window.c:569`), and the middle does
# nothing. Being bits of the mask is what makes a button an edge like a key: the client
# digs on the press and not on every frame the button is held.
#
# They used to share the bits of `E` and `R`. `E` now opens the inventory, as in the game
# this one is modelled on, so the left button has to be told from it: the left button digs
# and clicks, `F` digs from the keyboard, and the right button and `R` both place.
def left_bit() -> U32:
  32768

def right_bit() -> U32:
  65536

# An edge, not a level: a held key must not dig sixty times a second. A key is down now and
# was up in the previous tick's mask, which is the only thing an edge means. Testing the bit
# against the previous mask is what makes this work for every key code rather than only the
# first one.
def edge(keys: U32, previous: U32, +bit: U32) -> Bool:
  down = U32.is_eq(U32.and(bit, keys), bit)
  was_down = U32.is_eq(U32.and(bit, previous), 0)
  Bool.and(down, was_down)

def wants_dig(+previous: U32, +keys: U32) -> Bool:
  Bool.or(edge(keys, previous, key_bit(dig_code())), edge(keys, previous, left_bit()))

def wants_place(+previous: U32, +keys: U32) -> Bool:
  Bool.or(edge(keys, previous, key_bit(place_code())), edge(keys, previous, right_bit()))

def wants_save(previous: U32, keys: U32) -> Bool:
  edge(keys, previous, key_bit(save_code()))

# The diagnostics overlay is a toggle, so it reads as an edge like every other key: a held
# F3 would otherwise flip it sixty times a second.
def wants_debug(previous: U32, keys: U32) -> Bool:
  edge(keys, previous, key_bit(debug_code()))

# Escape asks to leave; the window manager's own close is noticed while the events are shared
# and quits just the same.
#
# Escape is read as the press it is, and not while the inventory screen is open: there it
# closes the screen, and a key still held on the tick after must not then close the client.
def quitting_from(closing: Bool, previous: U32, keys: U32, screen: Bool) -> Bool:
  Bool.or(closing, Bool.and(Bool.not(screen), edge(keys, previous, key_bit(escape_code()))))

# Whether the dig button is down: the left button or the dig key, as a level.
def digging(+mask: U32) -> Bool:
  Bool.or(U32.is_eq(U32.and(mask, left_bit()), left_bit()),
    U32.is_eq(U32.and(mask, key_bit(dig_code())), key_bit(dig_code())))

def button_bit(+button: U32) -> U32:
  Bool.pick(U32, U32.is_eq(button, 0), left_bit(),
    Bool.pick(U32, U32.is_eq(button, 1), right_bit(), 0))

def button_set(+keys: U32, +button: U32, down: Bool) -> U32:
  +bit = button_bit(button)
  +cleared = U32.and(keys, U32.xor(keys, bit))
  Bool.pick(U32, down, U32.or(cleared, bit), cleared)

def fold_keys(event: Event, +keys: U32) -> U32:
  match event:
    case Key{code, down}:
      key_set(keys, code, down)
    case Mouse{x, y, button, down}:
      button_set(keys, button, down)
    case _:
      keys

# A `Look` is this frame's pointer movement, in pixels.
#
# `window.c:591` pushes `Look{x - cx, y - cy}` and `window.c:594` warps the pointer back to
# the centre, so on a display where the warp works the event is a delta, and
# `lab/native/pointer/census-xvfb.sh` measures that it is: eight relative steps of ten pixels
# arrive as eight `Look{10 0}`. Under WSLg the display delivers no relative motion at all, so
# `native/pointer.bend` takes the delta from the Windows host instead and hands it to this
# fold as the same event. Either way the fold sums deltas and never differences them.
#
# A `Move` is the ungrabbed pointer's position and is not read: a position is not a movement.
def fold_turn(event: Event, +turn: F32) -> F32:
  match event:
    case Look{dx, dy}:
      F32.add(turn, F32.mul(dx, look_sensitivity()))
    case _:
      turn

# Spent rather than added: the runtime reports y growing downward, so the mouse travelling
# down arrives with a positive dy, and the pitch is positive up — `Player.direction` and
# `Camera.look` both put `sin(pitch)` in the forward y. That convention is measured rather than
# assumed: rendering the spawn scene from one eye at pitch +1 gives 16311 sky pixels and at
# pitch -1 gives 8, so positive pitch is up in the picture.
def fold_tilt(event: Event, +tilt: F32) -> F32:
  match event:
    case Look{dx, dy}:
      F32.sub(tilt, F32.mul(dy, look_sensitivity()))
    case _:
      tilt

def input.go(events: List<&2, Event>, +keys: U32, +turn: F32, +tilt: F32) -> Keys:
  match events:
    case Nil{}:
      Keys{keys, turn, tilt}
    case +event <> rest:
      input.go(rest, fold_keys(event, keys), fold_turn(event, turn), fold_tilt(event, tilt))

# The input stage: one tick's events into the held-key mask and the two look
# deltas, seeded with the mask the player already holds.
#
# The mask is a level and not a per-frame reading, which is what the seed is for.
# `Window.frame` hands a tick only the events that arrived during that frame, so a
# frame carrying no key event is the ordinary frame of a key the player is still
# holding down. Folding those frames from zero makes the mask a function of
# X11's auto-repeat rather than of the loop: a delay before the first step, one step
# per repeat instead of one per tick, and a diagonal that breaks up because the two
# repeats rarely land in the same frame.
#
# The look deltas do not carry a seed, for the opposite reason. A `Look` is already this
# frame's movement, so summing it into the previous frame's would turn one flick into a
# drift.
def input_from(events: List<&2, Event>, held: U32) -> Keys:
  input.go(events, held, 0.0, 0.0)

# The fold with nothing held, which is the state before the first key event and what
# a headless reader wants: this frame's events and no memory of an earlier one.
def input(events: List<&2, Event>) -> Keys:
  input_from(events, 0)

# A `match` may not scrutinize a `let`-bound local, so the folded record is read
# through three projections. Each is a field read, not a second fold.

def keys_mask(keys: Keys) -> U32:
  Keys{mask, _, _} = keys
  mask

# How far the pointer moved over the events the fold read, in pixels: the two look deltas
# before the sensitivity made angles of them. A screen moves its own arrow by this.
def look_dx(keys: Keys) -> F32:
  Keys{_, turn, _} = keys
  F32.div(turn, look_sensitivity())

def look_dy(keys: Keys) -> F32:
  Keys{_, _, tilt} = keys
  F32.neg(F32.div(tilt, look_sensitivity()))

def turn_delta(keys: Keys) -> F32:
  Keys{_, turn, _} = keys
  turn

def tilt_delta(keys: Keys) -> F32:
  Keys{_, _, tilt} = keys
  tilt

# The camera stage: the player's resulting eye, rebased onto the render chunk,
# with the angles the player state already carries.

def pose(state: Player.State, +origin_x: Nat, +origin_z: Nat) -> Pose:
  Player.State{+x, +y, +z, +yaw, +pitch, +velocity_y, +grounded, +health, +hunger,
    +air, +fall, +poison} = state
  +base_x = F32.from_nat(origin_x)
  +base_z = F32.from_nat(origin_z)
  Pose{Voxel.Vec{F32.sub(x, base_x), F32.add(y, eye_height()), F32.sub(z, base_z)},
    yaw, pitch}

def camera_of(+pose: Pose) -> Voxel.Camera:
  Pose{eye, yaw, pitch} = pose
  Voxel.Camera.look(eye, yaw, pitch)

def camera_forward_y(camera: Voxel.Camera) -> F32:
  Voxel.Camera{eye, forward, right, up} = camera
  Voxel.Vec{x, y, z} = forward
  y

def eye_of(+pose: Pose) -> Voxel.Vec:
  Pose{eye, _, _} = pose
  eye

def yaw_of(+pose: Pose) -> F32:
  Pose{_, yaw, _} = pose
  yaw

def pitch_of(+pose: Pose) -> F32:
  Pose{_, _, pitch} = pose
  pitch

def eye_x(eye: Voxel.Vec) -> F32:
  Voxel.Vec{x, _, _} = eye
  x

def eye_y(eye: Voxel.Vec) -> F32:
  Voxel.Vec{_, y, _} = eye
  y

def eye_z(eye: Voxel.Vec) -> F32:
  Voxel.Vec{_, _, z} = eye
  z

# The condition the client must test before it can skip a frame.
#
# The camera is the only thing the render stage reads, and `Camera.look` uses the
# eye's three components plus yaw and pitch and nothing else. So the image changes
# exactly when one of those five numbers changes. A state that moves hunger, air,
# fall damage, velocity or the grounded flag without moving the eye or turning
# the view produces the same pixels, and must not cost a frame. A world edit
# changes the grid rather than the pose, so it has to dirty the frame separately;
# this predicate is the pose half of that test.

def eye_moved(+before: Voxel.Vec, after: Voxel.Vec) -> Bool:
  Voxel.Vec{+bx, +by, +bz} = before
  Voxel.Vec{+ax, +ay, +az} = after
  Bool.or(F32.is_ne(bx, ax), Bool.or(F32.is_ne(by, ay), F32.is_ne(bz, az)))

# A `match` may only scrutinize a parameter or a field, so each of the five
# numbers the camera reads is compared through a def that receives it.

def pose_changed(+before: Pose, after: Pose) -> Bool:
  Pose{+before_eye, +before_yaw, +before_pitch} = before
  Pose{+eye, +yaw, +pitch} = after
  Bool.or(eye_moved(before_eye, eye),
    Bool.or(F32.is_ne(before_yaw, yaw), F32.is_ne(before_pitch, pitch)))

def is_grounded(state: Player.State) -> Bool:
  Player.State{x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall,
    poison} = state
  grounded

# The render seam.
#
# This is the one function a face-based renderer replaces. It takes the prebuilt
# grid and the camera and answers the frame's image. `camera_of`, `fingerprint`,
# the input fold, the player transition, the dirty test and every timing in
# `frame_bench.bend` stay exactly where they are.

def render(+grid: Voxel.VoxelGrid, +camera: Voxel.Camera, depth: Nat) -> Image:
  Voxel.render_size(grid, camera, depth)

def fingerprint(image: Image) -> U32:
  Voxel.fingerprint(image)

# The same render through the voxel probe's own chunk-level entry point, which
# rebuilds the nested grid from the bulk chunk on every call. `render` and
# `render_chunk` answer the same image for the same pose; what differs is the
# grid build, which is what a client that does not cache a chunk pays per frame.

def render_chunk(chunk: Array<U32>, +pose: Pose, depth: Nat) -> Image:
  Pose{eye, yaw, pitch} = pose
  Voxel.render_size_at(chunk, eye, yaw, pitch, depth)

def ray_abs_x(+ray: Voxel.Vec) -> F32:
  Voxel.Vec{x, _, _} = ray
  F32.abs(x)

def sky_pixel(+camera: Voxel.Camera, +x: U32, +y: U32, +half: F32, +focal: F32) -> U32:
  +ray = Voxel.Camera.ray_for(camera, x, y, half, focal)
  Voxel.sky_color(U32.add(y, F32.to_u32(ray_abs_x(ray))))

# The voxel probe's `sky` control, which is what the render stage would cost with
# the trace and its grid reads left out: the same quadtree, the same per-pixel
# ray, the same leaf shape and the same fingerprint fold. The ray is folded into
# the color so it cannot be dropped as dead code, so what this omits is exactly
# the trace. It is the floor a different rasterizer would have to beat.

def sky_image(+depth: Nat, +camera: Voxel.Camera, +half: F32, +focal: F32,
  +x: U32, +y: U32) -> Image:
  match depth:
    case 0n:
      Pix{sky_pixel(camera, x, y, half, focal)}
    case 1n+p:
      +step = U32.shln(1, p)
      tl tr bl br = sky_image(p, camera, half, focal, x, y)
        sky_image(p, camera, half, focal, (x + step : U32), y)
        sky_image(p, camera, half, focal, x, (y + step : U32))
        sky_image(p, camera, half, focal, (x + step : U32), (y + step : U32))
      Qua{tl, tr, bl, br}

def render_sky(+camera: Voxel.Camera, +depth: Nat) -> Image:
  +half = Voxel.projection_half(depth)
  sky_image(depth, camera, half, F32.mul(1.5, half), 0, 0)

# ---------------------------------------------------------------------------
# The cached world the frame reads
#
# A client builds the collision region and the render grid once and keeps them;
# the two are separate objects here because `native/player-probe` owns the
# region and the voxel probe owns the grid, and this probe owns neither.
# ---------------------------------------------------------------------------
def region() -> Maybe<&1, PlayerProbe.Region>:
  PlayerProbe.checked_from_world_state(seed(), chunk_x(), chunk_z(), columns(), rows(),
    WorldState.empty())

def chunk() -> Array<U32>:
  World.chunk(seed(), chunk_x(), chunk_z())

def grid() -> Voxel.VoxelGrid:
  Voxel.grid_from_chunk(chunk())

# The chunk's domain origin, which is what the player's cells are counted from.

def origin_x() -> Nat:
  PlayerProbe.domain_cell(Nat.mul(chunk_x(), World.chunk_size()))

def origin_z() -> Nat:
  PlayerProbe.domain_cell(Nat.mul(chunk_z(), World.chunk_size()))

def initial_player() -> Player.State:
  PlayerProbe.create_player(25n, 25n, 9n)

# `held` is the mask the player already holds, which the client's own tick carries
# between frames. `ready_holding` is the version that reads it; `ready` is this frame
# alone, which is what a headless reader wants.
def ready_holding(state: Player.State, events: List<&2, Event>, held: U32,
  +dt: F32) -> Player.State & U32:
  # Every parameter is destructured before the first `let`: a `let` turns the
  # remaining binders into computed values and a `match` may only scrutinize a
  # parameter or a field.
  Player.State{+x, +y, +z, +yaw, +pitch, +velocity_y, grounded, +health, +hunger,
    +air, +fall, +poison} = state
  +folded : Keys = input_from(events, held)
  +mask = keys_mask(folded)
  # Both looks land here: the fold's per-event deltas and the arrow keys' rate over this
  # tick. They add, so a player can hold Right and sweep with the mouse at the same time.
  +next_yaw = F32.add(F32.add(yaw, turn_delta(folded)), key_look_turn(mask, dt))
  +next_pitch = F32.clamp(
    F32.add(F32.add(pitch, tilt_delta(folded)), key_look_tilt(mask, dt)),
    F32.neg(pitch_limit()), pitch_limit())
  (Player.State{x, y, z, next_yaw, next_pitch, velocity_y, grounded, health, hunger,
    air, fall, poison}, mask)

def ready(state: Player.State, events: List<&2, Event>) -> Player.State & U32:
  ready_holding(state, events, 0, 0.0)

def ready_keys(ready: Player.State & U32) -> U32:
  (state, keys) = ready
  keys

def ready_state(ready: Player.State & U32) -> Player.State:
  (state, keys) = ready
  state

# The player stage: `Player.step` against the cached multi-chunk region. The
# probe owns the collision region, not the tick. A frame passes `prepared`
# straight through, so this def is also the seam a benchmark times on its own.

def tick(ready: Player.State & U32, +dt: F32,
  +region: PlayerProbe.Region) -> Player.State:
  (state, keys) = ready
  PlayerProbe.step(state, keys, dt, region, 25n, 25n, 9n)

# Input and the player transition, up to but not including the camera. A frame
# that skips the render still does exactly this, which is the dirty-frame cost.
#
# `held` is the mask carried in from the previous tick; see `input_from` for why it
# is one. `advance_holding` is the version that reads it and `advance` is this frame
# alone.

def advance_holding(state: Player.State, events: List<&2, Event>, held: U32, +dt: F32,
  +region: PlayerProbe.Region, +origin_x: Nat, +origin_z: Nat, previous: Pose) -> Staged:
  prepared : Player.State & U32 = ready_holding(state, events, held, dt)
  +moved : Player.State = tick(prepared, dt, region)
  +next : Pose = pose(moved, origin_x, origin_z)
  Staged{moved, next, pose_changed(previous, next)}

def staged_player(staged: Staged) -> Player.State:
  Staged{player, pose, changed} = staged
  player

def view_eye(eye: Voxel.Vec, home: Home) -> Voxel.Vec:
  Voxel.Vec{x, y, z} = eye
  Home{hx, hz} = home
  Voxel.Vec{F32.add(x, view_shift(origin_x(), hx)), y, F32.add(z, view_shift(origin_z(), hz))}

def advance(state: Player.State, events: List<&2, Event>, +dt: F32,
  +region: PlayerProbe.Region, +origin_x: Nat, +origin_z: Nat,
  previous: Pose) -> Staged:
  advance_holding(state, events, 0, dt, region, origin_x, origin_z, previous)

def rebuild.painted(+player: Player.State, +pose: Pose, chunk: Array<U32>,
  depth: Nat, +previous: U32) -> Frame:
  +image : Image = render_chunk(chunk, pose, depth)
  Frame{player, pose, fingerprint(image), True{}}

# The `sky` frame's paint: the same image with the trace and its grid reads removed.

def sky_draw.painted(+player: Player.State, +pose: Pose, depth: Nat,
  +previous: U32) -> Frame:
  +image : Image = render_sky(camera_of(pose), depth)
  Frame{player, pose, fingerprint(image), True{}}

# ---------------------------------------------------------------------------
# Reading a frame back
#
# A frame is affine, so each field is read once. A benchmark that needs two of
# them threads the frame itself, or reads a projection per use.
# ---------------------------------------------------------------------------
def digest_of(f: Frame) -> U32:
  Frame{player, pose, digest, rendered} = f
  digest

def rendered_of(f: Frame) -> Bool:
  Frame{player, pose, digest, rendered} = f
  rendered

# How many times a loop of frames actually reached the render stage. A benchmark
# folds this, so a dirty-frame phase that rendered is caught rather than reported
# as a cheap frame.

def draws_of(f: Frame) -> U32:
  Frame{player, pose, digest, rendered} = f
  Bool.to_u32(rendered)

def player_of(f: Frame) -> Player.State:
  Frame{player, pose, digest, rendered} = f
  player

def pose_of(+f: Frame) -> Pose:
  Frame{player, pose, digest, rendered} = f
  pose

# The frame's pose together with its digest, which is what the next tick needs:
# the pose to decide whether it can skip, and the digest to carry if it does.

type Carried is Data:
  Carried{player: Player.State, pose: Pose, digest: U32}

def carry(+f: Frame) -> Carried:
  Frame{player, pose, digest, rendered} = f
  Carried{player, pose, digest}

# The state a loop starts from: no digest yet, so the first frame has to draw.

def carried_seed(state: Player.State, pose: Pose) -> Carried:
  Carried{state, pose, 0}

def carried_player(+carried: Carried) -> Player.State:
  Carried{player, pose, digest} = carried
  player

def carried_pose(+carried: Carried) -> Pose:
  Carried{player, pose, digest} = carried
  pose

def carried_digest(+carried: Carried) -> U32:
  Carried{player, pose, digest} = carried
  digest

# One tick's worth of events, for the two shapes a measured frame takes. An idle
# client holds nothing, which is the shape that exercises the dirty path, and a
# turning client is the shape that exercises the render.

def idle_events() -> List<&2, Event>:
  []

def turn_events() -> List<&2, Event>:
  [Key{119, True{}}, Key{100, True{}}, Look{2.0, 0.5}]

# The player state fields a reader needs, projected one at a time because
# `Player.State` is affine and can only be destructured once.

def player_x(state: Player.State) -> F32:
  Player.State{x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall,
    poison} = state
  x

def player_y(state: Player.State) -> F32:
  Player.State{x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall,
    poison} = state
  y

def player_z(state: Player.State) -> F32:
  Player.State{x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall,
    poison} = state
  z

def player_yaw(state: Player.State) -> F32:
  Player.State{x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall,
    poison} = state
  yaw

def player_pitch(state: Player.State) -> F32:
  Player.State{x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall,
    poison} = state
  pitch

# The rendering policy the client applies. A `match` may only scrutinize a
# parameter, so the two policy bits are matched as a pair: redraw whenever either
# one is set.
#
# A world edit dirties the grid rather than the pose, so a client ORs a
# grid-version flag in at the same place: it would pass that flag as `changed`.

def draw.painted(+player: Player.State, +pose: Pose, +grid: Voxel.VoxelGrid,
  depth: Nat, +previous: U32) -> Frame:
  +image : Image = render(grid, camera_of(pose), depth)
  Frame{player, pose, fingerprint(image), True{}}

def rebuild.at(force: Bool, changed: Bool, +player: Player.State, +pose: Pose,
  chunk: Array<U32>, depth: Nat, +previous: U32) -> Frame:
  match force changed:
    case True{} True{}:
      rebuild.painted(player, pose, chunk, depth, previous)
    case True{} False{}:
      rebuild.painted(player, pose, chunk, depth, previous)
    case False{} True{}:
      rebuild.painted(player, pose, chunk, depth, previous)
    case False{} False{}:
      Frame{player, pose, previous, False{}}

def frame_rebuild(state: Player.State, events: List<&2, Event>, +dt: F32,
  +region: PlayerProbe.Region, chunk: Array<U32>, depth: Nat,
  +origin_x: Nat, +origin_z: Nat, previous: Pose, +digest: U32,
  force: Bool) -> Frame:
  prepared : Player.State & U32 = ready(state, events)
  +moved : Player.State = tick(prepared, dt, region)
  +next : Pose = pose(moved, origin_x, origin_z)
  +changed : Bool = pose_changed(previous, next)
  rebuild.at(force, changed, moved, next, chunk, depth, digest)

# The `sky` frame's draw: `draw.at` with `render_sky` in place of `render`.

def sky_draw.at(force: Bool, changed: Bool, +player: Player.State, +pose: Pose,
  depth: Nat, +previous: U32) -> Frame:
  match force changed:
    case True{} True{}:
      sky_draw.painted(player, pose, depth, previous)
    case True{} False{}:
      sky_draw.painted(player, pose, depth, previous)
    case False{} True{}:
      sky_draw.painted(player, pose, depth, previous)
    case False{} False{}:
      Frame{player, pose, previous, False{}}

def frame_sky(state: Player.State, events: List<&2, Event>, +dt: F32,
  +region: PlayerProbe.Region, depth: Nat,
  +origin_x: Nat, +origin_z: Nat, previous: Pose, +digest: U32,
  force: Bool) -> Frame:
  prepared : Player.State & U32 = ready(state, events)
  +moved : Player.State = tick(prepared, dt, region)
  +next : Pose = pose(moved, origin_x, origin_z)
  +changed : Bool = pose_changed(previous, next)
  sky_draw.at(force, changed, moved, next, depth, digest)

def draw.at(force: Bool, changed: Bool, +player: Player.State, +pose: Pose,
  +grid: Voxel.VoxelGrid, depth: Nat, +previous: U32) -> Frame:
  match force changed:
    case True{} True{}:
      draw.painted(player, pose, grid, depth, previous)
    case True{} False{}:
      draw.painted(player, pose, grid, depth, previous)
    case False{} True{}:
      draw.painted(player, pose, grid, depth, previous)
    case False{} False{}:
      Frame{player, pose, previous, False{}}

# The paint itself: the render seam and the fingerprint. This is the only place a
# frame reaches `render`.

def draw(force: Bool, staged: Staged, +grid: Voxel.VoxelGrid, depth: Nat,
  +previous: U32) -> Frame:
  Staged{player, pose, changed} = staged
  draw.at(force, changed, player, pose, grid, depth, previous)

# One full frame: the tick's events, the player transition through `Player.step`
# against the cached region, the camera rebuilt from the resulting eye and yaw,
# the render through the voxel probe, and the image fingerprint.

def frame(state: Player.State, events: List<&2, Event>, +dt: F32,
  +region: PlayerProbe.Region, +grid: Voxel.VoxelGrid, depth: Nat,
  +origin_x: Nat, +origin_z: Nat, previous: Pose, +digest: U32,
  force: Bool) -> Frame:
  +staged : Staged = advance(state, events, dt, region, origin_x, origin_z, previous)
  draw(force, staged, grid, depth, digest)

# The rebuild variant's draw: `draw.at` with `render_chunk` in place of `render`,
# so the only difference between the two frame paths is the grid build.
