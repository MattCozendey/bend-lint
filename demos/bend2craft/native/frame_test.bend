import Base
import ../world/player.bend as Player
import ../world/world.bend as World
import ./voxel.bend as Voxel
import ./player.bend as PlayerProbe
import ./frame.bend as Probe

# Every failure is IO.die, so a wrong dirty condition, a wrong render or a wrong
# region fails the run rather than printing a number that looks plausible.
def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "frame-probe-test: " ++ message)

def region_of(value: Maybe<&1, PlayerProbe.Region>) -> IO(PlayerProbe.Region):
  match value:
    case Some{region}:
      IO.pure(PlayerProbe.Region, region)
    case None{}:
      IO.die(PlayerProbe.Region, 1, "frame-probe-test: the benchmark region was refused")

def settle_ticks() -> Nat:
  120n

def render_depth() -> Nat:
  5n

# ---------------------------------------------------------------------------
# Fixtures
#
# `frame_of` and `rebuild_of` are the only two places that call `Probe.frame` and
# `Probe.frame_rebuild`, so the test and the benchmark measure the same frame.
# ---------------------------------------------------------------------------

def pose_at(+x: F32, +y: F32, +z: F32, +yaw: F32, +pitch: F32) -> Probe.Pose:
  Probe.Pose{Voxel.Vec{x, y, z}, yaw, pitch}

def state_at(+x: F32, +y: F32, +z: F32, +yaw: F32, +pitch: F32,
  +velocity_y: F32, grounded: Bool, +health: F32, +hunger: F32,
  +air: F32, +fall: F32) -> Player.State:
  Player.State{x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall,
    0.0}

def frame_digest(+f: Probe.Frame) -> U32:
  Probe.Frame{player, pose, digest, rendered} = f
  digest

def frame_rendered(+f: Probe.Frame) -> Bool:
  Probe.Frame{player, pose, digest, rendered} = f
  rendered

def frame_player(f: Probe.Frame) -> Player.State:
  Probe.Frame{player, pose, digest, rendered} = f
  player

def frame_pose(+f: Probe.Frame) -> Probe.Pose:
  Probe.Frame{player, pose, digest, rendered} = f
  pose

def keys_of(folded: Probe.Keys) -> U32:
  Probe.Keys{mask, _, _} = folded
  mask

def region_shape(region: PlayerProbe.Region) -> Nat & Nat:
  PlayerProbe.Region{+blocks, +origin_x, +origin_y, +origin_z, +width, +height, +depth}
    = region
  (width, depth)

def frame_of(+state: Player.State, events: List<&2, Event>,
  +region: PlayerProbe.Region, +grid: Voxel.VoxelGrid, +digest: U32,
  force: Bool) -> Probe.Frame:
  Probe.frame(state, events, Probe.tick_dt(), region, grid, render_depth(),
    Probe.origin_x(), Probe.origin_z(),
    Probe.pose(state, Probe.origin_x(), Probe.origin_z()), digest, force)

def rebuild_of(+state: Player.State, events: List<&2, Event>,
  +region: PlayerProbe.Region, +digest: U32, force: Bool) -> Probe.Frame:
  Probe.frame_rebuild(state, events, Probe.tick_dt(), region, Probe.chunk(),
    render_depth(), Probe.origin_x(), Probe.origin_z(),
    Probe.pose(state, Probe.origin_x(), Probe.origin_z()), digest, force)

def settle.go(remaining: Nat, +state: Player.State,
  +region: PlayerProbe.Region) -> Player.State:
  match remaining:
    case 0n:
      state
    case 1n+p:
      settle.go(p, Probe.tick(Probe.ready(state, []), Probe.tick_dt(), region), region)

def settle(iterations: Nat, +state: Player.State,
  +region: PlayerProbe.Region) -> Player.State:
  settle.go(iterations, state, region)

# ---------------------------------------------------------------------------
# The dirty-frame condition
#
# This is the one pure rule the probe adds; everything else it measures already
# existed in the voxel probe or the player probe. It is what a client must test
# before it can skip a frame.
# ---------------------------------------------------------------------------

def same_pose_is_clean() -> IO(Unit):
  +before : Probe.Pose = pose_at(9.5, 10.6, 9.5, 0.25, 0.30)
  +after : Probe.Pose = pose_at(9.5, 10.6, 9.5, 0.25, 0.30)
  do IO<Unit>:
    Unit <- check(Bool.not(Probe.pose_changed(before, after)),
      "an identical pose was reported as changed")
    IO.print("dirty: an identical pose is clean")

def moved_eye_is_dirty() -> IO(Unit):
  +before : Probe.Pose = pose_at(9.5, 10.6, 9.5, 0.25, 0.30)
  +x : Probe.Pose = pose_at(9.75, 10.6, 9.5, 0.25, 0.30)
  +y : Probe.Pose = pose_at(9.5, 10.75, 9.5, 0.25, 0.30)
  +z : Probe.Pose = pose_at(9.5, 10.6, 9.75, 0.25, 0.30)
  do IO<Unit>:
    Unit <- check(Probe.pose_changed(before, x), "moving the eye in x did not dirty the frame")
    Unit <- check(Probe.pose_changed(before, y), "moving the eye in y did not dirty the frame")
    check(Probe.pose_changed(before, z), "moving the eye in z did not dirty the frame")

def turned_camera_is_dirty() -> IO(Unit):
  +before : Probe.Pose = pose_at(9.5, 10.6, 9.5, 0.25, 0.30)
  +yawed : Probe.Pose = pose_at(9.5, 10.6, 9.5, 0.75, 0.30)
  +pitched : Probe.Pose = pose_at(9.5, 10.6, 9.5, 0.25, 0.55)
  do IO<Unit>:
    Unit <- check(Probe.pose_changed(before, yawed), "turning the yaw did not dirty the frame")
    check(Probe.pose_changed(before, pitched), "tilting the pitch did not dirty the frame")

