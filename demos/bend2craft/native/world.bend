import Base
import ../world/world.bend as World

type Cursor is Data:
  Cursor{x: U32, z: U32}

type State is Type:
  State{pixels: List<&2, U32>, cursor: Cursor, edited: Maybe<&2, Cursor>, path: String}

def cursor.x(cursor: Cursor) -> U32:
  Cursor{+x, +z} = cursor
  x

def cursor.z(cursor: Cursor) -> U32:
  Cursor{+x, +z} = cursor
  z

def cursor.at(cursor: Cursor, x: U32, z: U32) -> Bool:
  Cursor{+cursor_x, +cursor_z} = cursor
  U32.is_eq(cursor_x, x) && U32.is_eq(cursor_z, z)

def cursor.move(+code: U32, cursor: Cursor) -> Cursor:
  Cursor{+x, +z} = cursor
  +left = U32.is_eq(code, 97) || U32.is_eq(code, 63234)
  +right = U32.is_eq(code, 100) || U32.is_eq(code, 63235)
  +up = U32.is_eq(code, 119) || U32.is_eq(code, 63232)
  +down = U32.is_eq(code, 115) || U32.is_eq(code, 63233)
  +dx = Bool.pick(U32, left, 15, Bool.pick(U32, right, 1, 0))
  +dz = Bool.pick(U32, up, 15, Bool.pick(U32, down, 1, 0))
  Cursor{U32.and((x + dx : U32), 15), U32.and((z + dz : U32), 15)}

def move_cursor(cursor: Cursor, code: U32) -> Cursor:
  cursor.move(code, cursor)

def slice_index(x: U32, z: U32) -> U32:
  (2048 + z * 16 + x : U32)

def slice_block(blocks: Array<U32>, x: U32, z: U32) -> Array<U32> & U32:
  Array.get(U32, blocks, slice_index(x, z))

def set_slice_block(blocks: Array<U32>, x: U32, z: U32, block: U32) -> Array<U32>:
  Array.set(U32, blocks, slice_index(x, z), block)

def slice_equals(pair: Array<U32> & U32, expected: U32) -> Bool:
  (blocks, block) = pair
  U32.is_eq(block, expected)

def slice_is(blocks: Array<U32>, x: U32, z: U32, expected: U32) -> Bool:
  slice_equals(slice_block(blocks, x, z), expected)

def surface.matches(value: Maybe<&2, U32>, expected: U32) -> Bool:
  match value:
    case None{}:
      False{}
    case Some{block}:
      U32.is_eq(block, expected)

