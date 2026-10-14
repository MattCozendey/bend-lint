# LAWS.bend: the rules of Bend2Craft the checker proves. `PROOF.bend` closes each
# one, and `npm run proof` is the gate.
#
# Two kinds of law live here. A law with a `for` holds for **every** value of what
# it names: every log, every bag, every coordinate. A law without one is a value
# the game depends on, computed by the checker from the same definition the game
# runs. The checker computes integers, booleans and lists; it does not compute
# floats, so the player's physics is held by the tests and not stated here.

import Base
import ./world.bend as World
import ./world_state.bend as WorldState
import ./inventory.bend as Inventory
import ./equipment.bend as Equipment
import ./furnace.bend as Furnace
import ./chest.bend as Chest
import ./farmland.bend as Farmland
import ./crops.bend as Crops
import ./experience.bend as Experience
import ./light.bend as Light
import ./fluids.bend as Fluids
import ./fire.bend as Fire
import ./redstone.bend as Redstone
import ./player.bend as Player
import ./entities.bend as Entities
import ./digging.bend as Digging

# --- what the laws read out of a result ----------------------------------------

def slots(xs: List<&2, Inventory.Slot>) -> Nat:
  List.length(&2, Inventory.Slot, xs)

def interaction_slots(r: Inventory.InteractionResult) -> List<&2, Inventory.Slot>:
  Inventory.InteractionResult{edit, slots, ok} = r
  slots

def interaction_ok(r: Inventory.InteractionResult) -> Bool:
  Inventory.InteractionResult{edit, slots, ok} = r
  ok

def furnace_of(r: Furnace.FurnaceResult) -> Furnace.Furnace:
  Furnace.FurnaceResult{furnace, ok} = r
  furnace

def furnace_ok(r: Furnace.FurnaceResult) -> Bool:
  Furnace.FurnaceResult{furnace, ok} = r
  ok

def step_ok(r: Furnace.StepResult) -> Bool:
  Furnace.StepResult{furnace, produced, ok} = r
  ok

def transfer_furnace(r: Furnace.TransferResult) -> Furnace.Furnace:
  Furnace.TransferResult{furnace, item, amount, ok} = r
  furnace

def transfer_ok(r: Furnace.TransferResult) -> Bool:
  Furnace.TransferResult{furnace, item, amount, ok} = r
  ok

def farm_plots(r: Farmland.FarmResult) -> List<&2, Farmland.Plot>:
  Farmland.FarmResult{state, ok} = r
  Farmland.entries(state)

def crop_ok(r: Crops.CropResult) -> Bool:
  Crops.CropResult{state, ok} = r
  ok

def harvest_yield(r: Crops.HarvestResult) -> U32 & (U32 & Bool):
  Crops.HarvestResult{state, seeds, wheat, ok} = r
  (seeds, (wheat, ok))

# --- the generated world ---------------------------------------------------------
# The cells the first eleven laws name are the default seed's, and each is the
# block the terrain rule must put there: if the rule moves, the world the saves
# were made in is not the world they load into.

law air_above_surface:
  {World.block(1337n, 40n, 15n, 40n) == 0 : U32}

law surface_is_grass:
  {World.block(1337n, 20n, 8n, 20n) == 3 : U32}

law known_tree_wood:
  {World.block(1337n, 14n, 9n, 6n) == 5 : U32}

law known_tree_leaf:
  {World.block(1337n, 13n, 11n, 5n) == 4 : U32}

law beach_is_sand:
  {World.block(1337n, 3n, 5n, 3n) == 6 : U32}

law sea_surface_is_water:
  {World.block(1337n, 3n, 7n, 3n) == 7 : U32}

# A cave cell is air, and its neighbour in the same pocket is too: caves run,
# they are not single punched holes. The cell moved with the 3D cave rule on
# 2026-10-03; the rule behind the law did not.
law cave_is_air:
  {World.block(1337n, 36n, 5n, 40n) == 0 : U32}

law caves_run:
  {World.block(1337n, 37n, 5n, 40n) == 0 : U32}

# The rule is selective: solid ground still stands next to that pocket.
law ground_beside_a_cave_is_solid:
  {World.block(1337n, 32n, 5n, 32n) == 6 : U32}

law known_coal_ore:
  {World.block(1337n, 0n, 3n, 26n) == 8 : U32}

law known_iron_ore:
  {World.block(1337n, 26n, 4n, 84n) == 9 : U32}

law known_diamond_ore:
  {World.block(1337n, 14n, 1n, 85n) == 10 : U32}

# Ores generate in the bands of the column they are in, and the bands are the
# fractions of the column that vanilla's ore table gives over a world of its
# depth: diamond in the bottom quarter, coal and iron through the whole column.
#
# `World.ore_band` is one line, so a law with a `for` over it would only restate
# that line: it would hold for every column and every cell while saying nothing
# about a world, which is the definition and not a fact. The bands are therefore
# held as values, at named heights. The placement, the density and the clumping —
# what a digger actually feels — are held by tests/ore-distribution.test.mjs,
# because `Nat.mod` and `Nat.div` do not reduce on a variable and the checker
# cannot decide them.
law the_diamond_band_is_the_first_quarter_of_a_twelve_cell_column:
  {List.map(~Nat, ~Bool, ~(y => World.ore_band(10, y, 12n)), [0n, 2n, 3n, 4n, 12n, 13n])
    == [True{}, True{}, True{}, False{}, False{}, False{}] : List<Bool>}