# The complement, and the reason the predicate is worth having: a state that moves
# hunger, air, health or velocity without moving the eye or turning the view
# produces the same pixels, so it must not cost a frame.
def survival_change_is_clean() -> IO(Unit):
  +before = state_at(9.5, 10.6, 9.5, 0.25, 0.30, 0.0, True{}, 20.0, 20.0, 10.0, 0.0)
  +hunger = state_at(9.5, 10.6, 9.5, 0.25, 0.30, 0.0, True{}, 20.0, 11.0, 10.0, 0.0)
  +air = state_at(9.5, 10.6, 9.5, 0.25, 0.30, 0.0, True{}, 20.0, 20.0, 4.0, 0.0)
  +hurt = state_at(9.5, 10.6, 9.5, 0.25, 0.30, 0.0, True{}, 6.0, 20.0, 10.0, 0.0)
  +airborne = state_at(9.5, 10.6, 9.5, 0.25, 0.30, 4.0, False{}, 20.0, 20.0, 10.0, 0.0)
  +before_eye : Probe.Pose = Probe.pose(before, 0n, 0n)
  +hunger_eye : Probe.Pose = Probe.pose(hunger, 0n, 0n)
  +air_eye : Probe.Pose = Probe.pose(air, 0n, 0n)
  +hurt_eye : Probe.Pose = Probe.pose(hurt, 0n, 0n)
  +airborne_eye : Probe.Pose = Probe.pose(airborne, 0n, 0n)
  do IO<Unit>:
    Unit <- check(Bool.not(Probe.pose_changed(before_eye, hunger_eye)),
      "a hunger change dirtied a frame whose pixels cannot change")
    Unit <- check(Bool.not(Probe.pose_changed(before_eye, air_eye)),
      "an air change dirtied a frame whose pixels cannot change")
    Unit <- check(Bool.not(Probe.pose_changed(before_eye, hurt_eye)),
      "a health change dirtied a frame whose pixels cannot change")
    check(Bool.not(Probe.pose_changed(before_eye, airborne_eye)),
      "a velocity change with the eye held still dirtied the frame")

# The eye is the player plus the eye height, rebased onto the render chunk, and
# `check_eye` is written before its caller because a def may not be referenced
# before it is defined.
def check_eye(+local: Probe.Pose, +rebased: Probe.Pose, +expected_y: F32) -> IO(Unit):
  +eye : Voxel.Vec = Probe.eye_of(local)
  +rebased_eye : Voxel.Vec = Probe.eye_of(rebased)
  +chunk_x : F32 = F32.from_nat(Probe.origin_x())
  +chunk_z : F32 = F32.from_nat(Probe.origin_z())
  do IO<Unit>:
    Unit <- check(F32.is_eq(Probe.eye_x(eye), 9.5), "the eye lost its x")
    Unit <- check(F32.is_eq(Probe.eye_y(eye), expected_y),
      "the eye is not the player plus the eye height")
    Unit <- check(F32.is_eq(Probe.eye_z(eye), 9.5), "the eye lost its z")
    Unit <- check(F32.is_eq(Probe.yaw_of(local), 0.25), "the pose lost the player's yaw")
    Unit <- check(F32.is_eq(Probe.pitch_of(local), 0.30),
      "the pose lost the player's pitch")
    Unit <- check(F32.is_eq(Probe.eye_x(rebased_eye), F32.sub(9.5, chunk_x)),
      "the eye lost its x rebasing onto the render chunk")
    check(F32.is_eq(Probe.eye_z(rebased_eye), F32.sub(9.5, chunk_z)),
      "the eye lost its z rebasing onto the render chunk")

# `Player.State` is the body and carries no eye, so the eye is the adapter's job.
def eye_is_the_player_plus_eye_height() -> IO(Unit):
  +state = state_at(9.5, 10.0, 9.5, 0.25, 0.30, 0.0, True{}, 20.0, 20.0, 10.0, 0.0)
  +local : Probe.Pose = Probe.pose(state, 0n, 0n)
  +rebased : Probe.Pose = Probe.pose(state, Probe.origin_x(), Probe.origin_z())
  +expected_y : F32 = F32.add(10.0, Probe.eye_height())
  check_eye(local, rebased, expected_y)

# The camera has to start inside the region the renderer is handed, or the DDA reads
# nothing and the render stage would measure an all-sky frame. The bound is the view
# region, not one chunk: the client renders `view_columns` x `view_rows` chunks, and
# the eye at the world's own spawn cell is inside that region but outside any single
# chunk of it.
def check_eye_inside(+eye: Voxel.Vec) -> IO(Unit):
  +limit_x : F32 = U32.to_f32(U32.mul(U32.from_nat(World.chunk_size()),
    U32.from_nat(Probe.view_columns())))
  +limit_z : F32 = U32.to_f32(U32.mul(U32.from_nat(World.chunk_size()),
    U32.from_nat(Probe.view_rows())))
  +height : F32 = U32.to_f32(U32.from_nat(World.max_y()))
  +ex : F32 = Probe.eye_x(eye)
  +ey : F32 = Probe.eye_y(eye)
  +ez : F32 = Probe.eye_z(eye)
  do IO<Unit>:
    Unit <- check(Bool.and(F32.is_ge(ex, 0.0), F32.is_lt(ex, limit_x)),
      "the spawned eye is outside the view region in x")
    Unit <- check(Bool.and(F32.is_ge(ey, 0.0), F32.is_lt(ey, height)),
      "the spawned eye is outside the view region in y")
    Unit <- check(Bool.and(F32.is_ge(ez, 0.0), F32.is_lt(ez, limit_z)),
      "the spawned eye is outside the view region in z")
    IO.print("spawn eye=" ++ F32.show(ex) ++ "," ++ F32.show(ey) ++ "," ++ F32.show(ez))

def eye_lands_inside_the_render_chunk() -> IO(Unit):
  +posed : Probe.Pose = Probe.pose(Probe.initial_player(), Probe.origin_x(),
    Probe.origin_z())
  +eye : Voxel.Vec = Probe.eye_of(posed)
  check_eye_inside(eye)

# ---------------------------------------------------------------------------
# The input stage
# ---------------------------------------------------------------------------

