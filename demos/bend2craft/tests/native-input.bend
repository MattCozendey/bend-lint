import Base
import ../world/world.bend as World
import ../native/world.bend as Game
import ../native/main.bend as NativeApp

def require(condition: Bool, message: String) -> IO(Unit):
  match condition:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "native-input: " ++ message)

def state_cursor_at_result(value: Maybe<Game.State>, x: U32, z: U32) -> Bool:
  match value:
    case None{}:
      False{}
    case Some{state}:
      Game.state.cursor_at(state, x, z)

def saved_cursor_matches(value: Maybe<&2, Game.Cursor>, x: U32, z: U32) -> Bool:
  match value:
    case None{}:
      False{}
    case Some{+cursor}:
      U32.is_eq(Game.cursor.x(cursor), x) && U32.is_eq(Game.cursor.z(cursor), z)

def image_is_color(image: Image, color: U32) -> Bool:
  match image:
    case Pix{actual}:
      U32.is_eq(actual, color)
    case _:
      False{}

def saved_edit_pixel_is_stone(+pixels: List<&2, U32>,
  value: Maybe<&2, Game.Cursor>) -> Bool:
  match value:
    case None{}:
      False{}
    case Some{+cursor}:
      +x = Game.cursor.x(cursor)
      +z = Game.cursor.z(cursor)
      image_is_color(Game.image.pixel(List.get(&2, U32, pixels,
        U32.to_nat((x + z * 16 : U32))), x, z, Game.Cursor{15, 15},
        Some{cursor}), Game.block_color(1))

def move_then_edit(state: Game.State) -> IO(Maybe<Game.State>):
  IO.bind(Maybe<Game.State>, Maybe<Game.State>,
    NativeApp.Native.tick([Key{119, True{}}], state),
    App.more(Game.State, state => NativeApp.Native.tick([Key{101, True{}}], state)))

def main() -> IO(Unit):
  do IO<Unit>:
    +pixels : List<&2, U32> = Game.surface(World.chunk(1337n, 0n, 0n))
    state : Game.State = Game.initial_state(
      pixels, None{}, "native/native-input-test-edit.bin")
    updated : Maybe<Game.State> <- move_then_edit(state)
    event_check : Unit <- require(state_cursor_at_result(updated, 8, 7),
      "W event did not move the cursor before the edit")
    +saved : Maybe<&2, Game.Cursor> <-
      Game.load_edit("native/native-input-test-edit.bin")
    file_check : Unit <- require(saved_cursor_matches(saved, 8, 7),
      "E event did not persist its cursor through Base File")
    image_check : Unit <- require(saved_edit_pixel_is_stone(pixels, saved),
      "reloaded event edit is not rendered as stone")
    IO.print("native-input: all assertions passed")

#|native-input: all assertions passed
