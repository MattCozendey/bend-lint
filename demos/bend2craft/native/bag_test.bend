import Base
import ../world/inventory.bend as Inventory
import ../world/world_state.bend as WorldState
import ./bag.bend as Bag

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "bag: " ++ message)

def count_of(result: Inventory.InteractionResult, item: U32) -> U32:
  Inventory.InteractionResult{edit, slots, ok} = result
  Inventory.count(slots, item)

def ok_of(result: Inventory.InteractionResult) -> Bool:
  Inventory.InteractionResult{edit, slots, ok} = result
  ok

def block_of(result: Inventory.InteractionResult) -> U32:
  Inventory.InteractionResult{edit, slots, ok} = result
  WorldState.edit_value(edit)

def holding(+slot: Nat) -> Bag.Bag:
  Bag.Bag{Bag.slots_of(Bag.start()), slot, Bag.shut(), Bag.stores()}

# --- the starting bag -------------------------------------------------------------

def start_is_the_rules_plus_a_pickaxe() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(Bag.held_item(holding(0n)), 1), "slot 1 does not hold stone")
    Unit <- check(U32.is_eq(Inventory.count(Bag.slots_of(Bag.start()), 1), 32),
      "the bag does not start with the rules' 32 stone")
    check(U32.is_eq(Bag.held_item(holding(5n)), 19), "slot 6 does not hold the diamond pickaxe")

# --- selecting --------------------------------------------------------------------

def number_keys_select() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(Nat.is_eq(Bag.select([Key{51, True{}}], 0n), 2n), "pressing 3 did not select slot 3")
    Unit <- check(Nat.is_eq(Bag.select([Key{57, True{}}], 0n), 8n), "pressing 9 did not select slot 9")
    Unit <- check(Nat.is_eq(Bag.select([Key{51, False{}}], 0n), 0n), "releasing 3 selected a slot")
    Unit <- check(Nat.is_eq(Bag.select([Key{119, True{}}], 4n), 4n), "a movement key moved the selection")
    Unit <- check(Nat.is_eq(Bag.select([Key{48, True{}}], 4n), 4n), "pressing 0 moved the selection")
    check(Nat.is_eq(Bag.select([Key{50, True{}}, Key{53, True{}}], 0n), 4n),
      "two presses in one frame did not end on the later one")

# --- mining -----------------------------------------------------------------------
#
# The rules decide. Dirt comes away in a bare hand and lands in the bag; stone does not,
# and a refused dig must change nothing; with the pickaxe in hand stone comes away as stone
# and the pickaxe is worn by one use.

def hand_mines_dirt() -> IO(Unit):
  +result : Inventory.InteractionResult = Bag.mined(holding(6n), 2, 10n, 5n, 10n)
  do IO<Unit>:
    Unit <- check(ok_of(result), "a bare hand could not dig dirt")
    Unit <- check(U32.is_eq(block_of(result), 0), "digging did not ask for the cell to be emptied")
    check(U32.is_eq(count_of(result, 2), 25), "the dug dirt did not land in the bag")

def hand_cannot_mine_stone() -> IO(Unit):
  +result : Inventory.InteractionResult = Bag.mined(holding(6n), 1, 10n, 5n, 10n)
  do IO<Unit>:
    Unit <- check(Bool.not(ok_of(result)), "a bare hand broke stone, which the rules refuse")
    check(U32.is_eq(count_of(result, 1), 32), "a refused dig changed the bag")

def pickaxe_mines_stone() -> IO(Unit):
  +result : Inventory.InteractionResult = Bag.mined(holding(5n), 1, 10n, 5n, 10n)
  do IO<Unit>:
    Unit <- check(ok_of(result), "the pickaxe could not break stone")
    check(U32.is_eq(count_of(result, 1), 33), "the mined stone did not land in the bag")

# --- placing ----------------------------------------------------------------------
#
# Placing spends one of what is in hand and asks for that block at that cell. It is refused
# when the cell is taken, when the player is standing in it, and when the hand holds
# something that is not a block.

def placing_spends_one() -> IO(Unit):
  +result : Inventory.InteractionResult = Bag.placed(holding(1n), 10n, 5n, 10n, True{}, False{})
  do IO<Unit>:
    Unit <- check(ok_of(result), "dirt could not be placed in an empty cell")
    Unit <- check(U32.is_eq(block_of(result), 2), "placing dirt did not ask for a dirt block")
    check(U32.is_eq(count_of(result, 2), 23), "placing did not spend one dirt")

def placing_is_refused() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(Bool.not(ok_of(Bag.placed(holding(1n), 10n, 5n, 10n, False{}, False{}))),
      "a block was placed in a cell that was not empty")
    Unit <- check(Bool.not(ok_of(Bag.placed(holding(1n), 10n, 5n, 10n, True{}, True{}))),
      "a block was placed where the player stands")
    Unit <- check(Bool.not(ok_of(Bag.placed(holding(5n), 10n, 5n, 10n, True{}, False{}))),
      "a pickaxe was placed as a block")
    check(Bool.not(ok_of(Bag.placed(holding(8n), 10n, 5n, 10n, True{}, False{}))),
      "an empty hand placed a block")

# --- the item an item places ------------------------------------------------------

def items_place_their_blocks() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(Inventory.placed_block(1), 1), "stone does not place stone")
    Unit <- check(U32.is_eq(Inventory.placed_block(31), 22), "cobblestone does not place block 22")
    Unit <- check(U32.is_eq(Inventory.placed_block(10), 27), "a crafting table does not place block 27")
    Unit <- check(U32.is_eq(Inventory.placed_block(40), 25), "glass does not place block 25")
    Unit <- check(U32.is_eq(Inventory.placed_block(19), 0), "a pickaxe places a block")
    check(U32.is_eq(Inventory.placed_block(0), 0), "nothing places a block")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- start_is_the_rules_plus_a_pickaxe()
    Unit <- number_keys_select()
    Unit <- hand_mines_dirt()
    Unit <- hand_cannot_mine_stone()
    Unit <- pickaxe_mines_stone()
    Unit <- placing_spends_one()
    Unit <- placing_is_refused()
    Unit <- items_place_their_blocks()
    IO.print("bag: start, selection, mining, placing and placed blocks passed")