# And that quarter is a quarter: of a column eight cells tall the band reaches the
# second cell and not the seventh, and of twelve it reaches the third.
law the_diamond_band_is_a_quarter_of_the_column:
  {List.map(~Nat, ~Bool, ~(h => World.ore_band(10, 2n, h)), [7n, 8n, 11n, 12n]) == [False{}, True{}, True{}, True{}] : List<Bool>}

law the_diamond_band_stops_at_the_quarter:
  {List.map(~Nat, ~Bool, ~(h => World.ore_band(10, 7n, h)), [8n, 16n, 27n, 28n]) == [False{}, False{}, False{}, True{}] : List<Bool>}

# Coal and iron have no band of their own, so they generate through the whole
# column however tall it is and however deep the cell: seven cells up in a
# four-cell column, both still generate and diamond does not.
law only_diamond_has_a_band_of_its_own:
  {List.map(~U32, ~Bool, ~(ore => World.ore_band(ore, 7n, 4n)), [8, 9, 10]) == [True{}, True{}, False{}] : List<Bool>}

# A vein's reach is its ore's size: seven cells for diamond, and a pocket of coal
# or iron larger than that.
law a_vein_is_the_size_its_ore_gives_it:
  {List.map(~U32, ~Nat, ~(ore => World.ore_reach(ore)), [8, 9, 10]) == [2n, 2n, 1n] : List<Nat>}

# The lattice cells of one row of the default seed's world, in the order the
# thresholds place them: no ore, coal, iron and diamond all appear, and the
# rarer an ore the fewer cells hold it.
law the_veins_are_placed_in_the_order_of_rarity:
  {List.map(~Nat, ~U32, ~(cell => World.ore_vein_of(1337n, World.mix(1337n, cell, 0n), 0n)), [0n, 1n, 2n, 3n, 4n, 5n, 6n, 7n, 8n, 9n, 10n, 11n])
    == [1, 1, 8, 9, 8, 10, 1, 8, 1, 1, 10, 1] : List<U32>}

law known_village_furnace:
  {World.block(1337n, 25n, 9n, 27n) == 11 : U32}

# A chunk's 16 x 16 x 20 cells fit the 8192 slots `World.chunk` allocates.
law a_chunk_holds_its_cells:
  {Nat.is_le(Nat.mul(Nat.mul(World.chunk_size(), World.chunk_size()), World.max_y()), 16384n) == True{} : Bool}

# Cells below the origin are stored at `World.negative_origin()` + x. That number
# is 94371840, and it is a multiple of every period the terrain formulas reduce a
# coordinate by, which is what makes the world continue across the origin without
# a seam. The checker counts a `Nat` out in unary, so the number is said as a word.
law the_origin_shift_is_a_whole_number_of_terrain_periods:
  {List.map(~U32, ~U32, ~(period => U32.mod(94371840, period)), [24, 18, 48, 40, 32, 4096])
    == [0, 0, 0, 0, 0, 0] : List<U32>}

# For every column height and every cell at or above it, the terrain rule answers air.
law above_a_column_is_air:
  for +h: Nat
  for +k: Nat
  {World.terrain_block_height(h, Nat.add(h, k)) == 0 : U32}

# For every column, its top block is sand at or below the sea and grass above it.
law the_surface_is_sand_by_the_sea_and_grass_above:
  for +h: Nat
  {World.terrain_block_height(1n+h, h) == Bool.pick(U32, Nat.is_le(1n+h, World.sea_level()), 6, 3) : U32}

# For every column, no cell above sea level is generated as water.
law no_generated_water_above_the_sea:
  for +h: Nat
  for +k: Nat
  {World.water_at_height(h, Nat.add(1n+World.sea_level(), k)) == False{} : Bool}

# --- the edit log ------------------------------------------------------------------
# The log is the whole of what a player changed, and `WorldState.block` is how
# every reader — the renderer, the collision, the save — sees it. These three laws
# are its contract, for every log, seed, cell and block.

law an_empty_log_is_the_generated_world:
  for +seed: Nat
  for +x: Nat
  for +y: Nat
  for +z: Nat
  {WorldState.block(WorldState.empty(), seed, x, y, z) == World.block(seed, x, y, z) : U32}

law an_edit_reads_back:
  for +edits: List<&2, WorldState.Edit>
  for +seed: Nat
  for +x: Nat
  for +y: Nat
  for +z: Nat
  for +block: U32
  {WorldState.block(WorldState.set(edits, x, y, z, block), seed, x, y, z) == block : U32}

