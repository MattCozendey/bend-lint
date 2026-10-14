import Base
import ./bag.bend as Bag
import ./frame.bend as Frame
import ../world/inventory.bend as Inventory
import ../world/world.bend as World
import ../world/digging.bend as Digging
import ../world/player.bend as Player
import ./player.bend as PlayerProbe
import ./screen.bend as Screen
import ./stores.bend as Stores
import ../world/world_state.bend as WorldState

# What the player's hands do to the world: the cell the ray meets as the world's own cell
# (`Aim`), what a dig and a placing do to the edit log and the bag, which blocks open a screen,
# and one tick of a dig. The rules are `world/inventory.bend`'s, `world/digging.bend`'s and
# `native/bag.bend` applies them; what is here is deciding which cell, and turning the rules'
# answer into the next edits and bag (`Turn`).

# --- targeting ---------------------------------------------------------------

# `Player.raycast` answers in the encoded window, so the aim state is rebuilt
# from the pose instead of taking the player the tick owns.
#
# The eye goes back into that window by the origin the pose was taken from,
# `Frame.origin_x`, and not by the region's own origin. The two were the same number
# while the collision region started at the pose's chunk; the region now starts a chunk
# earlier, and reading its origin here aimed sixteen cells away from where the player
# was looking.
def aim_cast(+pose: Frame.Pose, +blocks: List<&2, List<&2, U32>>, +origin_x: Nat, +origin_y: Nat,
  +origin_z: Nat, +width: Nat, +height: Nat, +depth: Nat) -> Player.RayResult:
  +eye = Frame.eye_of(pose)
  +x = F32.add(Frame.eye_x(eye), F32.from_nat(Frame.origin_x()))
  +y = F32.sub(Frame.eye_y(eye), Frame.eye_height())
  +z = F32.add(Frame.eye_z(eye), F32.from_nat(Frame.origin_z()))
  Player.raycast(Player.state(x, y, z, Frame.yaw_of(pose), Frame.pitch_of(pose), 0.0,
    False{}, 20.0, 20.0), blocks, origin_x, origin_y, origin_z, width, height, depth)

def aimed(+pose: Frame.Pose, region: PlayerProbe.Region) -> Player.RayResult:
  PlayerProbe.Region{+blocks, +origin_x, +origin_y, +origin_z, +width, +height, +depth} = region
  aim_cast(pose, blocks, origin_x, origin_y, origin_z, width, height, depth)

# A cell as `WorldState` spells it: a stored cell, which is what an edit and the rules name.
type Cell is Data:
  Cell{x: Nat, y: Nat, z: Nat}

def cell_of(mx: Maybe<&1, Nat>, mz: Maybe<&1, Nat>, +y: Nat) -> Maybe<&2, Cell>:
  match mx mz:
    case Some{sx} Some{sz}:
      Some{Cell{sx, y, sz}}
    case _ _:
      None{}

# What the player's ray meets, in the world's own cells: the block it hit, the cell the face
# it hit opens onto, whether the rules let something stand there (`has_place`), and whether
# the player does (`overlaps`). A cell the storage encoding cannot name is no cell, which is
# the far edge of the world: the ray hit nothing there, and the player meets it as a wall.
type Aim is Data:
  Aim{hit: Maybe<&2, Cell>, place: Maybe<&2, Cell>, has_place: Bool, overlaps: Bool}

def aim.of(result: Player.RayResult, player: Player.State) -> Aim:
  match result:
    case Player.NoHit{}:
      Aim{None{}, None{}, False{}, False{}}
    case Player.Hit{hit_x, hit_y, hit_z, +place_x, +place_y, +place_z, has_place}:
      Aim{cell_of(PlayerProbe.stored_cell(hit_x), PlayerProbe.stored_cell(hit_z), hit_y),
        cell_of(PlayerProbe.stored_cell(place_x), PlayerProbe.stored_cell(place_z), place_y),
        has_place, Player.overlaps(player, place_x, place_y, place_z)}

# --- edits -------------------------------------------------------------------

# What a tick's action left: the edit log and the bag, both as the rules answered.
type Turn is Data:
  Turn{edits: List<&2, WorldState.Edit>, bag: Bag.Bag}

def turn_edits(turn: Turn) -> List<&2, WorldState.Edit>:
  Turn{edits, bag} = turn
  edits

def turn_bag(turn: Turn) -> Bag.Bag:
  Turn{edits, bag} = turn
  bag

def turn.applied(ok: Bool, edit: WorldState.Edit, +edits: List<&2, WorldState.Edit>,
  bag: Bag.Bag) -> Turn:
  match ok:
    case True{}:
      WorldState.Edit{x, y, z, block} = edit
      Turn{WorldState.set(edits, x, y, z, block), bag}
    case False{}:
      Turn{edits, bag}

# The rules' answer, applied: the edit joins the log only when the rules allowed the
# action, and the bag is the slots they handed back either way.
def turn.done(result: Inventory.InteractionResult, bag: Bag.Bag,
  +edits: List<&2, WorldState.Edit>) -> Turn:
  Inventory.InteractionResult{edit, slots, ok} = result
  turn.applied(ok, edit, edits, Bag.with_slots(bag, slots))

# The turn after a dig, with the chest or the furnace that stood in the cell forgotten when
# the cell is now air.
def dig.cleared(turn: Turn, +block: U32, +x: Nat, +y: Nat, +z: Nat) -> Turn:
  Turn{+edits, +bag} = turn
  Turn{edits, Bool.pick(Bag.Bag, U32.is_eq(WorldState.block(edits, Frame.seed(), x, y, z), 0),
    Bag.with_store(bag, Stores.forgot(Bag.store_of(bag), block, x, y, z)), bag)}