def surface.step(remaining: Nat, pair: Array<U32> & U32, index: U32,
  acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  match remaining, pair:
    case 0n, (blocks, block):
      (blocks, List.reverse(&2, U32, block <> acc))
    case 1n+p, (blocks, block):
      +next_index = U32.inc(index)
      surface.step(p, Array.get(U32, blocks, next_index), next_index, block <> acc)

def surface.pick(pair: Array<U32> & List<&2, U32>) -> List<&2, U32>:
  (blocks, pixels) = pair
  pixels

def surface(blocks: Array<U32>) -> List<&2, U32>:
  surface.pick(surface.step(255n, Array.get(U32, blocks, 2048), 2048, Nil{}))

def surface_matches_world(+pixels: List<&2, U32>, +x: U32, +z: U32) -> Bool:
  surface.matches(List.get(&2, U32, pixels,
    U32.to_nat((x + z * 16 : U32))),
    World.block(World.default_seed(), U32.to_nat(x), 8n, U32.to_nat(z)))

def cursor_bytes(cursor: Cursor) -> List<&2, U32>:
  Cursor{+x, +z} = cursor
  [x, z]

def decode_cursor.valid(+x: U32, +z: U32, valid: Bool) -> Maybe<&2, Cursor>:
  match valid:
    case True{}:
      Some{Cursor{x, z}}
    case False{}:
      None{}

def decode_cursor.end(+x: U32, +z: U32, rest: List<&2, U32>) -> Maybe<&2, Cursor>:
  match rest:
    case Nil{}:
      decode_cursor.valid(x, z, U32.is_lt(x, 16) && U32.is_lt(z, 16))
    case _:
      None{}

def decode_cursor.second(x: U32, rest: List<&2, U32>) -> Maybe<&2, Cursor>:
  match rest:
    case Nil{}:
      None{}
    case z <> tail:
      decode_cursor.end(x, z, tail)

def decode_cursor(bytes: List<&2, U32>) -> Maybe<&2, Cursor>:
  match bytes:
    case Nil{}:
      None{}
    case x <> rest:
      decode_cursor.second(x, rest)

def save_written(pair: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (file, result) = pair
  do IO<Unit>:
    unit : Unit <- IO.pass(Unit, result)
    File.close(file)

def save_edit(path: String, cursor: Cursor) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File, File.open(path, "w"))
    written : File & Result<&1, &1, U32 & String, Unit> <-
      File.write_bytes(file, cursor_bytes(cursor))
    save_written(written)

def load_read(pair: File & Result<&1, &1, U32 & String, List<&2, U32>>) ->
  IO(Maybe<&2, Cursor>):
  (file, result) = pair
  match result:
    case Fail{error}:
      do IO<Maybe<&2, Cursor>>:
        unit : Unit <- File.close(file)
        return None{}
    case Done{bytes}:
      do IO<Maybe<&2, Cursor>>:
        unit : Unit <- File.close(file)
        return decode_cursor(bytes)

def load_open(result: Result<&1, &1, U32 & String, File>) -> IO(Maybe<&2, Cursor>):
  match result:
    case Fail{error}:
      IO.pure(Maybe<&2, Cursor>, None{})
    case Done{file}:
      do IO<Maybe<&2, Cursor>>:
        bytes : File & Result<&1, &1, U32 & String, List<&2, U32>> <-
          File.read_bytes(file, 3)
        load_read(bytes)

def load_edit(path: String) -> IO(Maybe<&2, Cursor>):
  do IO<Maybe<&2, Cursor>>:
    result : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    load_open(result)

def edit_at(edited: Maybe<&2, Cursor>, x: U32, z: U32) -> Bool:
  match edited:
    case None{}:
      False{}
    case Some{cursor}:
      cursor.at(cursor, x, z)

def block_color(+block: U32) -> U32:
  Bool.pick(U32, U32.is_eq(block, 7), 3045823,
    Bool.pick(U32, U32.is_eq(block, 6), 14529124,
      Bool.pick(U32, U32.is_eq(block, 5), 10112063,
        Bool.pick(U32, U32.is_eq(block, 4), 2629176,
          Bool.pick(U32, U32.is_eq(block, 3), 4959975,
            Bool.pick(U32, U32.is_eq(block, 2), 8879718,
              Bool.pick(U32, U32.is_eq(block, 1), 8750469, 2236962)))))))

def image.pixel(value: Maybe<&2, U32>, +x: U32, +z: U32, +cursor: Cursor,
  +edited: Maybe<&2, Cursor>) -> Image:
  match value:
    case None{}:
      Pix{2236962}
    case Some{block}:
      +visible = Bool.pick(U32, edit_at(edited, x, z), 1, block)
      +selected = cursor.at(cursor, x, z)
      +color = Bool.pick(U32, selected, 16777215, block_color(visible))
      Pix{color}

def image(+depth: Nat, +pixels: List<&2, U32>, +x: U32, +z: U32,
  +cursor: Cursor, +edited: Maybe<&2, Cursor>) -> Image:
  match depth:
    case 0n:
      image.pixel(List.get(&2, U32, pixels,
        U32.to_nat((x + z * 16 : U32))), x, z, cursor, edited)
    case 1n+p:
      +half = U32.shln(1, p)
      tl tr bl br = image(p, pixels, x, z, cursor, edited)
        image(p, pixels, (x + half : U32), z, cursor, edited)
        image(p, pixels, x, (z + half : U32), cursor, edited)
        image(p, pixels, (x + half : U32), (z + half : U32), cursor, edited)
      Qua{tl, tr, bl, br}

def view(state: State) -> State & Image:
  State{+pixels, +cursor, +edited, +path} = state
  (State{pixels, cursor, edited, path}, image(4n, pixels, 0, 0, cursor, edited))

def state.cursor_at(state: State, x: U32, z: U32) -> Bool:
  State{pixels, cursor, edited, path} = state
  cursor.at(cursor, x, z)

def initial_state(pixels: List<&2, U32>, saved: Maybe<&2, Cursor>, path: String) -> State:
  match saved:
    case None{}:
      State{pixels, Cursor{8, 8}, None{}, path}
    case Some{+cursor}:
      State{pixels, cursor, Some{cursor}, path}

def start() -> IO(State):
  do IO<State>:
    blocks : Array<U32> = World.chunk(World.default_seed(), 0n, 0n)
    pixels : List<&2, U32> = surface(blocks)
    saved : Maybe<&2, Cursor> <- load_edit("native/native-edit.bin")
    return initial_state(pixels, saved, "native/native-edit.bin")

def move_state(state: State, code: U32) -> State:
  State{pixels, cursor, edited, path} = state
  State{pixels, cursor.move(code, cursor), edited, path}

def edit_state(state: State) -> IO(State):
  State{+pixels, +cursor, +edited, +path} = state
  do IO<State>:
    save_edit(path, cursor)
    return State{pixels, cursor, Some{cursor}, path}
