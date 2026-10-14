import Base
import ../world/world.bend as World
import ../native/world.bend as Native

def require(condition: Bool, message: String) -> IO(Unit):
  match condition:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "native-world: " ++ message)

def matches_cursor(value: Maybe<&2, Native.Cursor>, x: U32, z: U32) -> Bool:
  match value:
    case None{}:
      False{}
    case Some{+cursor}:
      U32.is_eq(Native.cursor.x(cursor), x)
        && U32.is_eq(Native.cursor.z(cursor), z)

def image_leaf_count(image: Image) -> Nat:
  match image:
    case Pix{color}:
      1n
    case Qua{tl, tr, bl, br}:
      Nat.add(Nat.add(image_leaf_count(tl), image_leaf_count(tr)),
        Nat.add(image_leaf_count(bl), image_leaf_count(br)))

def view_leaf_count(pair: Native.State & Image) -> Nat:
  (state, image) = pair
  image_leaf_count(image)

def pixel_color_matches(image: Image, expected: U32) -> Bool:
  match image:
    case Pix{color}:
      U32.is_eq(color, expected)
    case _:
      False{}

def restored_edit_pixel_is_stone(+pixels: List<&2, U32>,
  value: Maybe<&2, Native.Cursor>) -> Bool:
  match value:
    case None{}:
      False{}
    case Some{+cursor}:
      +x = Native.cursor.x(cursor)
      +z = Native.cursor.z(cursor)
      pixel_color_matches(Native.image.pixel(List.get(&2, U32, pixels,
        U32.to_nat((x + z * 16 : U32))), x, z, Native.Cursor{15, 15},
        Some{cursor}), Native.block_color(1))

def world_pixel_matches(+pixels: List<&2, U32>, +x: U32, +z: U32) -> Bool:
  pixel_color_matches(
    Native.image.pixel(List.get(&2, U32, pixels,
      U32.to_nat((x + z * 16 : U32))), x, z, Native.Cursor{15, 15}, None{}),
    Native.block_color(World.block(1337n, U32.to_nat(x), 8n, U32.to_nat(z))))

def main() -> IO(Unit):
  do IO<Unit>:
    +pixels : List<&2, U32> = Native.surface(World.chunk(1337n, 0n, 0n))
    slice_check : Unit <- require(Native.surface_matches_world(pixels, 3, 4),
      "surface slice differs from World.block")
    pixel_check : Unit <- require(world_pixel_matches(pixels, 3, 4),
      "rendered pixel color differs from World.block")
    view_state : Native.State = Native.initial_state(
      pixels, None{}, "native/native-world-test-edit.bin")
    view_check : Unit <- require(Nat.is_eq(view_leaf_count(Native.view(view_state)), 256n),
      "view is not a 16 by 16 image")
    +moved : Native.Cursor = Native.move_cursor(Native.Cursor{3, 4}, 119)
    move_check : Unit <- require(matches_cursor(Some{moved}, 3, 3),
      "W input did not move the cursor north")
    encoded : List<&2, U32> = Native.cursor_bytes(moved)
    decoded : Maybe<&2, Native.Cursor> = Native.decode_cursor(encoded)
    decode_check : Unit <- require(matches_cursor(decoded, 3, 3),
      "cursor encoding did not round-trip")
    Native.save_edit("native/native-world-test-edit.bin", moved)
    +restored : Maybe<&2, Native.Cursor> <-
      Native.load_edit("native/native-world-test-edit.bin")
    file_check : Unit <- require(matches_cursor(restored, 3, 3),
      "Base File did not restore the saved cursor")
    image_check : Unit <- require(restored_edit_pixel_is_stone(pixels, restored),
      "restored edit is not visible as stone in the world slice")
    IO.print("native-world: all assertions passed")

#|native-world: all assertions passed