def input_folds_key_events() -> IO(Unit):
  +events : List<&2, Event> = [Key{119, True{}}, Key{100, True{}}]
  +folded : Probe.Keys = Probe.input(events)
  +held : U32 = keys_of(folded)
  do IO<Unit>:
    Unit <- check(U32.is_eq(held, 9),
      "holding w and d did not set the forward+strafe mask (1 for forward, 8 for right)")
    IO.print("input: forward+right mask=" ++ U32.show(held))

def input_releases_keys() -> IO(Unit):
  +events : List<&2, Event> = [Key{119, True{}}, Key{119, False{}}]
  +folded : Probe.Keys = Probe.input(events)
  do IO<Unit>:
    check(U32.is_eq(keys_of(folded), 0), "releasing w left the key held")

def input_ignores_unmapped_codes() -> IO(Unit):
  +events : List<&2, Event> = [Key{4242, True{}}, Move{1, 2}]
  +folded : Probe.Keys = Probe.input(events)
  do IO<Unit>:
    check(U32.is_eq(keys_of(folded), 0), "an unmapped key code set a movement bit")

def check_look(+before: Probe.Pose, prepared: Player.State & U32) -> IO(Unit):
  (state, mask) = prepared
  +after : Probe.Pose = Probe.pose(state, 0n, 0n)
  +expected_yaw : F32 = F32.add(Probe.yaw_of(before),
    F32.mul(20.0, Probe.look_sensitivity()))
  # The pitch moves the other way: the runtime reports the pointer's offset in a
  # window space whose y grows downward, and a positive pitch is looking up.
  +expected_pitch : F32 = F32.sub(Probe.pitch_of(before),
    F32.mul(8.0, Probe.look_sensitivity()))
  do IO<Unit>:
    Unit <- check(F32.is_eq(Probe.yaw_of(after), expected_yaw),
      "two look events did not accumulate into yaw")
    Unit <- check(F32.is_eq(Probe.pitch_of(after), expected_pitch),
      "two look events did not accumulate into pitch")
    Unit <- check(U32.is_eq(mask, 0), "a look event set a movement key")
    check(F32.is_eq(Probe.eye_x(Probe.eye_of(after)),
      Probe.eye_x(Probe.eye_of(before))), "mouse look moved the player's position")

# A held key stays held. `Window.frame` hands the tick only the events that arrived
# during that frame, so a frame carrying no key event is the ordinary frame of a key
# the player is still holding down, and the mask has to survive it. Folding from zero
# every frame leaves movement riding X11's auto-repeat instead of the loop: a delay
# before the first step, one step per repeat rather than per tick, and a diagonal that
# breaks up because the two repeats rarely land in the same frame.
def input_holds_keys_across_frames() -> IO(Unit):
  +pressed : List<&2, Event> = [Key{119, True{}}]
  +held : U32 = keys_of(Probe.input_from(pressed, 0))
  +silent : List<&2, Event> = []
  +carried : U32 = keys_of(Probe.input_from(silent, held))
  do IO<Unit>:
    check(U32.is_eq(carried, 1), "a frame with no key event dropped the held key")

# A release still clears, so seeding the fold cannot become "or the previous mask in".
def input_releases_across_frames() -> IO(Unit):
  +release : List<&2, Event> = [Key{119, False{}}]
  +after : U32 = keys_of(Probe.input_from(release, 1))
  do IO<Unit>:
    check(U32.is_eq(after, 0), "a release did not clear the key it named")

# A mouse travelling down the screen has to look down. The pitch is positive up
# (`Player.direction` and `Camera.look` both put `sin(pitch)` in the forward y), and
# the X11 runtime reports a pointer y that grows downward, so the fold has to spend
# the dy rather than add it.
#
# `check_pitch_fell` takes the pair as a parameter rather than destructuring it after
# a `let`, because the destructured binder would be a local and a match may not
# scrutinize one.
def check_pitch_fell_by(prepared: Player.State & U32, moved: F32) -> IO(Unit):
  (state, mask) = prepared
  # The pitch is read once: a `Player.State` is consumed once and the pitch is wanted
  # against two expectations here.
  +pitch : F32 = Probe.player_pitch(state)
  +before : F32 = Probe.player_pitch(Probe.initial_player())
  +want : F32 = F32.sub(before, F32.mul(moved, Probe.look_sensitivity()))
  do IO<Unit>:
    Unit <- check(F32.is_lt(pitch, before),
      "a look delta did not lower the pitch")
    Unit <- check(F32.is_eq(pitch, want),
      "the pitch did not turn by the look delta times the sensitivity")
    check(U32.is_eq(mask, 0), "a look event set a movement key")

def input_turns_by_the_look_delta() -> IO(Unit):
  # Sixty pixels of movement is sixty pixels of turn, whatever the frame before reported.
  check_pitch_fell_by(Probe.ready(Probe.initial_player(), [Look{0.0, 60.0}]), 60.0)

def check_pitch_fell(prepared: Player.State & U32) -> IO(Unit):
  (state, mask) = prepared
  +before : F32 = Probe.player_pitch(Probe.initial_player())
  do IO<Unit>:
    Unit <- check(F32.is_lt(Probe.player_pitch(state), before),
      "moving the mouse down did not lower the pitch")
    check(U32.is_eq(mask, 0), "a look event set a movement key")

def input_looks_down_when_the_mouse_goes_down() -> IO(Unit):
  check_pitch_fell(Probe.ready(Probe.initial_player(), [Look{0.0, 40.0}]))

# --- a look is this frame's movement ------------------------------------------
#
# `window.c:591` pushes `Look{x - cx, y - cy}` and `window.c:594` then warps the pointer
# back to the window centre, which is what makes the event this frame's movement.
# `lab/native/pointer/census-xvfb.sh` measures that on a real X server: eight relative steps
# of ten pixels arrive as eight `Look{10 0}`, one per frame. Under WSLg the same delta comes
# from the host through `native/pointer.bend`, as a `Look` again. So a look that repeats on
# the next frame is a mouse still travelling at the same pace and has to turn again: a fold
# that differenced it against the frame before would read a steady sweep as a mouse held
# still.

