import Base
import ./voxel.bend as Voxel
import ./paint.bend as Paint
import ./hud.bend as Hud

# Tag: a name over a player's head.
#
# A room's players have names, and a figure in flat colours says nothing about whose it is.
# A tag is the name in the overlay's own dots — a letter is three dots wide and five high,
# like the hotbar's digits — on a dark plate, centred over where the player's head is in the
# frame. It is part of the overlay, not of the scene: it is painted ahead of every face, so a
# name shows through a wall, as the browser's does, and it is one size however far the
# player is. A name that would not fit whole inside the frame is not drawn, and neither is
# one behind the eye or further than the air lets a body be seen.

# What is written, and the point of the region it is written over.
type Label is Data:
  Label{text: String, x: F32, y: F32, z: F32}

# A letter of the alphabet, by its place in it, as fifteen bits read like `Hud.glyph`'s.
def letter(+index: U32) -> U32:
  Bool.pick(U32, U32.is_eq(index, 0), 23530,
    Bool.pick(U32, U32.is_eq(index, 1), 15083,
    Bool.pick(U32, U32.is_eq(index, 2), 25166,
    Bool.pick(U32, U32.is_eq(index, 3), 15211,
    Bool.pick(U32, U32.is_eq(index, 4), 29391,
    Bool.pick(U32, U32.is_eq(index, 5), 4815,
    Bool.pick(U32, U32.is_eq(index, 6), 27470,
    Bool.pick(U32, U32.is_eq(index, 7), 23533,
    Bool.pick(U32, U32.is_eq(index, 8), 29847,
    Bool.pick(U32, U32.is_eq(index, 9), 11044,
    Bool.pick(U32, U32.is_eq(index, 10), 23277,
    Bool.pick(U32, U32.is_eq(index, 11), 29257,
    Bool.pick(U32, U32.is_eq(index, 12), 23549,
    Bool.pick(U32, U32.is_eq(index, 13), 23403,
    Bool.pick(U32, U32.is_eq(index, 14), 11114,
    Bool.pick(U32, U32.is_eq(index, 15), 4843,
    Bool.pick(U32, U32.is_eq(index, 16), 28522,
    Bool.pick(U32, U32.is_eq(index, 17), 23275,
    Bool.pick(U32, U32.is_eq(index, 18), 14478,
    Bool.pick(U32, U32.is_eq(index, 19), 9367,
    Bool.pick(U32, U32.is_eq(index, 20), 31597,
    Bool.pick(U32, U32.is_eq(index, 21), 11117,
    Bool.pick(U32, U32.is_eq(index, 22), 24557,
    Bool.pick(U32, U32.is_eq(index, 23), 23213,
    Bool.pick(U32, U32.is_eq(index, 24), 9389,
    29351)))))))))))))))))))))))))

# The dots of a character. Small letters are drawn as capitals, and a character the font
# does not have is a space.
def glyph_of(+code: U32) -> U32:
  +upper = Bool.pick(U32, Bool.and(U32.is_ge(code, 97), U32.is_le(code, 122)), U32.sub(code, 32), code)
  Bool.pick(U32, Bool.and(U32.is_ge(code, 48), U32.is_le(code, 57)), Hud.glyph(U32.sub(code, 48)),
    Bool.pick(U32, Bool.and(U32.is_ge(upper, 65), U32.is_le(upper, 90)), letter(U32.sub(upper, 65)),
      Bool.pick(U32, U32.is_eq(code, 45), 448,
        Bool.pick(U32, U32.is_eq(code, 95), 28672,
          Bool.pick(U32, U32.is_eq(code, 46), 8192, 0)))))

def plate_color() -> U32:
  Voxel.rgb(24, 24, 28)

# How wide `count` characters are: three dots each and one between.
def width(+count: U32, +p: U32) -> U32:
  U32.sub(U32.mul(U32.mul(count, 4), p), p)

