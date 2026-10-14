import Base
import ./voxel.bend as Voxel
import ./texture.bend as Texture

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "texture: " ++ message)

def red(+color: U32) -> U32:
  U32.and(U32.shrn(color, 16n), 255)

def green(+color: U32) -> U32:
  U32.and(U32.shrn(color, 8n), 255)

def blue(+color: U32) -> U32:
  U32.and(color, 255)

def brightness(+color: U32) -> U32:
  U32.add(U32.add(red(color), green(color)), blue(color))

# A texel is a rule, so the same block, side and place is the same colour every time, and a
# colour is three channels and nothing above them.
def a_texel_is_a_colour() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(Texture.texel(1, 1, 3, 9), Texture.texel(1, 1, 3, 9)),
      "the same texel is two colours")
    Unit <- check(U32.is_lt(Texture.texel(4, 0, 15, 15), 16777216),
      "a texel has bits above its three channels")
    check(U32.is_ne(Texture.texel(1, 1, 0, 0), Texture.texel(1, 1, 5, 11)),
      "stone is one flat colour: it has no texture")

# The side a face is on sets its light, as `Voxel.shade_color` does: a top is brighter than
# the same texel on a side that faces along x.
def the_top_is_brighter_than_a_side() -> IO(Unit):
  check(U32.is_gt(brightness(Texture.texel(6, 1, 4, 4)), brightness(Texture.texel(6, 0, 4, 4))),
    "sand's top is not brighter than its side")

# Grass is green from above, dirt from below, and from the side a green lip over dirt.
def grass_has_three_faces() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_gt(green(Texture.texel(3, 1, 7, 7)), red(Texture.texel(3, 1, 7, 7))),
      "the top of grass is not green")
    Unit <- check(U32.is_gt(red(Texture.texel(3, 4, 7, 7)), green(Texture.texel(3, 4, 7, 7))),
      "the bottom of grass is not dirt")
    Unit <- check(U32.is_gt(green(Texture.texel(3, 0, 7, 0)), red(Texture.texel(3, 0, 7, 0))),
      "the top row of grass's side is not green")
    check(U32.is_gt(red(Texture.texel(3, 0, 7, 12)), green(Texture.texel(3, 0, 7, 12))),
      "the lower rows of grass's side are not dirt")

# Cobblestone's joints are darker than its stones, and a made block's frame darker than its
# face.
def joints_and_frames_are_dark() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_lt(brightness(Texture.texel(22, 1, 5, 0)), brightness(Texture.texel(22, 1, 5, 2))),
      "a cobblestone joint is not darker than the stone beside it")
    check(U32.is_lt(brightness(Texture.texel(27, 1, 0, 5)), brightness(Texture.texel(27, 1, 5, 5))),
      "a crafting table's frame is not darker than its face")

# A scaled colour never runs a channel past 255 into the one above it.
def scaling_holds_each_channel() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(Texture.scaled(Voxel.rgb(200, 100, 50), 512), Voxel.rgb(255, 200, 100)),
      "doubling a colour did not hold the channel that overflowed")
    check(U32.is_eq(Texture.scaled(Voxel.rgb(200, 100, 50), 128), Voxel.rgb(100, 50, 25)),
      "halving a colour is wrong")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- a_texel_is_a_colour()
    Unit <- the_top_is_brighter_than_a_side()
    Unit <- grass_has_three_faces()
    Unit <- joints_and_frames_are_dark()
    Unit <- scaling_holds_each_channel()
    IO.print("texture: texels, light, grass, joints and scaling passed")