def turned_twice() -> Player.State:
  Probe.ready_state(Probe.ready(Probe.ready_state(Probe.ready(Probe.initial_player(),
    [Look{10.0, 0.0}])), [Look{10.0, 0.0}]))

def input_turns_again_on_a_repeated_look() -> IO(Unit):
  # Two frames that each carry Look{10, 0} are twenty pixels of travel.
  +want : F32 = F32.add(Probe.player_yaw(Probe.initial_player()),
    F32.mul(20.0, Probe.look_sensitivity()))
  check(F32.is_le(F32.abs(F32.sub(Probe.player_yaw(turned_twice()), want)), 0.0001),
    "a look that repeated on the next frame did not turn again, so it is being read as a position")

# A `Move` is where the pointer is while nothing holds it. It is a position and not a
# movement, so it must not turn the camera: the look belongs to a held pointer.
def input_does_not_look_on_a_move() -> IO(Unit):
  check(F32.is_le(F32.abs(F32.sub(
      Probe.player_yaw(Probe.ready_state(Probe.ready(Probe.initial_player(), [Move{300, 296}]))),
      Probe.player_yaw(Probe.initial_player()))), 0.0),
    "an ungrabbed pointer position turned the camera")

# --- looking by key ------------------------------------------------------------
#
# The arrow keys are the measured look path under WSLg, so the direction and the rate are
# pinned here rather than left for a player to discover. The code test matters most: a code
# that is not the runtime's own translation would look right on the machine it was typed on
# and read as nothing at all on this one.

def yaw_of(state: Player.State) -> F32:
  Probe.player_yaw(state)
def pitch_of(state: Player.State) -> F32:
  Probe.player_pitch(state)
def initial() -> Player.State:
  Probe.initial_player()
def faced(events: List<&2, Event>, dt: F32) -> Player.State:
  Probe.ready_state(
    Probe.ready_holding(initial(), events, 0, dt))
def held_key(code: U32) -> List<&2, Event>:
  [Key{code, True{}}]
def differs(+a: F32, +b: F32) -> Bool:
  Bool.xor(F32.is_le(a, b), F32.is_ge(a, b))
def close(a: F32, b: F32) -> Bool:
  F32.is_le(F32.abs(F32.sub(a, b)), 0.0001)
def one_bit(code: U32, +name: String) -> IO(Unit):
  check(Bool.not(Bool.xor(U32.is_eq(Probe.key_bit(code), 0), False{})),
    name ++ " has no bit of its own, so it reads as held for ever")
def apart(a: U32, b: U32) -> IO(Unit):
  check(Bool.not(U32.is_eq(Probe.key_bit(a), Probe.key_bit(b))),
    "two arrow keys resolve to the same bit, so one of them cannot be read")
def arrow_codes_are_the_runtime_translation() -> IO(Unit):
  # window.c:507: XK_Up, XK_Down, XK_Left, XK_Right. Every code must map to a bit of its
  # own, because a code missing from `key_bit` reads as 0 and a zero bit reads as held for
  # ever -- which is a camera that spins on its own, not one that does not move.
  do IO<Unit>:
    up : Unit <- one_bit(Probe.arrow_up(), "Up")
    down : Unit <- one_bit(Probe.arrow_down(), "Down")
    left : Unit <- one_bit(Probe.arrow_left(), "Left")
    one_bit(Probe.arrow_right(), "Right")
def arrow_codes_are_four_different_keys() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- apart(Probe.arrow_up(), Probe.arrow_down())
    b : Unit <- apart(Probe.arrow_up(), Probe.arrow_left())
    c : Unit <- apart(Probe.arrow_up(), Probe.arrow_right())
    d : Unit <- apart(Probe.arrow_down(), Probe.arrow_left())
    e : Unit <- apart(Probe.arrow_down(), Probe.arrow_right())
    apart(Probe.arrow_left(), Probe.arrow_right())
# "These two yaws are not the same" and "these two yaws are the same" are two different
# assertions, and using one for both is how the key-look tests came to pass a spin and fail a
# still camera in the same run.
def turned(state: Player.State, at: Player.State, +label: String, +complaint: String) ->
  IO(Unit):
  check(differs(yaw_of(state), yaw_of(at)), label ++ complaint)

def still(state: Player.State, at: Player.State, +label: String, +complaint: String) ->
  IO(Unit):
  check(Bool.not(differs(yaw_of(state), yaw_of(at))), label ++ complaint)
def arrow_right_turns_right() -> IO(Unit):
  turned(faced(held_key(Probe.arrow_right()), 1.0), initial(),
    "the Right arrow ", "did not turn the camera")
def arrow_left_turns_left() -> IO(Unit):
  turned(faced(held_key(Probe.arrow_left()), 1.0), initial(),
    "the Left arrow ", "turned the wrong way, or not at all")
def arrow_up_looks_up() -> IO(Unit):
  # Pitch is positive up in the picture, measured by rendering the spawn scene from one eye:
  # pitch +1 gives 16311 sky pixels, -1 gives 8. `fold_tilt` says so and this holds it to it.
  check(F32.is_gt(pitch_of(faced(held_key(Probe.arrow_up()), 1.0)), 0.0),
    "the Up arrow did not raise the pitch")
def arrow_down_looks_down() -> IO(Unit):
  check(F32.is_lt(pitch_of(faced(held_key(Probe.arrow_down()), 1.0)), 0.0),
    "the Down arrow spent nothing, so it looked up instead of down")
def both_arrows_hold_still() -> IO(Unit):
  # A player who rolls both fingers onto Left and Right means hold still, so the two must
  # cancel rather than sum. 1.6 + 1.6 is 3.2 radians a second, which would be a spin.
  still(faced([Key{Probe.arrow_left(), True{}}, Key{Probe.arrow_right(), True{}}], 1.0),
    initial(), "holding Left and Right together ", "drifted the yaw")
