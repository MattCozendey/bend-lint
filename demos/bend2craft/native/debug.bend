import Base
import ./paint.bend as Paint
import ./frame.bend as Frame
import ./tag.bend as Tag
import ./size.bend as Size
import ./voxel.bend as Voxel
import ../world/player.bend as Player

# Debug: the diagnostics F3 puts on the window, in the same dots the players' names use.
#
# The browser's F3 is a DOM element, so this is not a copy of it but the same idea against
# what this client actually keeps: where the player is, where the view region is, what the
# last frame's world update cost, the clock and the window. It deliberately does not carry
# the browser's worker and mesh-rebuild lines, because this client has no workers and no
# mesh counter, and a line that always reads zero is worse than no line at all.
#
# `WORLD` is the one that matters. The client builds a chunk when one has come into view
# (`Slabs.world_for`), and that frame is dearer than the frames around it - measured at 6 ms
# against a 16.67 ms tick on the machine in `lab/native/client-probe/chunk_probe.bend`,
# single-threaded however wide the pool is. On a machine where the paint fits the tick and
# the frame rate still falls while walking, that is where the answer is, and it was
# invisible until this existed.

def plate_color() -> U32:
  Voxel.rgb(24, 24, 28)

# A signed position in tenths of a cell, as three or four characters. `U32.show` has no
# fixed width, so the fraction is taken as one digit rather than two: a position wants
# "12.5", not "12.50", and the dot the font already has sits between them.
def tenth_text(+value: F32) -> String:
  negative = F32.is_lt(value, 0.0)
  +absolute : F32 = F32.abs(value)
  +scaled : U32 = F32.to_u32(F32.mul(1000.0, absolute))
  +whole : U32 = U32.div(scaled, 1000)
  +tenth : U32 = U32.div(U32.mod(scaled, 1000), 100)
  +text : String = U32.show(whole) ++ "." ++ U32.show(tenth)
  Bool.pick(String, negative, "-" ++ text, text)

# --- the lines -----------------------------------------------------------------

def xyz_line(+player: Player.State) -> String:
  Player.State{x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall, poison} = player
  "XYZ " ++ tenth_text(x) ++ " " ++ tenth_text(y) ++ " " ++ tenth_text(z)

# What the last frame's world update cost. `TICK` is the 16.67 ms the runtime paces every
# presented frame to, so the two numbers are read against each other and not on their own.
def world_line(+world_ms: U32) -> String:
  "WORLD " ++ U32.show(world_ms) ++ " MS TICK 16.7"

# Where the view region is, in window chunks. This moves while the player walks, so it is
# the line that says whether a drop is the region coming into view or something else.
def home_line(+home: Frame.Home) -> String:
  Frame.Home{hx, hz} = home
  "HOME " ++ Nat.show(hx) ++ " " ++ Nat.show(hz)

def size_line(+size: Size.Size) -> String:
  "SIZE " ++ U32.show(Size.width_of(size))

def cons(head: String, tail: List<&2, String>) -> List<&2, String>:
  head <> tail

# The overlay's lines, or none at all. An empty list is what "F3 is off" means, so the
# painter needs no second flag to agree with.
def lines(shown: Bool, +player: Player.State, +home: Frame.Home, +world_ms: U32,
  +size: Size.Size, +clock: U32) -> List<&2, String>:
  match shown:
    case True{}:
      cons(xyz_line(player),
        cons(world_line(world_ms),
          cons(home_line(home),
            cons(size_line(size), cons("CLOCK " ++ U32.show(clock), [])))))
    case False{}:
      []

# --- the drawing ---------------------------------------------------------------

# How wide a run of `count` characters is, from `Tag`'s own measure, so a plate is exactly
# as wide as the text on it.
def width(+count: Nat, +p: U32) -> U32:
  U32.sub(U32.mul(U32.mul(U32.from_nat(count), 4), p), p)

# One row, its first dot at (`x`, `y`), over a plate one dot wider all round. The text is
# drawn after the plate so it reads over it.
def row(+line: String, +x: U32, +y: U32, +p: U32, +size: U32, next: Paint.Quads) -> Paint.Quads:
  +count : Nat = String.length(line)
  Tag.written(line, x, y, p, size,
    Paint.rect(U32.sub(x, p), U32.sub(y, p), U32.add(width(count, p), U32.mul(2, p)),
      U32.mul(8, p), plate_color(), size, next))

# The rows down the frame, each a line's five dots plus a gap's three.
def rows.go(remaining: Nat, +lines: List<&2, String>, +x: U32, +y: U32, +p: U32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  match remaining:
    case 0n:
      next
    case 1n+r:
      match lines:
        case Nil{}:
          next
        case +line <> rest:
          row(line, x, y, p, size,
            rows.go(r, rest, x, U32.add(y, U32.mul(8, p)), p, size, next))

# The overlay, in the frame's top-left corner. It goes in the same list as the hand, the
# hotbar and the hearts, ahead of them so it is painted first and they stay on top.
def quads(+lines: List<&2, String>, +p: U32, +size: U32, next: Paint.Quads) -> Paint.Quads:
  rows.go(List.length(&2, String, lines), lines, p, p, p, size, next)