# `apart` says the two cells differ: the new entry is not an entry of (ox, oy, oz).
law an_edit_keeps_every_other_cell:
  for +edits: List<&2, WorldState.Edit>
  for +seed: Nat
  for +x: Nat
  for +y: Nat
  for +z: Nat
  for +block: U32
  for +ox: Nat
  for +oy: Nat
  for +oz: Nat
  for +apart: {WorldState.edit_matches(WorldState.make_edit(x, y, z, block), ox, oy, oz) == False{} : Bool}
  {WorldState.block(WorldState.set(edits, x, y, z, block), seed, ox, oy, oz) == WorldState.block(edits, seed, ox, oy, oz) : U32}

# In a batch, the last edit of a cell is the one that stays.
law the_last_edit_of_a_batch_wins:
  {WorldState.block(WorldState.set_many(WorldState.empty(),
      [WorldState.make_edit(1n, 2n, 3n, 5), WorldState.make_edit(4n, 2n, 3n, 6), WorldState.make_edit(1n, 2n, 3n, 9)]),
    1337n, 1n, 2n, 3n) == 9 : U32}

# --- the inventory: a refused action changes nothing ---------------------------------
# For every bag, slot, item and cell.

law mining_the_bottom_layer_is_refused:
  for +bag: List<&2, Inventory.Slot>
  for +tool: U32
  for +block: U32
  {Inventory.mine_collect(bag, tool, block, 0n) == Inventory.result(bag, False{}) : Inventory.InventoryResult}

law placing_into_an_occupied_cell_is_refused:
  for +bag: List<&2, Inventory.Slot>
  for +index: Nat
  for +item: U32
  for +inside: Bool
  for +over: Bool
  {Inventory.place(bag, index, item, False{}, inside, over) == Inventory.result(bag, False{}) : Inventory.InventoryResult}

law placing_outside_the_world_is_refused:
  for +bag: List<&2, Inventory.Slot>
  for +index: Nat
  for +item: U32
  for +empty: Bool
  for +over: Bool
  {Inventory.place(bag, index, item, empty, False{}, over) == Inventory.result(bag, False{}) : Inventory.InventoryResult}

law placing_into_the_player_is_refused:
  for +bag: List<&2, Inventory.Slot>
  for +index: Nat
  for +item: U32
  for +empty: Bool
  for +inside: Bool
  {Inventory.place(bag, index, item, empty, inside, True{}) == Inventory.result(bag, False{}) : Inventory.InventoryResult}

law consuming_nothing_is_refused:
  for +bag: List<&2, Inventory.Slot>
  for +index: Nat
  {Inventory.consume(bag, index, 0n) == Inventory.result(bag, False{}) : Inventory.InventoryResult}

law moving_a_slot_onto_itself_is_refused:
  for +bag: List<&2, Inventory.Slot>
  for +index: Nat
  for +amount: Nat
  {Inventory.move(bag, index, index, amount) == Inventory.result(bag, False{}) : Inventory.InventoryResult}

law crafting_past_the_recipes_is_refused:
  for +bag: List<&2, Inventory.Slot>
  for +k: Nat
  {Inventory.craft(bag, Nat.add(25n, k)) == Inventory.result(bag, False{}) : Inventory.InventoryResult}

# The two calls the clients make. Whatever made the action fail — the wrong tool, a
# full bag, a worn-out pickaxe, an occupied cell — the bag that comes back is the
# bag that went in.
law a_refused_mining_keeps_the_bag:
  for +bag: List<&2, Inventory.Slot>
  for +index: Nat
  for +tool: U32
  for +block: U32
  for +x: Nat
  for +y: Nat
  for +z: Nat
  for h: {interaction_ok(Inventory.mine_interaction_at(bag, index, tool, block, x, y, z)) == False{} : Bool}
  {interaction_slots(Inventory.mine_interaction_at(bag, index, tool, block, x, y, z)) == bag : List<&2, Inventory.Slot>}

law a_refused_placing_keeps_the_bag:
  for +bag: List<&2, Inventory.Slot>
  for +index: Nat
  for +item: U32
  for +block: U32
  for +x: Nat
  for +y: Nat
  for +z: Nat
  for +empty: Bool
  for +inside: Bool
  for +over: Bool
  for h: {interaction_ok(Inventory.place_interaction(bag, index, item, block, x, y, z, empty, inside, over)) == False{} : Bool}
  {interaction_slots(Inventory.place_interaction(bag, index, item, block, x, y, z, empty, inside, over)) == bag : List<&2, Inventory.Slot>}

# --- the inventory: a bag never grows or shrinks ---------------------------------------
# For every bag: adding, removing, mining and placing answer a bag of as many slots.

law adding_items_keeps_the_slots:
  for +bag: List<&2, Inventory.Slot>
  for +item: U32
  for +amount: U32
  {slots(Inventory.add_slots(Inventory.add_items(bag, item, amount))) == slots(bag) : Nat}

law removing_items_keeps_the_slots:
  for bag: List<&2, Inventory.Slot>
  for +item: U32
  for +amount: U32
  {slots(Inventory.remove_slots(Inventory.remove_items(bag, item, amount))) == slots(bag) : Nat}

