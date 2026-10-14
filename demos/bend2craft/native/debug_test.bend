import Base
import ./debug.bend as Debug
import ./frame.bend as Frame
import ./size.bend as Size
import ./voxel.bend as Voxel
import ./paint.bend as Paint
import ../world/player.bend as Player

# The F3 overlay: what it says, and that its numbers are the ones it was given.
#
# The numbers are the point of this, so they are asserted as text built from the values
# rather than as a picture that happens to look right: a position that reads back as a
# different place, or a world cost that always reads zero because the measurement never
# reached the overlay, is a diagnostic that lies, and a lying diagnostic is worse than none.

def check(passed: Bool, message: String) -> IO(Unit):
  match passed:
    case True{}:
      IO.print("ok " ++ message)
    case False{}:
      IO.die(Unit, 1, "debug_test FAILED: " ++ message)

def holds(+lines: List<&2, String>, +needle: String) -> Bool:
  match lines:
    case Nil{}:
      False{}
    case +line <> rest:
      Bool.or(String.eq(line, needle), holds(rest, needle))

def count(+lines: List<&2, String>) -> U32:
  U32.from_nat(List.length(&2, String, lines))

def at(+x: F32, +y: F32, +z: F32) -> Player.State:
  Player.State{x, y, z, 0.0, 0.0, 0.0, True{}, F32.from_nat(20n), F32.from_nat(20n),
    F32.from_nat(10n), 0.0, 0.0}

# The overlay is quads on the frame, so it is read back out of a painted frame rather than
# assumed: a list of lines that never reaches the painter is a panel that is off, and only
# the pixels can tell that.
def frame_size() -> U32:
  256

def camera() -> Voxel.Camera:
  Voxel.Camera.look(Voxel.Vec{0.0, 0.0, 0.0}, 0.0, 0.0)

def frame(quads: Paint.Quads) -> Array<U32>:
  Paint.frame_pixels_with([], camera(), Voxel.projection_half(8n),
    F32.mul(1.5, Voxel.projection_half(8n)), frame_size(), 8n, quads, False{})

# A frame's pixels arrive as the array and one value out of it together, which is the same
# shape `native/hud_test.bend` reads the overlay back with.
def pixel(read: Array<U32> & U32) -> U32:
  (pixels, value) = read
  value

def column(read: Array<U32>, +x: U32, +y: U32) -> U32:
  pixel(read[U32.add(U32.mul(y, frame_size()), x)])

# The overlay is quads on the frame, so it is read back out of a painted frame rather than
# assumed: a list of lines that never reaches the painter is a panel that is off, and only
# the pixels can tell that. The pixel is inside the first row's plate, which starts at the
# corner and is eight dots tall and as wide as the line on it.
def corner(read: Array<U32>) -> U32:
  column(read, 5, 5)

def main() -> IO(Unit):
  do IO<Unit>:
    # The key itself. The runtime translates the function keys to `63236 + (ks - XK_F1)`,
    # so F3 arrives as 63238 and not as X11's keysym for it; a first version of this bound
    # the keysym, which the runtime never hands on, and the overlay could not be opened at
    # all with no error to say so. It is pinned here because that failure is silent.
    Unit <- check(U32.is_eq(Frame.debug_code(), 63238),
      "F3 is the code the runtime sends, not X11's keysym for it")
    # And it has to be a key of its own: a bit shared with another key would make F3 dig.
    Unit <- check(U32.is_eq(Frame.key_bit(Frame.debug_code()), 262144),
      "the overlay's key has a bit of its own")
    Unit <- check(Bool.not(Bool.or(
        U32.is_eq(Frame.key_bit(Frame.debug_code()), Frame.key_bit(Frame.dig_code())),
        U32.is_eq(Frame.key_bit(Frame.debug_code()), Frame.key_bit(Frame.save_code())))),
      "the overlay's key is not a key the client already acts on")
    +player : Player.State = at(F32.from_nat(25n), F32.from_nat(9n), F32.from_nat(16n))
    +home : Frame.Home = Frame.Home{3n, 4n}
    +size : Size.Size = Size.of_width((1024 : U32))
    +off : List<&2, String> = Debug.lines(False{}, player, home, 6, size, 4800)
    +on : List<&2, String> = Debug.lines(True{}, player, home, 6, size, 4800)
    Unit <- check(U32.is_eq(count(off), 0), "F3 off draws no lines")
    Unit <- check(U32.is_eq(count(on), 5), "F3 on draws its five lines")
    # The world cost is the reading this overlay exists for, so a measured cost has to
    # reach the text rather than being measured and dropped on the way.
    Unit <- check(holds(on, "WORLD 6 MS TICK 16.7"), "the measured world cost reaches the overlay")
    Unit <- check(Bool.not(holds(Debug.lines(True{}, player, home, 0, size, 4800), "WORLD 6 MS")),
      "a zero world cost does not read as the one that was measured")
    Unit <- check(holds(on, "HOME 3 4"), "the region's place is shown")
    Unit <- check(holds(on, "SIZE 1024"), "the window size is shown")
    Unit <- check(holds(on, "CLOCK 4800"), "the clock is shown")
    Unit <- check(holds(on, "XYZ 25.0 9.0 16.0"), "the position is shown to a tenth of a cell")
    # A position west of the origin is negative, and one that drops its sign reads as
    # somewhere the player is not.
    +west : Player.State = at(F32.from_nat(25n), F32.from_nat(9n), F32.neg(4.2))
    Unit <- check(holds(Debug.lines(True{}, west, home, 6, size, 4800), "XYZ 25.0 9.0 -4.2"),
      "a negative coordinate keeps its sign")
    sky_frame : Array<U32> = frame(Paint.QNil{})
    +sky : U32 = corner(sky_frame)
    painted_frame : Array<U32> = frame(Debug.quads(on, 2, frame_size(), Paint.QNil{}))
    lit : U32 = corner(painted_frame)
    Unit <- check(U32.is_ne(lit, sky), "the lines are painted onto the frame")
    hidden_frame : Array<U32> = frame(Debug.quads(off, 2, frame_size(), Paint.QNil{}))
    hidden : U32 = corner(hidden_frame)
    Unit <- check(U32.is_eq(hidden, sky), "an overlay that is off paints nothing")
    IO.print("debug_test ok")