def the_rate_follows_the_tick() -> IO(Unit):
  # The turn is a rate scaled by the tick, not a jump per press, so a tenth of a second has
  # to be a tenth of the turn. If this fails, the camera turns by one step per frame and
  # walks at whatever rate the frame rate happens to be.
  second = faced(held_key(Probe.arrow_right()), 1.0)
  tenth = faced(held_key(Probe.arrow_right()), 0.1)
  check(differs(yaw_of(second), yaw_of(tenth)),
    "the turn did not depend on how long the tick was")
def the_rate_is_the_number_it_says() -> IO(Unit):
  # One second of Right is `turn_rate()` radians, to within a float's worth of rounding.
  check(close(yaw_of(faced(held_key(Probe.arrow_right()), 1.0)), Probe.turn_rate()),
    "a second of Right did not turn the camera by the stated rate")


# The render seam and the voxel probe's own chunk-level entry point must agree, or
# "bootstrap once" and "rebuild per frame" would be two different programs. The
# frame must also differ from the `sky` control, or the render stage is not reading
# the grid at all and every number this probe reports would be the sky cost.
# The render seam and the voxel probe's own chunk-level entry point must agree, or
# "bootstrap once" and "rebuild per frame" would be two different programs. The
# frame must also differ from the `sky` control, or the render stage is not reading
# the grid at all and every number this probe reports would be the sky cost.

def no_arrow_no_turn() -> IO(Unit):
  # A frame holding only a movement key must not turn at all, or the camera drifts on its own
  # while the player walks.
  still(faced(held_key(119), 1.0), initial(),
    "walking forward also ", "turned the camera")

def the_key_look_composes_with_the_mouse() -> IO(Unit):
  # Both looks land in the same two fields and add, so holding Right while the pointer moves
  # turns by more than either alone rather than one of them cancelling the other.
  both = Probe.ready_state(Probe.ready_holding(initial(),
    [Key{Probe.arrow_right(), True{}}, Look{10.0, 0.0}], 0, 1.0))
  check(F32.is_gt(yaw_of(both), yaw_of(faced(held_key(Probe.arrow_right()), 1.0))),
    "the arrow key and the pointer fought each other instead of adding")

def input_accumulates_look() -> IO(Unit):
  +events : List<&2, Event> = [Look{10.0, 4.0}, Look{10.0, 4.0}]
  +before : Probe.Pose = Probe.pose(Probe.initial_player(), 0n, 0n)
  ready : Player.State & U32 = Probe.ready(Probe.initial_player(), events)
  check_look(before, ready)

# ---------------------------------------------------------------------------
# The cached world
# ---------------------------------------------------------------------------

def report_shape(+width: Nat, +depth: Nat, +chunks: Nat, +cells: Nat) -> IO(Unit):
  do IO<Unit>:
    Unit <- check(Nat.is_gt(chunks, 1n), "the benchmark region is not multi-chunk")
    Unit <- check(Nat.is_eq(width, 32n), "the region width is not two chunks")
    Unit <- check(Nat.is_eq(depth, 32n), "the region depth is not two chunks")
    IO.print("region chunks=" ++ Nat.show(chunks) ++ " width=" ++ Nat.show(width)
      ++ " depth=" ++ Nat.show(depth) ++ " cells=" ++ Nat.show(cells))

def report_region(shape: Nat & Nat) -> IO(Unit):
  (width, depth) = shape
  +chunks : Nat = Nat.mul(Probe.columns(), Probe.rows())
  +cells : Nat = PlayerProbe.region_cells(Probe.columns(), Probe.rows())
  report_shape(width, depth, chunks, cells)

def region_is_multi_chunk() -> IO(Unit):
  do IO<Unit>:
    +region : PlayerProbe.Region <- region_of(Probe.region())
    shape : Nat & Nat = region_shape(region)
    report_region(shape)

# The player tick has to run against that cached region: the spawn must settle on
# terrain inside it and stay there, or no frame is ever idle and the dirty case
# cannot be measured at all.
def report_settled(settled: Player.State) -> IO(Unit):
  Player.State{+x, +y, +z, +yaw, +pitch, +velocity_y, +grounded, +health, +hunger,
    +air, +fall, +poison} = settled
  do IO<Unit>:
    Unit <- check(F32.is_gt(y, 0.0), "the settled player fell out of the world")
    Unit <- check(grounded, "the settled player never landed, so no frame is idle")
    IO.print("settled at " ++ F32.show(x) ++ "," ++ F32.show(y) ++ "," ++ F32.show(z)
      ++ " grounded=" ++ Bool.show(grounded))

def player_tick_settles_on_the_region() -> IO(Unit):
  do IO<Unit>:
    +region : PlayerProbe.Region <- region_of(Probe.region())
    +settled : Player.State = settle(settle_ticks(), Probe.initial_player(), region)
    report_settled(settled)

# ---------------------------------------------------------------------------
# The frame
# ---------------------------------------------------------------------------

# The render seam and the voxel probe's own chunk-level entry point must agree, or
# "bootstrap once" and "rebuild per frame" would be two different programs. The
# frame must also differ from the `sky` control, or the render stage is not reading
# the grid at all and every number this probe reports would be the sky cost.

def check_seam(+region: PlayerProbe.Region, +grid: Voxel.VoxelGrid,
  +settled: Player.State) -> IO(Unit):
  +frame : Probe.Frame = frame_of(settled, [], region, grid, 0, True{})
  +posed : Probe.Pose = frame_pose(frame)
  +camera : Voxel.Camera = Probe.camera_of(posed)
  +seam : U32 = Probe.fingerprint(Probe.render(grid, camera, render_depth()))
  +voxel : U32 = Probe.fingerprint(Probe.render_chunk(Probe.chunk(), posed,
    render_depth()))
  +sky : U32 = Probe.fingerprint(Probe.render_sky(camera, render_depth()))
  +center : U32 = Voxel.pixel_color_for(grid, camera, 16, 16, 16.0, 24.0)
  +sky_center : U32 = Voxel.sky_color(16)
  do IO<Unit>:
    IO.print("seam_digest=" ++ U32.show(seam) ++ " render_chunk_digest="
      ++ U32.show(voxel) ++ " sky_digest=" ++ U32.show(sky)
      ++ " center=" ++ U32.show(center) ++ " sky_center=" ++ U32.show(sky_center))
    Unit <- check(U32.is_eq(seam, voxel),
      "the render seam does not match the voxel probe's render_size_at")
    Unit <- check(U32.is_ne(seam, sky),
      "the frame at the settled spawn equals the sky control, so it renders no terrain")
    check(U32.is_ne(center, sky_center),
      "the centre pixel of the settled frame is sky, so the render reads no blocks")