def dig.cell(locked: Bool, +block: U32, +x: Nat, +y: Nat, +z: Nat, +edits: List<&2, WorldState.Edit>,
  +bag: Bag.Bag) -> Turn:
  match locked:
    case True{}:
      Turn{edits, bag}
    case False{}:
      dig.cleared(turn.done(Bag.mined(bag, block, x, y, z), bag, edits), block, x, y, z)

# Digging takes the block the ray hit, with what is in hand, and the rules decide whether
# it comes away and what lands in the bag. A chest that still holds something stays.
def dig.at(hit: Maybe<&2, Cell>, +edits: List<&2, WorldState.Edit>, +bag: Bag.Bag) -> Turn:
  match hit:
    case Some{Cell{+x, +y, +z}}:
      +block : U32 = WorldState.block(edits, Frame.seed(), x, y, z)
      dig.cell(Stores.locked(Bag.store_of(bag), block, x, y, z), block, x, y, z, edits, bag)
    case None{}:
      Turn{edits, bag}

# Building puts what is in hand in the cell the ray says the hit face opens onto, and
# touches no other cell. It used to dig the cell it hit as well, on the theory that the two
# actions should agree about the hit: that is the block beside, below or behind the new one
# vanishing every time a block was placed.
def place.at(place: Maybe<&2, Cell>, has_place: Bool, overlaps: Bool,
  +edits: List<&2, WorldState.Edit>, +bag: Bag.Bag) -> Turn:
  match place has_place:
    case Some{Cell{+x, +y, +z}} True{}:
      turn.done(Bag.placed(bag, x, y, z,
          U32.is_eq(WorldState.block(edits, Frame.seed(), x, y, z), 0), overlaps),
        bag, edits)
    case _ _:
      Turn{edits, bag}

# The screen a block opens under the place key, or 0. They open in a room as out of one: a
# room's chest is the room's, and its screen asks the room for each move (`Stores`).
def opens(+block: U32) -> U32:
  Bool.pick(U32, U32.is_eq(block, World.crafting_table_block()), Screen.table(),
    Bool.pick(U32, U32.is_eq(block, World.chest_block()), Screen.chest(),
      Bool.pick(U32, U32.is_eq(block, World.furnace_block()), Screen.furnace(), 0)))

# The place key on a block with a screen opens it, and places nothing; on anything else it
# places what is in hand beside the block the ray hit.
def built.used(opening: Bool, +mode: U32, +x: Nat, +y: Nat, +z: Nat, place: Maybe<&2, Cell>,
  has_place: Bool, overlaps: Bool, +edits: List<&2, WorldState.Edit>, +bag: Bag.Bag,
  +size: U32) -> Turn:
  match opening:
    case True{}:
      Turn{edits, Screen.opened_at(bag, mode, x, y, z, size)}
    case False{}:
      place.at(place, has_place, overlaps, edits, bag)

def built.at(aim: Aim, +edits: List<&2, WorldState.Edit>, +bag: Bag.Bag, +size: U32) -> Turn:
  match aim:
    case Aim{Some{Cell{+x, +y, +z}}, place, has_place, overlaps}:
      +mode : U32 = opens(WorldState.block(edits, Frame.seed(), x, y, z))
      built.used(U32.is_ne(mode, 0), mode, x, y, z, place, has_place, overlaps, edits, bag, size)
    case Aim{None{}, place, has_place, overlaps}:
      place.at(place, has_place, overlaps, edits, bag)

def dug(aim: Aim, +edits: List<&2, WorldState.Edit>, +bag: Bag.Bag) -> Turn:
  match aim:
    case Aim{hit, place, has_place, overlaps}:
      dig.at(hit, edits, bag)

def acted(+edits: List<&2, WorldState.Edit>, +bag: Bag.Bag, +pose: Frame.Pose,
  region: PlayerProbe.Region, player: Player.State, digging: Bool, building: Bool,
  +size: U32) -> Turn:
  match digging building:
    case True{} False{}:
      dug(aim.of(aimed(pose, region), player), edits, bag)
    case False{} True{}:
      built.at(aim.of(aimed(pose, region), player), edits, bag, size)
    case _ _:
      Turn{edits, bag}

# --- digging takes time ---------------------------------------------------------
#
# One more tick on the block the ray meets: `world/digging.bend` decides what it comes to.
def mining.hit(aim: Aim, dig: Digging.Dig, +edits: List<&2, WorldState.Edit>, +item: U32) -> Digging.Mined:
  match aim:
    case Aim{Some{Cell{+x, +y, +z}}, place, has_place, overlaps}:
      Digging.step(WorldState.block(edits, Frame.seed(), x, y, z), x, y, z, dig, item, Frame.tick_dt())
    case Aim{None{}, place, has_place, overlaps}:
      Digging.refused()

# The dig after one tick. With the button up there is none; held, the ray is cast and the
# block it meets is a tick nearer to coming away.
def mining(holding: Bool, dig: Digging.Dig, +pose: Frame.Pose, region: PlayerProbe.Region,
  player: Player.State, +edits: List<&2, WorldState.Edit>, +item: U32) -> Digging.Mined:
  match holding:
    case False{}:
      Digging.refused()
    case True{}:
      mining.hit(aim.of(aimed(pose, region), player), dig, edits, item)