law mining_keeps_the_slots:
  for +bag: List<&2, Inventory.Slot>
  for +index: Nat
  for +tool: U32
  for +block: U32
  for +x: Nat
  for +y: Nat
  for +z: Nat
  {slots(interaction_slots(Inventory.mine_interaction_at(bag, index, tool, block, x, y, z))) == slots(bag) : Nat}

law placing_keeps_the_slots:
  for +bag: List<&2, Inventory.Slot>
  for +index: Nat
  for +item: U32
  for +block: U32
  for +x: Nat
  for +y: Nat
  for +z: Nat
  for +empty: Bool
  for +inside: Bool
  for +over: Bool
  {slots(interaction_slots(Inventory.place_interaction(bag, index, item, block, x, y, z, empty, inside, over))) == slots(bag) : Nat}

law an_empty_bag_has_the_slots_asked_for:
  for +n: Nat
  {slots(Inventory.empty_slots(n)) == n : Nat}

# --- the inventory: the tables the game depends on --------------------------------------

law the_starting_bag_has_thirty_six_slots:
  {slots(Inventory.create()) == Inventory.slot_count() : Nat}

law the_starting_bag_holds_stone_dirt_grass_leaves_and_wood:
  {List.map(~U32, ~U32, ~(item => Inventory.count(Inventory.create(), item)), [1, 2, 3, 4, 5, 6])
    == [32, 24, 16, 8, 8, 0] : List<U32>}

# What a hand, and each pickaxe, can break: stone, iron ore, diamond ore, obsidian.
law a_bare_hand_breaks_dirt_and_not_stone:
  {List.map(~U32, ~Bool, ~(block => Inventory.can_mine(0, block)), [2, 3, 4, 5, 6, 1, 9, 10, 23])
    == [True{}, True{}, True{}, True{}, True{}, False{}, False{}, False{}, False{}] : List<Bool>}

law a_wooden_pickaxe_breaks_stone_and_not_iron:
  {List.map(~U32, ~Bool, ~(block => Inventory.can_mine(11, block)), [1, 8, 22, 9, 10, 23])
    == [True{}, True{}, True{}, False{}, False{}, False{}] : List<Bool>}

law a_stone_pickaxe_breaks_iron_and_not_diamond:
  {List.map(~U32, ~Bool, ~(block => Inventory.can_mine(17, block)), [1, 9, 10, 23])
    == [True{}, True{}, False{}, False{}] : List<Bool>}

law an_iron_pickaxe_breaks_diamond_and_not_obsidian:
  {List.map(~U32, ~Bool, ~(block => Inventory.can_mine(18, block)), [1, 9, 10, 23])
    == [True{}, True{}, True{}, False{}] : List<Bool>}

law a_diamond_pickaxe_breaks_obsidian:
  {List.map(~U32, ~Bool, ~(block => Inventory.can_mine(19, block)), [1, 9, 10, 23])
    == [True{}, True{}, True{}, True{}] : List<Bool>}

law air_and_fluids_are_not_mined:
  {List.map(~U32, ~Bool, ~(block => Inventory.can_mine(19, block)), [0, 7, 21, 24])
    == [False{}, False{}, False{}, False{}] : List<Bool>}

# What each block leaves: an ore its mineral, a made block its item, a crop its seeds.
law what_a_block_drops:
  {List.map(~U32, ~U32, ~(block => Inventory.mining_item(block)), [1, 2, 3, 4, 5, 6, 8, 9, 10, 20, 16, 17, 18, 19])
    == [1, 2, 3, 4, 5, 6, 14, 15, 16, 2, 25, 25, 25, 26] : List<U32>}

# What each redstone block leaves: its own item; the piston head leaves nothing.
law what_a_redstone_block_drops:
  {List.map(~U32, ~U32, ~(block => Inventory.mining_item(block)),
      [28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40])
    == [51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 0, 61, 62] : List<U32>}

# The open door drops the door item rather than whatever id the cell shares.
law what_an_open_door_drops:
  {Inventory.mining_item(15) == 24 : U32}

# What a block drops places that block again, for every block a player can put back.
law what_a_block_drops_places_it_again:
  {List.map(~U32, ~U32, ~(block => Inventory.placed_block(Inventory.mining_item(block))),
      [1, 2, 3, 4, 5, 6, 11, 12, 13, 14, 22, 23, 25, 26, 27])
    == [1, 2, 3, 4, 5, 6, 11, 12, 13, 14, 22, 23, 25, 26, 27] : List<U32>}

# The bottom row is bedrock: nothing can build or scoop the floor out.
law the_bottom_row_is_bedrock:
  {List.map(~U32, ~U32, ~(x => World.block(1337n, U32.to_nat(x), 0n, 33n)), [5, 16, 100, 400])
    == [41, 41, 41, 41] : List<U32>}