def seam_matches_render_size_at() -> IO(Unit):
  do IO<Unit>:
    +region : PlayerProbe.Region <- region_of(Probe.region())
    +grid : Voxel.VoxelGrid = Probe.grid()
    +settled : Player.State = settle(settle_ticks(), Probe.initial_player(), region)
    check_seam(region, grid, settled)

# The dirty path: once the player is at rest, consecutive idle frames must skip the
# render and carry the previous digest forward unchanged.
def report_idle(+first: Probe.Frame, +second: Probe.Frame,
  +third: Probe.Frame) -> IO(Unit):
  +d1 : U32 = frame_digest(first)
  +d2 : U32 = frame_digest(second)
  +d3 : U32 = frame_digest(third)
  +r1 : Bool = frame_rendered(first)
  +r2 : Bool = frame_rendered(second)
  do IO<Unit>:
    Unit <- check(r1, "the forced first frame did not render")
    Unit <- check(Bool.not(r2), "the second settled idle frame rendered instead of skipping")
    Unit <- check(U32.is_eq(d1, d2),
      "a skipped frame changed the fingerprint it carried forward")
    Unit <- check(U32.is_eq(d2, d3), "the third idle frame changed the carried fingerprint")
    IO.print("forced frame rendered once, then two idle frames carried "
      ++ U32.show(d3) ++ " without rendering")

def idle_frames_skip_the_render() -> IO(Unit):
  do IO<Unit>:
    +region : PlayerProbe.Region <- region_of(Probe.region())
    +grid : Voxel.VoxelGrid = Probe.grid()
    +settled : Player.State = settle(settle_ticks(), Probe.initial_player(), region)
    +first : Probe.Frame = frame_of(settled, [], region, grid, 0, True{})
    +d1 : U32 = frame_digest(first)
    +second : Probe.Frame = frame_of(frame_player(first), [], region, grid, d1, False{})
    +d2 : U32 = frame_digest(second)
    +third : Probe.Frame = frame_of(frame_player(second), [], region, grid, d2, False{})
    report_idle(first, second, third)

# The rebuild path has to skip on the same condition, so the two frame paths stay
# comparable.
def report_rebuild(+first: Probe.Frame, +second: Probe.Frame) -> IO(Unit):
  +d1 : U32 = frame_digest(first)
  +d2 : U32 = frame_digest(second)
  +r1 : Bool = frame_rendered(first)
  +r2 : Bool = frame_rendered(second)
  do IO<Unit>:
    Unit <- check(r1, "the forced first rebuild frame did not render")
    Unit <- check(Bool.not(r2), "the rebuild path rendered a second idle frame")
    check(U32.is_eq(d1, d2), "the rebuild path changed the carried fingerprint")

def rebuild_skips_the_same_way() -> IO(Unit):
  do IO<Unit>:
    +region : PlayerProbe.Region <- region_of(Probe.region())
    +settled : Player.State = settle(settle_ticks(), Probe.initial_player(), region)
    +first : Probe.Frame = rebuild_of(settled, [], region, 0, True{})
    +d1 : U32 = frame_digest(first)
    +second : Probe.Frame = rebuild_of(frame_player(first), [], region, d1, False{})
    report_rebuild(first, second)

# Holding a movement key has to move the player and dirty the frame, or the dirty
# test would be true for the wrong reason.
def report_walk(+before: Probe.Pose, +after: Probe.Pose, +rendered: Bool) -> IO(Unit):
  +moved : Bool = Probe.pose_changed(before, after)
  +x0 : F32 = Probe.eye_x(Probe.eye_of(before))
  +x1 : F32 = Probe.eye_x(Probe.eye_of(after))
  +y0 : F32 = Probe.eye_y(Probe.eye_of(before))
  +y1 : F32 = Probe.eye_y(Probe.eye_of(after))
  +z0 : F32 = Probe.eye_z(Probe.eye_of(before))
  +z1 : F32 = Probe.eye_z(Probe.eye_of(after))
  do IO<Unit>:
    Unit <- check(moved, "holding forward for one tick did not move the camera")
    Unit <- check(rendered, "a moved player did not dirty the frame")
    IO.print("walked eye " ++ F32.show(x0) ++ "," ++ F32.show(y0) ++ "," ++ F32.show(z0)
      ++ " to " ++ F32.show(x1) ++ "," ++ F32.show(y1) ++ "," ++ F32.show(z1))

# --- which way is right ----------------------------------------------------------
#
# The mask test above cannot see this, and a strafe that goes the wrong way is invisible
# until a player walks into it: `Player.step` reads `input_axis(held(keys, 8), held(keys, 2))`,
# so the *number* decides the direction, and 8 has to be the player's right at yaw 0 where
# forward is -z. The table had A on 8 and D on 2, and the strafe went left when the player
# pressed right. These walk the player and read which way they ended up.
def right_way(after: F32, before: F32, want_right: Bool) -> Bool:
  Bool.xor(want_right, F32.is_lt(after, before))

def strafed_player(walked: Probe.Staged) -> Player.State:
  Probe.Staged{player, pose, changed} = walked
  player

def check_strafed(walked: Probe.Staged, before: Probe.Pose, want_right: Bool,
  +label: String) -> IO(Unit):
  +moved : Player.State = strafed_player(walked)
  +after : Probe.Pose = Probe.pose(moved, 0n, 0n)
  check(right_way(Probe.eye_x(Probe.eye_of(after)), Probe.eye_x(Probe.eye_of(before)),
    want_right), label)

