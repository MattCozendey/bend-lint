import Base
import ./voxel.bend as Voxel
import ./paint.bend as Paint
import ./hud.bend as Hud
import ./tag.bend as Tag

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "tag: " ++ message)

# A letter is its dots, a small letter is its capital, a digit is the hotbar's own, and what
# the font does not have is a space.
def the_font_is_read() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(Tag.glyph_of(76), 29257), "an L is not a column and a foot")
    Unit <- check(U32.is_eq(Tag.glyph_of(108), Tag.glyph_of(76)), "a small l is not drawn as a capital")
    Unit <- check(U32.is_eq(Tag.glyph_of(55), Hud.glyph(7)), "a seven is not the hotbar's seven")
    Unit <- check(U32.is_eq(Tag.glyph_of(32), 0), "a space has dots")
    Unit <- check(U32.is_eq(Tag.glyph_of(233), 0), "a character the font does not have has dots")
    check(U32.is_ne(Tag.glyph_of(65), Tag.glyph_of(66)), "an A and a B are the same dots")

# A frame 256 pixels a side with no world in it, seen from the origin looking along -z, and
# one name over a point of it.
def size() -> U32:
  256

def pixel(read: Array<U32> & U32) -> U32:
  (frame, cell) = read
  cell

def at(+name: String, +z: F32, +x: U32, +y: U32) -> U32:
  pixel(Paint.frame_pixels_with([], Voxel.Camera.look(Voxel.Vec{0.0, 0.0, 0.0}, 0.0, 0.0),
    Voxel.projection_half(8n), F32.mul(1.5, Voxel.projection_half(8n)), size(), 8n,
    Tag.quads([Tag.Label{name, 0.0, 0.0, z}], Voxel.Vec{0.0, 0.0, 0.0}, 0.0, 0.0, 8n, Paint.QNil{}),
    False{})[U32.add(U32.mul(y, size()), x)])

def p() -> U32:
  Hud.dot(size())

# A point straight ahead is the middle of the frame.
def left(+count: U32) -> U32:
  Tag.left_of(127.5, count, p())

def top() -> U32:
  Tag.top_of(127.5, p())

# The name is written in white dots on a dark plate, centred over the point: an L's first
# dot is lit and the one beside it is the plate, and the plate reaches a dot past the name.
def a_name_is_written() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(at("L", F32.neg(5.0), left(1), top()), Hud.white()), "the first dot of an L is not lit")
    Unit <- check(U32.is_eq(at("L", F32.neg(5.0), U32.add(left(1), p()), top()), Tag.plate_color()), "the dot beside an L's column is not the plate")
    Unit <- check(U32.is_eq(at("L", F32.neg(5.0), U32.sub(left(1), p()), U32.sub(top(), p())), Tag.plate_color()), "the plate does not reach past the name")
    Unit <- check(U32.is_eq(at("AL", F32.neg(5.0), U32.add(left(2), U32.mul(4, p())), top()), Hud.white()), "the second letter is not four dots along")
    check(U32.is_ne(at("L", F32.neg(5.0), U32.sub(left(1), U32.mul(3, p())), top()), Tag.plate_color()), "the plate is wider than the name")

# No name is drawn behind the eye, past where a name is read from, or when it has no room.
def a_name_out_of_sight_is_not_written() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_ne(at("L", 5.0, left(1), top()), Hud.white()), "a name behind the eye is written")
    Unit <- check(U32.is_ne(at("L", F32.neg(80.0), left(1), top()), Hud.white()), "a name eighty cells off is written")
    Unit <- check(U32.is_ne(at("", F32.neg(5.0), 127, U32.sub(top(), p())), Tag.plate_color()), "no name has a plate")
    check(U32.is_ne(at("ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMNOPQRSTUVWXYZ", F32.neg(5.0), 127, top()), Tag.plate_color()),
      "a name wider than the frame is written")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- the_font_is_read()
    Unit <- a_name_is_written()
    Unit <- a_name_out_of_sight_is_not_written()
    IO.print("tag: the font, a name over its point and names out of sight passed")