# The characters from (`x`, `y`), left to right.
def written(name: String, +x: U32, +y: U32, +p: U32, +size: U32, next: Paint.Quads) -> Paint.Quads:
  match name:
    case SNil{}:
      next
    case SCon{head, tail}:
      Hud.digit.go(15n, 0, glyph_of(Char.to_u32(head)), x, y, p, size,
        written(tail, U32.add(x, U32.mul(4, p)), y, p, size, next))

# A name with its first dot at (`x`, `y`), over a plate one dot wider all round. The dots
# come first: the frame is painted nearest first.
def plated(+name: String, +count: U32, +x: U32, +y: U32, +p: U32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  written(name, x, y, p, size,
    Paint.rect(U32.sub(x, p), U32.sub(y, p), U32.add(width(count, p), U32.mul(2, p)), U32.mul(7, p),
      plate_color(), size, next))

# Where a name's first dot goes for a point of the frame: the name is centred on it and
# stands on it.
def left_of(+sx: F32, +count: U32, +p: U32) -> U32:
  U32.sub(F32.to_u32(sx), U32.div(width(count, p), 2))

def top_of(+sy: F32, +p: U32) -> U32:
  U32.sub(F32.to_u32(sy), U32.mul(5, p))

def tag.at(shown: Bool, +name: String, +count: U32, +sx: F32, +sy: F32, +p: U32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  match shown:
    case False{}:
      next
    case True{}:
      plated(name, count, left_of(sx, count, p), top_of(sy, p), p, size, next)

# How far a name is read from, in cells.
def reach() -> F32:
  48.0

# Whether the whole tag is inside the frame, with a dot to spare all round.
def fits(+sx: F32, +sy: F32, +count: U32, +p: U32, +size: U32) -> Bool:
  +half = U32.to_f32(U32.add(U32.div(width(count, p), 2), U32.mul(2, p)))
  Bool.and(
    Bool.and(F32.is_ge(F32.sub(sx, half), 1.0), F32.is_lt(F32.add(sx, half), U32.to_f32(U32.sub(size, 1)))),
    Bool.and(F32.is_ge(F32.sub(sy, U32.to_f32(U32.mul(7, p))), 1.0),
      F32.is_lt(F32.add(sy, U32.to_f32(U32.mul(3, p))), U32.to_f32(U32.sub(size, 1)))))

# A name over a point already in view space: across, up and along the view from the eye.
def over(v: Paint.V, +name: String, +count: U32, +half: F32, +focal: F32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  Paint.V{+x, +y, +z} = v
  +ahead = F32.max(z, Paint.near_plane())
  +sx = Paint.screen_x(x, ahead, F32.sub(half, 0.5), focal)
  +sy = Paint.screen_y(y, ahead, F32.sub(half, 0.5), focal)
  tag.at(Bool.and(Bool.and(F32.is_gt(z, Paint.near_plane()), F32.is_lt(z, reach())),
      Bool.and(U32.is_gt(count, 0), fits(sx, sy, count, Hud.dot(size), size))),
    name, count, sx, sy, Hud.dot(size), size, next)

def quads.go(labels: List<&2, Label>, +camera: Voxel.Camera, +half: F32, +focal: F32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  match labels:
    case Nil{}:
      next
    case Label{+name, x, y, z} <> rest:
      quads.go(rest, camera, half, focal, size,
        over(Paint.seen(Voxel.Vec{x, y, z}, camera), name, U32.from_nat(String.length(name)), half,
          focal, size, next))

# Every label's dots and plate, for a frame of side `2^depth` seen from `eye`: what goes in
# the overlay, under the hotbar and the hand.
def quads(labels: List<&2, Label>, +eye: Voxel.Vec, +yaw: F32, +pitch: F32, +depth: Nat,
  next: Paint.Quads) -> Paint.Quads:
  quads.go(labels, Voxel.Camera.look(eye, yaw, pitch), Voxel.projection_half(depth),
    F32.mul(1.5, Voxel.projection_half(depth)), U32.shln((1 : U32), depth), next)