def check_strafe_direction(code: U32, +label: String, want_right: Bool) -> IO(Unit):
  do IO<Unit>:
    +region : PlayerProbe.Region <- region_of(Probe.region())
    +settled : Player.State = settle(settle_ticks(), Probe.initial_player(), region)
    +before : Probe.Pose = Probe.pose(settled, 0n, 0n)
    +walked : Probe.Staged = Probe.advance(settled, [Key{code, True{}}],
      Probe.tick_dt(), region, 0n, 0n, before)
    check_strafed(walked, before, want_right, label)

def d_strafes_right() -> IO(Unit):
  check_strafe_direction(100, "pressing D went left instead of right", True{})

def a_strafes_left() -> IO(Unit):
  check_strafe_direction(97, "pressing A went right instead of left", False{})

def strafed_x(walked: Probe.Staged, before: Probe.Pose) -> F32:
  F32.sub(Probe.eye_x(Probe.eye_of(Probe.pose(strafed_player(walked), 0n, 0n))),
    Probe.eye_x(Probe.eye_of(before)))

def sum_zero(+a: F32, +b: F32) -> Bool:
  F32.is_le(F32.abs(F32.add(a, b)), 0.0001)

def a_and_d_are_mirrors() -> IO(Unit):
  # The two strafe displacements must be exact opposites of each other, which is a statement
  # about the mapping alone and owes nothing to the terrain. An earlier version of this test
  # walked forward as a control and read the collision slide instead: the player settled into
  # a spot where walking -z pushed them along +x, so the control failed for a reason that had
  # nothing to do with what it was checking.
  do IO<Unit>:
    +region : PlayerProbe.Region <- region_of(Probe.region())
    +settled : Player.State = settle(settle_ticks(), Probe.initial_player(), region)
    +before : Probe.Pose = Probe.pose(settled, 0n, 0n)
    +right : Probe.Staged = Probe.advance(settled, [Key{100, True{}}], Probe.tick_dt(),
      region, 0n, 0n, before)
    +left : Probe.Staged = Probe.advance(settled, [Key{97, True{}}], Probe.tick_dt(),
      region, 0n, 0n, before)
    check(sum_zero(strafed_x(right, before), strafed_x(left, before)),
      "D and A did not move the player by opposite amounts, so one of them is mis-mapped")

def held_input_dirties_the_frame() -> IO(Unit):
  do IO<Unit>:
    +region : PlayerProbe.Region <- region_of(Probe.region())
    +grid : Voxel.VoxelGrid = Probe.grid()
    +settled : Player.State = settle(settle_ticks(), Probe.initial_player(), region)
    +events : List<&2, Event> = [Key{119, True{}}]
    +idle : Probe.Frame = frame_of(settled, [], region, grid, 0, False{})
    +walking : Probe.Frame = frame_of(frame_player(idle), events, region, grid,
      frame_digest(idle), False{})
    report_walk(frame_pose(idle), frame_pose(walking), frame_rendered(walking))

# --- the mouse buttons ---------------------------------------------------------
#
# The left button and the right button each hold a bit of their own, which no key holds.
# The middle button holds nothing, and a release lets go.
def buttons_are_the_action_keys() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(keys_of(Probe.input([Mouse{64, 64, 0, True{}}])), Probe.left_bit()),
      "the left button did not hold its bit")
    Unit <- check(U32.is_eq(keys_of(Probe.input([Mouse{64, 64, 1, True{}}])), Probe.right_bit()),
      "the right button did not hold its bit")
    Unit <- check(U32.is_eq(keys_of(Probe.input([Mouse{64, 64, 2, True{}}])), 0),
      "the middle button held a key")
    check(U32.is_eq(keys_of(Probe.input_from([Mouse{64, 64, 0, False{}}], Probe.left_bit())), 0),
      "releasing the left button did not let it go")

# --- key edges ---------------------------------------------------------------
#
# A held key must act once, not sixty times a second, so every action is an edge against the
# mask the previous tick ended with. The dig is the key or the left button and the place is
# the key or the right button; the save is a key; and escape quits on a press and only where
# no screen is open, because a screen is what it closes there.
def keys_are_edges_and_not_levels() -> IO(Unit):
  +dig = Probe.key_bit(Probe.dig_code())
  +place = Probe.key_bit(Probe.place_code())
  +save = Probe.key_bit(Probe.save_code())
  +escape = Probe.key_bit(Probe.escape_code())
  do IO<Unit>:
    Unit <- check(Probe.wants_dig(0, dig), "a fresh dig press did not count as an edge")
    Unit <- check(Bool.not(Probe.wants_dig(dig, dig)), "a held dig key repeated instead of firing once")
    Unit <- check(Probe.wants_dig(0, Probe.left_bit()), "a fresh left click did not count as a dig")
    Unit <- check(Bool.not(Probe.wants_dig(Probe.left_bit(), Probe.left_bit())),
      "a held left button repeated instead of firing once")
    Unit <- check(Probe.wants_place(0, place), "a fresh place press did not count as an edge")
    Unit <- check(Bool.not(Probe.wants_place(place, place)),
      "a held place key repeated instead of firing once")
    Unit <- check(Probe.wants_place(0, Probe.right_bit()), "a fresh right click did not count as a place")
    Unit <- check(Bool.not(Probe.wants_dig(0, place)), "a place press was read as a dig press")
    Unit <- check(Bool.not(Probe.wants_place(0, dig)), "a dig press was read as a place press")
    Unit <- check(Probe.wants_save(0, save), "a fresh save press did not count as an edge")
    Unit <- check(Bool.not(Probe.wants_save(save, save)), "a held save key repeated instead of firing once")
    Unit <- check(Probe.quitting_from(False{}, 0, escape, False{}), "an escape press did not quit")
    Unit <- check(Bool.not(Probe.quitting_from(False{}, escape, escape, False{})),
      "a held escape quit again instead of waiting for a press")
    Unit <- check(Bool.not(Probe.quitting_from(False{}, 0, escape, True{})),
      "escape quit the client while a screen was open, where it closes the screen")
    check(Probe.quitting_from(True{}, escape, 0, True{}), "the window's close did not quit")