# Every item the bag lets a player place outside the redstone set names a block.
law every_placeable_item_places_a_block:
  {List.map(~U32, ~Bool, ~(item => Bool.and(Inventory.is_placeable(item), U32.is_ne(Inventory.placed_block(item), 0))),
      [1, 2, 3, 4, 5, 6, 10, 21, 22, 23, 24, 31, 32, 40, 43])
    == [True{}, True{}, True{}, True{}, True{}, True{}, True{}, True{}, True{}, True{}, True{}, True{}, True{}, True{}, True{}] : List<Bool>}

law tools_and_food_place_nothing:
  {List.map(~U32, ~Bool, ~(item => Inventory.is_placeable(item)), [0, 8, 9, 11, 14, 19, 26, 41])
    == [False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}] : List<Bool>}

# A leaf at (0, 8, 0) is one of the leaves that drops an apple, and its neighbour is not.
law some_leaves_drop_an_apple:
  {(Inventory.mine_drop_at(0, 4, 0n, 8n, 0n), Inventory.mine_drop_at(0, 4, 1n, 8n, 0n))
    == (Inventory.MiningResult{42, 1, True{}}, Inventory.MiningResult{4, 1, True{}}) : Inventory.MiningResult & Inventory.MiningResult}

law a_stack_holds_sixty_four:
  {Inventory.add_remaining(Inventory.add_items(Inventory.empty_slots(1n), 1, 70)) == 6 : U32}

law a_tool_wears_by_one_and_breaks_at_zero:
  {(Inventory.use_tool(11, 59), Inventory.use_tool(11, 1))
    == (Inventory.ToolResult{58, False{}, True{}}, Inventory.ToolResult{0, True{}, True{}}) : Inventory.ToolResult & Inventory.ToolResult}

law each_tool_starts_with_its_durability:
  {List.map(~U32, ~U32, ~(item => Inventory.tool_max_durability(item)), [11, 17, 18, 19, 27, 1])
    == [59, 131, 250, 1561, 59, 0] : List<U32>}

# Two logs become a wooden pickaxe: a log is four planks, two planks are four
# sticks, and three planks over two sticks are the pickaxe.
law two_logs_make_a_wooden_pickaxe:
  {List.map(~U32, ~U32,
      ~(item => Inventory.count(Inventory.inventory_slots(Inventory.craft(Inventory.inventory_slots(Inventory.craft(
        Inventory.inventory_slots(Inventory.craft(Inventory.inventory_slots(Inventory.craft(Inventory.create(), 0n)), 0n)), 1n)), 3n)), item)),
      [5, 8, 9, 11])
    == [6, 3, 2, 1] : List<U32>}

law crafting_without_the_ingredients_is_refused:
  {Inventory.craft(Inventory.create(), 6n) == Inventory.result(Inventory.create(), False{}) : Inventory.InventoryResult}

# --- armour --------------------------------------------------------------------------

# For every outfit and item: a slot past the five changes nothing and holds nothing.
law an_unknown_armour_slot_changes_nothing:
  for +outfit: Equipment.Equipment
  for +item: U32
  for +k: Nat
  {(Equipment.equip_slot(outfit, Nat.add(5n, k), item), Equipment.take_slot(outfit, Nat.add(5n, k)))
    == (outfit, Equipment.TakeResult{outfit, 0, False{}}) : Equipment.Equipment & Equipment.TakeResult}

# For every outfit and item: what is put in a slot is what comes back out of it.
law armour_taken_off_is_the_armour_put_on:
  for +outfit: Equipment.Equipment
  for +item: U32
  {(Equipment.take_item(Equipment.take_slot(Equipment.equip_slot(outfit, 0n, item), 0n)),
    (Equipment.take_item(Equipment.take_slot(Equipment.equip_slot(outfit, 1n, item), 1n)),
    (Equipment.take_item(Equipment.take_slot(Equipment.equip_slot(outfit, 2n, item), 2n)),
    (Equipment.take_item(Equipment.take_slot(Equipment.equip_slot(outfit, 3n, item), 3n)),
     Equipment.take_item(Equipment.take_slot(Equipment.equip_slot(outfit, 4n, item), 4n))))))
    == (item, (item, (item, (item, item)))) : U32 & (U32 & (U32 & (U32 & U32)))}

law each_armour_piece_has_its_slot:
  {List.map(~U32, ~U32, ~(item => Equipment.slot_for_item(item)), [38, 44, 45, 46, 47, 1])
    == [0, 1, 2, 3, 4, 99] : List<U32>}

law a_full_set_defends_seven:
  {Equipment.armor_defense(Equipment.Equipment{38, 44, 45, 46, 47}) == 7 : U32}

law a_block_is_not_armour:
  {Equipment.equip_ok(Equipment.equip(Equipment.empty(), 1)) == False{} : Bool}

# --- the furnace ---------------------------------------------------------------------

# For every furnace: a load or a take that is refused answers the furnace it was given.
law a_refused_load_keeps_the_furnace:
  for +furnace: Furnace.Furnace
  for +item: U32
  for +amount: Nat
  for h: {furnace_ok(Furnace.load_input(furnace, item, amount)) == False{} : Bool}
  {furnace_of(Furnace.load_input(furnace, item, amount)) == furnace : Furnace.Furnace}

law a_refused_fuel_keeps_the_furnace:
  for +furnace: Furnace.Furnace
  for +item: U32
  for +amount: Nat
  for h: {furnace_ok(Furnace.load_fuel(furnace, item, amount)) == False{} : Bool}
  {furnace_of(Furnace.load_fuel(furnace, item, amount)) == furnace : Furnace.Furnace}

law a_refused_take_keeps_the_furnace:
  for +furnace: Furnace.Furnace
  for h: {transfer_ok(Furnace.take_output(furnace)) == False{} : Bool}
  {transfer_furnace(Furnace.take_output(furnace)) == furnace : Furnace.Furnace}

law what_each_ore_smelts_into:
  {List.map(~U32, ~U32, ~(item => Furnace.smelt_output(item)), [15, 6, 31, 26])
    == [20, 40, 1, 41] : List<U32>}

law a_furnace_without_fuel_does_not_burn:
  {step_ok(Furnace.tick(Furnace.Furnace{15, 1, 0, 0, 0, 0, 0, 0})) == False{} : Bool}

law a_lit_furnace_burns_one_coal_for_eight_ticks:
  {Furnace.step_furnace(Furnace.tick(Furnace.Furnace{15, 1, 14, 1, 0, 0, 0, 0}))
    == Furnace.Furnace{15, 1, 14, 0, 20, 0, 1, 7} : Furnace.Furnace}

# --- digging ----------------------------------------------------------------------------

# For every block, cell, item and time: a dig the rules refuse is the dig at rest and never
# comes away, so nothing about the time or what was going can make a refused block progress.
# Whether a tick is allowed is decided first and alone (`Digging.step.allowed`); that it is
# decided by `Inventory.can_mine` is held by the tests, because the checker computes no floats.
law a_refused_dig_gets_nowhere:
  for +block: U32
  for +x: Nat
  for +y: Nat
  for +z: Nat
  for +item: U32
  for +time: F32
  {Digging.step.allowed(False{}, block, x, y, z, item, time)
    == Digging.Mined{Digging.resting(), False{}} : Digging.Mined}

# --- the blocks that hold something --------------------------------------------------

# A furnace, a chest and a crafting table are named once, in `world/world.bend`, and the item
# that places each (`Inventory.placed_block`) puts down the block named for it. A client and a
# room each used to keep their own number for these.
law the_blocks_that_hold_something_are_named:
  {[World.furnace_block(), World.chest_block(), World.crafting_table_block()] == [11, 26, 27] : List<U32>}

law an_item_places_the_block_named_for_it:
  {[Inventory.placed_block(21), Inventory.placed_block(43), Inventory.placed_block(10)]
    == [World.furnace_block(), World.chest_block(), World.crafting_table_block()] : List<U32>}

# --- the chest -----------------------------------------------------------------------

# For every chest, slot and amount: taking from it answers a chest of as many slots.
law a_withdrawal_keeps_the_chest_slots:
  for chest: List<&2, Chest.Slot>
  for +index: Nat
  for +amount: U32
  {List.length(&2, Chest.Slot, Chest.withdraw_slots(Chest.withdraw(chest, index, amount)))
    == List.length(&2, Chest.Slot, chest) : Nat}

law a_chest_has_nine_slots:
  {List.length(&2, Chest.Slot, Chest.empty()) == 9n : Nat}

law a_tool_keeps_its_wear_in_a_chest:
  {Chest.withdraw(Chest.deposit_slots(Chest.deposit(Chest.empty_slots(1n), 11, 1, 37)), 0n, 1)
    == Chest.WithdrawResult{Chest.empty_slots(1n), 11, 1, 37, True{}} : Chest.WithdrawResult}

# --- farmland and crops ----------------------------------------------------------------

# For every farm and cell: a plot added is a plot the farm holds.
law an_added_plot_is_in_the_farm:
  for +farm: Farmland.State
  for +x: Nat
  for +y: Nat
  for +z: Nat
  {Farmland.contains(farm_plots(Farmland.add(farm, x, y, z)), x, y, z) == True{} : Bool}

# For every farm: a tick dries or wets plots, and makes or loses none.
law a_tick_keeps_every_plot:
  for plots: List<&2, Farmland.Plot>
  for +waters: List<&2, Farmland.Water>
  {List.length(&2, Farmland.Plot, Farmland.tick_entries(plots, waters)) == List.length(&2, Farmland.Plot, plots) : Nat}

# For every field: a tick grows crops, and makes or loses none.
law a_tick_keeps_every_crop:
  for crops: List<&2, Crops.Crop>
  for +steps: Nat
  {List.length(&2, Crops.Crop, Crops.tick_entries(crops, steps)) == List.length(&2, Crops.Crop, crops) : Nat}

law water_within_four_cells_wets_a_plot:
  {(Farmland.tick_plot(Farmland.Plot{10n, 5n, 10n, 0}, [Farmland.Water{14n, 6n}]),
    Farmland.tick_plot(Farmland.Plot{10n, 5n, 10n, 3}, [Farmland.Water{15n, 10n}]))
    == (Farmland.Plot{10n, 5n, 10n, 7}, Farmland.Plot{10n, 5n, 10n, 2}) : Farmland.Plot & Farmland.Plot}