# The dig button is a level: held, the dig goes on, and either the key or the left button
# holds it.
def digging_is_a_level() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(Probe.digging(Probe.key_bit(Probe.dig_code())), "the dig key did not dig")
    Unit <- check(Probe.digging(Probe.left_bit()), "the left button did not dig")
    Unit <- check(Bool.not(Probe.digging(Probe.key_bit(Probe.place_code()))), "the place key dug")
    check(Bool.not(Probe.digging(0)), "no key dug")

# --- the region follows the player ---------------------------------------------
#
# The region is five chunks per axis and `Home` is its first, so its middle chunk is the
# third: cells 32 to 47 of a region that starts at 0. It stays put while the player is in
# that chunk or within four cells of it, and past that it moves so the player's chunk is the
# middle one again. The margin is what keeps a player standing on a chunk boundary from
# moving the region with every step.
def home_is(+origin: Nat, +cell: Nat, +want: Nat, +label: String) -> IO(Unit):
  check(Nat.is_eq(Probe.home_axis(origin, cell), want), label)

def region_follows_the_player() -> IO(Unit):
  do IO<Unit>:
    Unit <- home_is(0n, 40n, 0n, "a player in the middle chunk moved the region")
    Unit <- home_is(0n, 48n, 0n, "a player one cell past the middle chunk moved the region")
    Unit <- home_is(0n, 51n, 0n, "a player inside the margin moved the region")
    Unit <- home_is(0n, 52n, 1n, "a player past the margin did not move the region east")
    Unit <- home_is(1n, 46n, 1n, "a player inside the margin on the west side moved the region")
    Unit <- home_is(1n, 43n, 0n, "a player past the margin did not move the region west")
    Unit <- home_is(3n, 200n, 10n, "a player far from the region did not bring it to their chunk")
    # The start is window chunk 2047, the chunk before world chunk 0, and the spawn is window
    # cell 32793, in the region's middle chunk. A player eleven cells west of the world's
    # origin moves the region two chunks before theirs, which is a plain number in the window.
    Unit <- check(Nat.is_eq(Probe.home_x(Probe.home_start()), 2047n), "the region does not start a chunk before the world's origin")
    Unit <- home_is(2047n, 32793n, 2047n, "the spawn moved the region")
    home_is(2047n, 32757n, 2045n, "a player west of the origin did not move the region past it")

# The collision region is two chunks, thirty-two cells, and the player is kept at least six
# cells inside it: it stays while the player is between its sixth and twenty-sixth cell, and
# past that it moves so the player is in its middle sixteen.
def den_is(+origin: Nat, +cell: Nat, +want: Nat, +label: String) -> IO(Unit):
  check(Nat.is_eq(Probe.den_axis(origin, cell), want), label)

def collision_region_keeps_the_player_inside() -> IO(Unit):
  do IO<Unit>:
    Unit <- den_is(2049n, 32793n, 2049n, "the spawn moved the collision region")
    Unit <- den_is(2049n, 32790n, 2049n, "a player six cells inside moved the collision region")
    Unit <- den_is(2049n, 32789n, 2048n, "a player five cells from the west edge did not move it west")
    Unit <- den_is(2049n, 32809n, 2049n, "a player seven cells from the east edge moved the collision region")
    den_is(2049n, 32810n, 2050n, "a player six cells from the east edge did not move it east")

# The pose counts the eye from window cell 32784, chunk (1, 1). In the starting region,
# which begins two chunks earlier, the same eye is thirty-two cells further in; in one that
# begins at the pose's chunk it is where the pose says; in one that has followed the player
# a chunk past it, it is sixteen cells before the region.
def eye_x_in(home: Probe.Home) -> F32:
  Probe.eye_x(Probe.view_eye(Voxel.Vec{9.5, 10.62, 9.5}, home))

def the_eye_is_shifted_into_the_region() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(close(eye_x_in(Probe.home_start()), 41.5), "the eye in the starting region is not 41.5")
    Unit <- check(close(eye_x_in(Probe.Home{2048n, 2048n}), 25.5), "the eye in a region a chunk before the pose's is not 25.5")
    Unit <- check(close(eye_x_in(Probe.Home{2049n, 2048n}), 9.5), "the eye in a region at the pose's chunk is not 9.5")
    Unit <- check(close(eye_x_in(Probe.Home{2050n, 2048n}), F32.neg(6.5)), "the eye in a region a chunk past the pose's is not -6.5")
    check(close(eye_x_in(Probe.Home{2046n, 2048n}), 57.5), "the eye in a region west of the origin is not 57.5")

def main() -> IO(Unit):
  do IO<Unit>:
    same_pose_is_clean()
    moved_eye_is_dirty()
    turned_camera_is_dirty()
    survival_change_is_clean()
    eye_is_the_player_plus_eye_height()
    eye_lands_inside_the_render_chunk()
    input_folds_key_events()
    input_releases_keys()
    input_ignores_unmapped_codes()
    input_holds_keys_across_frames()
    input_releases_across_frames()
    input_looks_down_when_the_mouse_goes_down()
    arrow_codes_are_the_runtime_translation()
    arrow_codes_are_four_different_keys()
    arrow_right_turns_right()
    arrow_left_turns_left()
    arrow_up_looks_up()
    arrow_down_looks_down()
    both_arrows_hold_still()
    the_rate_follows_the_tick()
    the_rate_is_the_number_it_says()
    no_arrow_no_turn()
    the_key_look_composes_with_the_mouse()
    input_does_not_look_on_a_move()
    input_turns_again_on_a_repeated_look()
    input_turns_by_the_look_delta()
    input_accumulates_look()
    region_is_multi_chunk()
    buttons_are_the_action_keys()
    keys_are_edges_and_not_levels()
    digging_is_a_level()
    region_follows_the_player()
    collision_region_keeps_the_player_inside()
    the_eye_is_shifted_into_the_region()
    player_tick_settles_on_the_region()
    seam_matches_render_size_at()
    idle_frames_skip_the_render()
    rebuild_skips_the_same_way()
    d_strafes_right()
    a_strafes_left()
    a_and_d_are_mirrors()
    held_input_dirties_the_frame()
    IO.print("frame-probe-test=pass")