law seeds_grow_on_farmland_only:
  {(crop_ok(Crops.plant(Crops.empty(), 1n, 2n, 3n, 20, 0)),
    (crop_ok(Crops.plant(Crops.empty(), 1n, 2n, 3n, 2, 0)), crop_ok(Crops.plant(Crops.empty(), 1n, 2n, 3n, 20, 5))))
    == (True{}, (False{}, False{})) : Bool & (Bool & Bool)}

law wheat_grows_a_stage_every_four_ticks_and_stops_ripe:
  {List.map(~U32, ~U32, ~(stage => Crops.next_stage(stage, 4n)), [16, 17, 18, 19])
    == [17, 18, 19, 19] : List<U32>}

law ripe_wheat_gives_a_seed_and_a_wheat:
  {(harvest_yield(Crops.harvest(Crops.State{[Crops.Crop{1n, 2n, 3n, 19, 0n}]}, 1n, 2n, 3n)),
    harvest_yield(Crops.harvest(Crops.State{[Crops.Crop{1n, 2n, 3n, 18, 0n}]}, 1n, 2n, 3n)))
    == ((1, (1, True{})), (0, (0, False{}))) : (U32 & (U32 & Bool)) & (U32 & (U32 & Bool))}

# --- experience ------------------------------------------------------------------------

law a_level_costs_seven_and_two_more_each_time:
  {List.map(~U32, ~U32, ~(level => Experience.threshold(level)), [0, 1, 5])
    == [7, 9, 17] : List<U32>}

law seven_points_are_the_first_level:
  {(Experience.add(Experience.empty(), 6), Experience.add(Experience.empty(), 7))
    == (Experience.XP{0, 6}, Experience.XP{1, 0}) : Experience.XP & Experience.XP}

law a_monster_is_worth_five_and_an_animal_two:
  {(Experience.xp_for_kind(2), Experience.xp_for_kind(1)) == (5, 2) : U32 & U32}

# --- light, bodies and fluids: one reading of each block id -------------------------------
# The block ids are 0 air to 29 redstone torch. Light, collision and fluids each ask
# their own question of an id, and these hold the answers to each other.

law light_reaches_fifteen:
  {(Light.max_light(), Redstone.max_power()) == (15, 15) : U32 & U32}

law a_cave_is_never_darker_than_three_or_brighter_than_twelve:
  {List.map(~Nat, ~U32, ~(y => Light.cave_ambient(y)), [0n, 4n, 18n, 40n])
    == [3, 5, 12, 12] : List<U32>}

law torches_and_lava_give_light:
  {List.map(~U32, ~Bool, ~(block => Light.is_light_source(block)), [12, 21, 1, 7])
    == [True{}, True{}, False{}, False{}] : List<Bool>}

# No block lets both light and a body through and is also solid: for every id.
law what_light_passes_a_body_passes:
  {List.map(~U32, ~Bool, ~(block => Bool.and(Light.transparent_block(block), Player.solid(block))),
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29])
    == [False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{},
        False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{},
        False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}] : List<Bool>}

law the_ground_is_solid_and_the_air_is_not:
  {List.map(~U32, ~Bool, ~(block => Player.solid(block)), [1, 2, 3, 4, 5, 6, 0, 7, 12, 15, 16, 19, 21, 24])
    == [True{}, True{}, True{}, True{}, True{}, True{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}] : List<Bool>}

# The fluid rules and the world's block ids name the same blocks, and nothing a
# player mines is a fluid.
# A placed pool holds its shape instead of ratcheting itself away. A tick used
# to rebuild the field from the spreads alone, so every cell took a lower level
# than it had, one step per tick, until the pool drained; it also walked only
# the first 64 flows and dropped the rest, which cleared their cells in the
# world. These are values, computed from the same definition the game runs.
law a_settled_pool_keeps_its_cells:
  {List.length(&2, Fluids.Flow, Fluids.state_flows(Fluids.tick(
      Fluids.State{
        Con{Fluids.Flow{5n, 0n, 5n, 8, True{}, 7},
        Con{Fluids.Flow{6n, 0n, 5n, 7, False{}, 7},
        Con{Fluids.Flow{7n, 0n, 5n, 6, False{}, 7}, Nil{}}}}},
      Nil{}))) == 3n : Nat}

# A cell with no source, no stronger neighbour and no water above it has nothing
# holding it there, so the tick clears it and leaves only what it reached.
law an_unfed_flow_dries_up:
  {List.length(&2, Fluids.Flow, Fluids.state_flows(Fluids.tick(
      Fluids.State{
        Con{Fluids.Flow{5n, 0n, 5n, 3, False{}, 7}, Nil{}}},
      Nil{}))) == 0n : Nat}

# A shovel, an axe and shears: what kind of tool each is, what tier, how long it
# lasts, and that none of them is a pickaxe or a block. The speeds are floats and
# so are held by the tests; these are the answers the checker can decide.
law the_tool_kinds_are_what_they_are:
  {List.map(~U32, ~U32, ~(item => Inventory.tool_kind(item)),
      [0, 11, 17, 18, 19, 27, 63, 64, 65, 66, 67, 68, 69, 70, 71])
    == [0, 1, 1, 1, 1, 3, 3, 3, 3, 3, 2, 2, 2, 2, 4] : List<U32>}

law the_tool_tiers_run_wooden_to_diamond:
  {List.map(~U32, ~U32, ~(item => Inventory.tool_tier(item)), [63, 64, 65, 66, 67, 68, 69, 70, 71])
    == [1, 2, 3, 4, 1, 2, 3, 4, 5] : List<U32>}

law a_tool_wears_by_its_tier:
  {List.map(~U32, ~U32, ~(item => Inventory.tool_max_durability(item)), [63, 64, 65, 66, 70, 71])
    == [59, 131, 250, 1561, 1561, 238] : List<U32>}

law the_tools_place_nothing:
  {List.map(~U32, ~U32, ~(item => Inventory.placed_block(item)), [63, 64, 65, 66, 67, 68, 69, 70, 71])
    == [0, 0, 0, 0, 0, 0, 0, 0, 0] : List<U32>}

law the_tools_break_what_they_are_for:
  {List.map(~U32, ~Bool, ~(item => Inventory.can_mine(item, 2)), [63, 67, 71])
    == [True{}, True{}, True{}] : List<Bool>}

# The materials a block wants: dirt a shovel, wood an axe, leaves shears.
law each_block_wants_its_tool:
  {List.map(~U32, ~U32, ~(block => Inventory.suited_kind(block)), [2, 3, 6, 20, 5, 4, 1, 23])
    == [3, 3, 3, 3, 2, 4, 1, 1] : List<U32>}

law the_fluids_are_water_and_lava:
  {(Fluids.water_block(), (Fluids.lava_block(), (Fluids.cobblestone_block(), (Fluids.obsidian_block(), Fire.fire_block()))))
    == (7, (21, (22, (23, 24)))) : U32 & (U32 & (U32 & (U32 & U32)))}

law water_and_lava_meet_as_stone:
  {(Fluids.opposite_block(7), (Fluids.opposite_block(21), (Fluids.reaction_block(True{}), Fluids.reaction_block(False{}))))
    == (21, (7, (23, 22))) : U32 & (U32 & (U32 & U32))}

law only_wood_and_leaves_burn:
  {List.map(~U32, ~Bool, ~(block => Fire.flammable(block)), [4, 5, 1, 2, 3, 6, 7])
    == [True{}, True{}, False{}, False{}, False{}, False{}, False{}] : List<Bool>}

# --- redstone ------------------------------------------------------------------------

# The redstone ids continue the world's from 28, in the order the adapter walks.
law the_redstone_blocks_are_twenty_eight_to_forty:
  {Redstone.block_ids() == [28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40] : List<U32>}

law power_never_decays_below_zero:
  {(Redstone.sat_sub32(15, 1), (Redstone.sat_sub32(1, 1), Redstone.sat_sub32(0, 1))) == (14, (0, 0)) : U32 & (U32 & U32)}

# For every signal: it is the same signal as itself.
law a_signal_equals_itself:
  for +a: Bool
  {Redstone.same_bool(a, a) == True{} : Bool}

# --- the mobs ------------------------------------------------------------------------

# Every kind of the roster is an animal or a hostile, and none is both.
law every_mob_is_an_animal_or_a_hostile:
  {List.map(~U32, ~Bool, ~(kind => Bool.xor(Entities.kind_is_animal(kind), Entities.kind_is_hostile(kind))), [1, 2, 3, 4, 5, 6])
    == [True{}, True{}, True{}, True{}, True{}, True{}] : List<Bool>}

# A body is a mob exactly when the roster holds its kind, 1 to 6: the number that names a
# villager (10 and up) or an item on the ground (1000 and up) is not one, and neither is 0.
law only_the_roster_are_mobs:
  {List.map(~U32, ~Bool, ~(kind => Entities.kind_is_mob(kind)), [0, 1, 2, 3, 4, 5, 6, 7, 10, 11, 1000, 1001])
    == [False{}, True{}, True{}, True{}, True{}, True{}, True{}, False{}, False{}, False{}, False{}, False{}] : List<Bool>}

law zombies_and_brutes_are_the_hostiles:
  {List.map(~U32, ~Bool, ~(kind => Entities.kind_is_hostile(kind)), [1, 2, 3, 4, 5, 6])
    == [False{}, True{}, False{}, True{}, False{}, False{}] : List<Bool>}

law what_each_mob_leaves:
  {List.map(~U32, ~U32, ~(kind => Entities.drop_item(kind)), [1, 2, 3, 4, 5, 6])
    == [48, 13, 12, 13, 49, 50] : List<U32>}

law wander_dir_pins_heading:
  {Entities.wander_dir(3n, 48n) == 7 : U32}
