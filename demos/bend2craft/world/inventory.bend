import Base
import ./world_state.bend as WorldState

# Item IDs: 0 empty, 1 stone, 2 dirt, 3 grass, 4 leaves, 5 wood,
# 6 sand, 7 water, 8 planks, 9 sticks, 10 crafting table, 11 wooden pickaxe,
# 12 wool, 13 rotten flesh, 14 coal, 15 raw iron, 16 diamond,
# 17 stone pickaxe, 18 iron pickaxe, 19 diamond pickaxe, 20 iron ingot,
# 21 furnace, 22 torch, 23 bed, 24 door, 25 wheat seeds, 26 wheat,
# 27 wooden hoe, 28 empty bucket, 29 water bucket, 30 lava bucket,
# 31 cobblestone, 32 obsidian, 33 wooden sword, 34 stone sword,
# 35 iron sword, 36 diamond sword, 37 bow, 38 shield, 39 arrow,
# 40 glass, 41 bread, 42 apple, 43 chest,
# 44 leather helmet, 45 iron chestplate, 46 iron leggings, 47 iron boots,
# 48 raw porkchop, 49 raw beef, 50 raw chicken.
# Block 20 is farmland and drops dirt; it has no standalone inventory item.
# Blocks 25 (glass), 26 (chest) and 27 (crafting table) drop items
# 40, 43 and 10. Items 48-50 are what a farm animal leaves behind, so the
# animals are worth striking instead of being scenery.

type Slot is Data:
  Slot{item: U32, count: U32, durability: U32}

type InventoryResult is Data:
  InventoryResult{slots: List<&2, Slot>, ok: Bool}

type GridCraftResult is Data:
  GridCraftResult{slots: List<&2, Slot>, grid: List<&2, Slot>, output: U32, amount: U32, ok: Bool}

type TradeResult is Data:
  TradeResult{slots: List<&2, Slot>, ok: Bool}

type AddResult is Data:
  AddResult{slots: List<&2, Slot>, remaining: U32}

type RemoveResult is Data:
  RemoveResult{slots: List<&2, Slot>, remaining: U32}

type Lookup is Data:
  Found{slot: Slot}
  Missing{}

type Recipe is Data:
  Recipe{item_a: U32, count_a: U32, item_b: U32, count_b: U32, output: U32, output_count: U32}

type ToolResult is Data:
  ToolResult{durability: U32, broken: Bool, valid: Bool}

type MiningResult is Data:
  MiningResult{item: U32, amount: U32, valid: Bool}

type InteractionResult is Data:
  InteractionResult{edit: WorldState.Edit, slots: List<&2, Slot>, ok: Bool}

# What kind of tool a thing is: 0 nothing in hand, 1 a pickaxe, 2 an axe, 3 a
# shovel (a hoe is one for digging), 4 shears. The kind is what says which
# material a tool suits; the tier is what says how good it is.
def tool_kind(+item: U32) -> U32:
  Bool.pick(U32, U32.is_eq(item, 71), 4,
    Bool.pick(U32, U32.is_eq(item, 67), 2,
      Bool.pick(U32, U32.is_eq(item, 68), 2,
        Bool.pick(U32, U32.is_eq(item, 69), 2,
          Bool.pick(U32, U32.is_eq(item, 70), 2,
            Bool.pick(U32, U32.is_eq(item, 63), 3,
              Bool.pick(U32, U32.is_eq(item, 64), 3,
                Bool.pick(U32, U32.is_eq(item, 65), 3,
                  Bool.pick(U32, U32.is_eq(item, 66), 3,
                    Bool.pick(U32, U32.is_eq(item, 27), 3,
                      Bool.pick(U32, U32.is_eq(item, 11), 1,
                        Bool.pick(U32, U32.is_eq(item, 17), 1,
                          Bool.pick(U32, U32.is_eq(item, 18), 1,
                            Bool.pick(U32, U32.is_eq(item, 19), 1, 0))))))))))))))

# The tier of a mining tool: 1 wooden, 2 stone, 3 iron, 4 diamond, 5 shears.
def tool_tier(+item: U32) -> U32:
  Bool.pick(U32, U32.is_eq(item, 71), 5,
    Bool.pick(U32, U32.is_eq(item, 66), 4,
      Bool.pick(U32, U32.is_eq(item, 70), 4,
        Bool.pick(U32, U32.is_eq(item, 19), 4,
          Bool.pick(U32, U32.is_eq(item, 65), 3,
            Bool.pick(U32, U32.is_eq(item, 69), 3,
              Bool.pick(U32, U32.is_eq(item, 18), 3,
                Bool.pick(U32, U32.is_eq(item, 64), 2,
                  Bool.pick(U32, U32.is_eq(item, 68), 2,
                    Bool.pick(U32, U32.is_eq(item, 17), 2,
                      Bool.pick(U32, U32.is_eq(item, 63), 1,
                        Bool.pick(U32, U32.is_eq(item, 67), 1,
                          Bool.pick(U32, U32.is_eq(item, 11), 1,
                            Bool.pick(U32, U32.is_eq(item, 27), 1, 0))))))))))))))

def suited_kind(+block: U32) -> U32:
  Bool.pick(U32, U32.is_eq(block, 4), 4,
    Bool.pick(U32, U32.is_eq(block, 5), 2,
      Bool.pick(U32, U32.is_eq(block, 6), 3,
        Bool.pick(U32, U32.is_eq(block, 2), 3,
          Bool.pick(U32, U32.is_eq(block, 3), 3,
            Bool.pick(U32, U32.is_eq(block, 20), 3, 1))))))

# The materials that are not mining tools: swords and the bow, which wear when
# they are used to hit, and armour, which wears when it is worn.
def tool_max_durability.other(+item: U32) -> U32:
  Bool.pick(U32, U32.is_eq(item, 36), 1561,
    Bool.pick(U32, U32.is_eq(item, 35), 250,
      Bool.pick(U32, U32.is_eq(item, 34), 131,
        Bool.pick(U32, U32.is_eq(item, 33), 59,
          Bool.pick(U32, U32.is_eq(item, 37), 384,
            Bool.pick(U32, U32.is_eq(item, 38), 336,
              Bool.pick(U32, U32.is_eq(item, 44), 55,
                Bool.pick(U32, U32.is_eq(item, 45), 400,
                  Bool.pick(U32, U32.is_eq(item, 46), 450,
                    Bool.pick(U32, U32.is_eq(item, 47), 385, 0))))))))))

def tool_max_durability(+item: U32) -> U32:
  # The mining tools wear by tier, whatever they are: a wooden shovel lasts as
  # long as a wooden pickaxe, and a diamond axe as long as a diamond pickaxe.
  +tier = tool_tier(item)
  +mining = Bool.pick(U32, U32.is_eq(tier, 5), 238,
    Bool.pick(U32, U32.is_eq(tier, 4), 1561,
      Bool.pick(U32, U32.is_eq(tier, 3), 250,
        Bool.pick(U32, U32.is_eq(tier, 2), 131,
          Bool.pick(U32, U32.is_eq(tier, 1), 59, 0)))))
  Bool.pick(U32, U32.is_ne(mining, 0), mining, tool_max_durability.other(item))

def weapon_damage(+item: U32) -> U32:
  Bool.pick(U32, U32.is_eq(item, 36), 7,
    Bool.pick(U32, U32.is_eq(item, 35), 6,
      Bool.pick(U32, U32.is_eq(item, 37), 6,
        Bool.pick(U32, U32.is_eq(item, 34), 5,
          Bool.pick(U32, U32.is_eq(item, 33), 4, 1)))))

def hand_damage() -> U32:
  4

# What a hit with an item in hand does: a sword its own damage, anything else the hand's.
def is_sword(+item: U32) -> Bool:
  Bool.and(U32.is_ge(item, 33), U32.is_le(item, 36))

def melee_damage(+item: U32) -> U32:
  Bool.pick(U32, is_sword(item), weapon_damage(item), hand_damage())

def slot_count() -> Nat:
  36n

def max_stack() -> U32:
  64

def food_value(+item: U32) -> U32:
  Bool.pick(U32, U32.is_eq(item, 13), 4,
    Bool.pick(U32, U32.is_eq(item, 26), 2,
      Bool.pick(U32, U32.is_eq(item, 41), 5,
        Bool.pick(U32, U32.is_eq(item, 42), 4,
          Bool.pick(U32, U32.is_eq(item, 50), 2,
            Bool.pick(U32, Bool.or(U32.is_eq(item, 48), U32.is_eq(item, 49)), 3, 0))))))

def slot_item(slot: Slot) -> U32:
  Slot{item, count, durability} = slot
  item

def slot_count_value(slot: Slot) -> U32:
  Slot{item, count, durability} = slot
  count

def slot_durability(slot: Slot) -> U32:
  Slot{item, count, durability} = slot
  durability

def make_slot(item: U32, count: U32, durability: U32) -> Slot:
  Slot{item, count, durability}

def cons_slot(slot: Slot, tail: List<&2, Slot>) -> List<&2, Slot>:
  Con{slot, tail}

def empty_slots(+remaining: Nat) -> List<&2, Slot>:
  match remaining:
    case 0n:
      Nil{}
    case 1n+p:
      Slot{0, 0, 0} <> empty_slots(p)

def create() -> List<&2, Slot>:
  Slot{1, 32, 0} <> Slot{2, 24, 0} <> Slot{3, 16, 0} <> Slot{4, 8, 0}
    <> Slot{5, 8, 0} <> empty_slots(31n)

def result(slots: List<&2, Slot>, ok: Bool) -> InventoryResult:
  InventoryResult{slots, ok}

def inventory_slots(state: InventoryResult) -> List<&2, Slot>:
  InventoryResult{slots, ok} = state
  slots

def inventory_ok(state: InventoryResult) -> Bool:
  InventoryResult{slots, ok} = state
  ok

def trade_slots(state: TradeResult) -> List<&2, Slot>:
  TradeResult{slots, ok} = state
  slots

def trade_ok(state: TradeResult) -> Bool:
  TradeResult{slots, ok} = state
  ok

def add_slots(state: AddResult) -> List<&2, Slot>:
  AddResult{slots, remaining} = state
  slots

def add_remaining(state: AddResult) -> U32:
  AddResult{slots, remaining} = state
  remaining

def remove_slots(state: RemoveResult) -> List<&2, Slot>:
  RemoveResult{slots, remaining} = state
  slots

def remove_remaining(state: RemoveResult) -> U32:
  RemoveResult{slots, remaining} = state
  remaining

def count_item(slots: List<&2, Slot>, +item: U32, total: U32) -> U32:
  match slots:
    case Nil{}:
      total
    case Con{+head, tail}:
      +added = Bool.pick(U32, U32.is_eq(slot_item(head), item), slot_count_value(head), 0)
      count_item(tail, item, U32.add(total, added))

def count(slots: List<&2, Slot>, item: U32) -> U32:
  count_item(slots, item, 0)

def add_existing(slots: List<&2, Slot>, +item: U32, +amount: U32) -> AddResult:
  match slots:
    case Nil{}:
      AddResult{Nil{}, amount}
    case Con{+head, tail}:
      +same_item = U32.is_eq(slot_item(head), item)
      +has_room = U32.is_lt(slot_count_value(head), max_stack())
      +has_amount = U32.is_ne(amount, 0)
      +eligible = Bool.and(Bool.and(same_item, has_room), has_amount)
      +space = U32.sub(max_stack(), slot_count_value(head))
      +added = Bool.pick(U32, eligible, U32.min(amount, space), 0)
      +updated = make_slot(slot_item(head), U32.add(slot_count_value(head), added), slot_durability(head))
      +rest = add_existing(tail, item, U32.sub(amount, added))
      AddResult{cons_slot(updated, add_slots(rest)), add_remaining(rest)}

def add_empty(slots: List<&2, Slot>, +item: U32, +amount: U32) -> AddResult:
  match slots:
    case Nil{}:
      AddResult{Nil{}, amount}
    case Con{+head, tail}:
      +empty = Bool.and(U32.is_eq(slot_item(head), 0), U32.is_eq(slot_count_value(head), 0))
      +eligible = Bool.and(empty, U32.is_ne(amount, 0))
      +added = Bool.pick(U32, eligible, U32.min(amount, max_stack()), 0)
      +new_item = Bool.pick(U32, eligible, item, slot_item(head))
      +new_durability = Bool.pick(U32, eligible, tool_max_durability(item), slot_durability(head))
      +updated = make_slot(new_item, U32.add(slot_count_value(head), added), new_durability)
      +rest = add_empty(tail, item, U32.sub(amount, added))
      AddResult{cons_slot(updated, add_slots(rest)), add_remaining(rest)}

def add_items(slots: List<&2, Slot>, +item: U32, +amount: U32) -> AddResult:
  +first = add_existing(slots, item, amount)
  add_empty(add_slots(first), item, add_remaining(first))

def is_block_item(+item: U32) -> Bool:
  Bool.or(
    Bool.and(U32.is_ne(item, 0), U32.is_lt(item, 7)),
    Bool.or(
      Bool.or(U32.is_eq(item, 31), U32.is_eq(item, 32)),
      # The redstone slice: items 51-62 are the placeable redstone blocks from
      # world/redstone.bend, whose own contract owns the block ids they place.
      Bool.or(
        Bool.or(U32.is_eq(item, 51), U32.is_eq(item, 52)),
        Bool.or(
          Bool.or(U32.is_eq(item, 53), U32.is_eq(item, 54)),
          Bool.or(
            Bool.or(U32.is_eq(item, 55), U32.is_eq(item, 56)),
            Bool.or(
              Bool.or(U32.is_eq(item, 57), U32.is_eq(item, 58)),
              Bool.or(
                Bool.or(U32.is_eq(item, 59), U32.is_eq(item, 60)),
                Bool.or(U32.is_eq(item, 61), U32.is_eq(item, 62))
              )
            )
          )
        )
      )
    )
  )

def collect.finalize(
  original: List<&2, Slot>, added: AddResult, valid: Bool
) -> InventoryResult:
  match valid:
    case True{}:
      result(add_slots(added), True{})
    case False{}:
      result(original, False{})

def collect.if(
  +slots: List<&2, Slot>, +item: U32, amount: U32, valid: Bool
) -> InventoryResult:
  match valid:
    case False{}:
      result(slots, False{})
    case True{}:
      +added = add_items(slots, item, amount)
      collect.finalize(slots, added, U32.is_eq(add_remaining(added), 0))

def collect(slots: List<&2, Slot>, +item: U32, +amount: Nat) -> InventoryResult:
  +valid_item = Bool.and(U32.is_ne(item, 0), U32.is_lt(item, 7))
  +valid_amount = Nat.is_gt(amount, 0n)
  collect.if(slots, item, U32.from_nat(amount), Bool.and(valid_item, valid_amount))

def pickup_item(+item: U32) -> Bool:
  +mob = Bool.or(Bool.or(U32.is_eq(item, 11), U32.is_eq(item, 12)), Bool.or(U32.is_eq(item, 13), Bool.or(Bool.or(U32.is_eq(item, 48), U32.is_eq(item, 49)), U32.is_eq(item, 50))))
  +ore = Bool.or(Bool.or(U32.is_eq(item, 14), U32.is_eq(item, 15)), U32.is_eq(item, 16))
  +tools = Bool.or(Bool.or(Bool.or(Bool.or(U32.is_eq(item, 17), U32.is_eq(item, 18)), Bool.or(U32.is_eq(item, 19), U32.is_eq(item, 27))), Bool.or(Bool.or(Bool.or(U32.is_eq(item, 63), U32.is_eq(item, 64)), Bool.or(U32.is_eq(item, 65), U32.is_eq(item, 66))), Bool.or(Bool.or(Bool.or(U32.is_eq(item, 67), U32.is_eq(item, 68)), Bool.or(U32.is_eq(item, 69), U32.is_eq(item, 70))), U32.is_eq(item, 71)))), False{})
  +combat = Bool.or(Bool.or(Bool.or(U32.is_eq(item, 33), U32.is_eq(item, 34)), Bool.or(U32.is_eq(item, 35), U32.is_eq(item, 36))), Bool.or(Bool.or(U32.is_eq(item, 37), U32.is_eq(item, 38)), U32.is_eq(item, 39)))
  +goods = Bool.or(Bool.or(U32.is_eq(item, 40), U32.is_eq(item, 41)), Bool.or(U32.is_eq(item, 42), U32.is_eq(item, 43)))
  +smelted = Bool.or(Bool.or(U32.is_eq(item, 20), U32.is_eq(item, 21)), Bool.or(Bool.or(Bool.or(U32.is_eq(item, 22), U32.is_eq(item, 23)), U32.is_eq(item, 24)), Bool.or(U32.is_eq(item, 25), U32.is_eq(item, 26))))
  +buckets = Bool.or(Bool.or(U32.is_eq(item, 28), U32.is_eq(item, 29)), U32.is_eq(item, 30))
  Bool.or(Bool.or(Bool.or(is_block_item(item), combat), goods), Bool.or(mob, Bool.or(ore, Bool.or(tools, Bool.or(smelted, buckets)))))

def pickup(slots: List<&2, Slot>, +item: U32, +amount: Nat) -> InventoryResult:
  collect.if(slots, item, U32.from_nat(amount),
    Bool.and(pickup_item(item), Nat.is_gt(amount, 0n)))

def remove_items(slots: List<&2, Slot>, +item: U32, +amount: U32) -> RemoveResult:
  match slots:
    case Nil{}:
      RemoveResult{Nil{}, amount}
    case Con{+head, tail}:
      +matching = U32.is_eq(slot_item(head), item)
      +removed = Bool.pick(U32, matching, U32.min(amount, slot_count_value(head)), 0)
      +left = U32.sub(slot_count_value(head), removed)
      +new_item = Bool.pick(U32, U32.is_eq(left, 0), 0, slot_item(head))
      +new_durability = Bool.pick(U32, U32.is_eq(left, 0), 0, slot_durability(head))
      +updated = make_slot(new_item, left, new_durability)
      +rest = remove_items(tail, item, U32.sub(amount, removed))
      RemoveResult{cons_slot(updated, remove_slots(rest)), remove_remaining(rest)}

def trade(
  +slots: List<&2, Slot>, +cost_item: U32, +cost_amount: U32,
  +reward_item: U32, +reward_amount: U32
) -> TradeResult:
  +removed = remove_items(slots, cost_item, cost_amount)
  +paid = U32.is_eq(remove_remaining(removed), 0)
  +added = add_items(remove_slots(removed), reward_item, reward_amount)
  +room = U32.is_eq(add_remaining(added), 0)
  +ok = Bool.and(paid, room)
  +next_slots = Bool.pick(List<&2, Slot>, ok, add_slots(added), slots)
  TradeResult{next_slots, ok}

def consume.head(
  original: List<&2, Slot>, tail: List<&2, Slot>, +slot: Slot, +amount: U32, valid: Bool
) -> InventoryResult:
  match valid:
    case False{}:
      result(original, False{})
    case True{}:
      +left = U32.sub(slot_count_value(slot), amount)
      +new_item = Bool.pick(U32, U32.is_eq(left, 0), 0, slot_item(slot))
      +new_durability = Bool.pick(U32, U32.is_eq(left, 0), 0, slot_durability(slot))
      +updated = make_slot(new_item, left, new_durability)
      result(cons_slot(updated, tail), True{})

def consume.at(slots: List<&2, Slot>, +index: Nat, +amount: U32) -> InventoryResult:
  match slots:
    case Nil{}:
      result(Nil{}, False{})
    case Con{+head, +tail}:
      match index:
        case 0n:
          consume.head(slots, tail, head, amount,
            Bool.and(U32.is_ne(slot_item(head), 0), U32.is_le(amount, slot_count_value(head))))
        case 1n+p:
          +rest = consume.at(tail, p, amount)
          result(cons_slot(head, inventory_slots(rest)), inventory_ok(rest))

def consume.if(slots: List<&2, Slot>, +index: Nat, +amount: U32, valid: Bool) -> InventoryResult:
  match valid:
    case False{}:
      result(slots, False{})
    case True{}:
      consume.at(slots, index, amount)

def consume(slots: List<&2, Slot>, +index: Nat, +amount: Nat) -> InventoryResult:
  consume.if(slots, index, U32.from_nat(amount),
    Bool.and(Nat.is_lt(index, slot_count()), Nat.is_gt(amount, 0n)))

def lookup(slots: List<&2, Slot>, +index: Nat) -> Lookup:
  match slots:
    case Nil{}:
      Missing{}
    case Con{+head, tail}:
      match index:
        case 0n:
          Found{head}
        case 1n+p:
          lookup(tail, p)

def replace_at(slots: List<&2, Slot>, +index: Nat, replacement: Slot) -> List<&2, Slot>:
  match slots:
    case Nil{}:
      Nil{}
    case Con{+head, tail}:
      match index:
        case 0n:
          cons_slot(replacement, tail)
        case 1n+p:
          cons_slot(head, replace_at(tail, p, replacement))

def move.finalize(
  original: List<&2, Slot>, +from: Nat, +to: Nat, +source: Slot, +target: Slot,
  +moving: U32, valid: Bool
) -> InventoryResult:
  match valid:
    case False{}:
      result(original, False{})
    case True{}:
      +source_left = U32.sub(slot_count_value(source), moving)
      +source_item = Bool.pick(U32, U32.is_eq(source_left, 0), 0, slot_item(source))
      +source_durability = Bool.pick(U32, U32.is_eq(source_left, 0), 0, slot_durability(source))
      +source_slot = make_slot(source_item, source_left, source_durability)
      +target_durability = Bool.pick(U32, U32.is_eq(slot_item(target), 0), slot_durability(source), slot_durability(target))
      +target_slot = make_slot(slot_item(source), U32.add(slot_count_value(target), moving), target_durability)
      +after_source = replace_at(original, from, source_slot)
      result(replace_at(after_source, to, target_slot), True{})

def move.found(
  original: List<&2, Slot>, +from: Nat, +to: Nat, +amount: U32,
  +source: Slot, +target: Slot
) -> InventoryResult:
  +compatible = Bool.or(U32.is_eq(slot_item(target), 0), U32.is_eq(slot_item(target), slot_item(source)))
  +space = Bool.pick(U32, U32.is_eq(slot_item(target), 0), max_stack(), U32.sub(max_stack(), slot_count_value(target)))
  +moving = U32.min(U32.min(amount, slot_count_value(source)), space)
  +valid = Bool.and(Bool.and(U32.is_ne(slot_item(source), 0), compatible), U32.is_ne(moving, 0))
  move.finalize(original, from, to, source, target, moving, valid)

def move.target(
  +original: List<&2, Slot>, +from: Nat, +to: Nat, +amount: U32,
  source: Slot, lookup_result: Lookup
) -> InventoryResult:
  match lookup_result:
    case Missing{}:
      result(original, False{})
    case Found{target}:
      move.found(original, from, to, amount, source, target)

def move.source(
  +original: List<&2, Slot>, +from: Nat, +to: Nat, amount: U32, lookup_result: Lookup
) -> InventoryResult:
  match lookup_result:
    case Missing{}:
      result(original, False{})
    case Found{source}:
      move.target(original, from, to, amount, source, lookup(original, to))

def move.if(
  +slots: List<&2, Slot>, +from: Nat, +to: Nat, amount: U32, valid: Bool
) -> InventoryResult:
  match valid:
    case False{}:
      result(slots, False{})
    case True{}:
      move.source(slots, from, to, amount, lookup(slots, from))

def move(slots: List<&2, Slot>, +from: Nat, +to: Nat, +amount: Nat) -> InventoryResult:
  +valid = Bool.and(Bool.and(Nat.is_lt(from, slot_count()), Nat.is_lt(to, slot_count())), Nat.is_ne(from, to))
  move.if(slots, from, to, U32.from_nat(amount), valid)

def recipe(index: Nat) -> Recipe:
  match index:
    case 0n:
      Recipe{5, 1, 0, 0, 8, 4}
    case 1n:
      Recipe{8, 2, 0, 0, 9, 4}
    case 2n:
      Recipe{8, 4, 0, 0, 10, 1}
    case 3n:
      Recipe{8, 3, 9, 2, 11, 1}
    case 4n:
      Recipe{1, 3, 9, 2, 17, 1}
    case 5n:
      Recipe{20, 3, 9, 2, 18, 1}
    case 6n:
      Recipe{16, 3, 9, 2, 19, 1}
    case 7n:
      Recipe{1, 8, 0, 0, 21, 1}
    case 8n:
      Recipe{14, 1, 9, 1, 22, 4}
    case 9n:
      Recipe{12, 3, 8, 3, 23, 1}
    case 10n:
      Recipe{8, 6, 0, 0, 24, 1}
    case 11n:
      Recipe{8, 2, 9, 2, 27, 1}
    case 12n:
      Recipe{20, 3, 0, 0, 28, 1}
    case 13n:
      Recipe{8, 2, 9, 1, 33, 1}
    case 14n:
      Recipe{1, 2, 9, 1, 34, 1}
    case 15n:
      Recipe{20, 2, 9, 1, 35, 1}
    case 16n:
      Recipe{16, 2, 9, 1, 36, 1}
    case 17n:
      Recipe{9, 3, 12, 3, 37, 1}
    case 18n:
      Recipe{9, 1, 14, 1, 39, 4}
    case 19n:
      Recipe{8, 6, 20, 1, 38, 1}
    case 20n:
      Recipe{26, 3, 0, 0, 41, 1}
    case 21n:
      Recipe{12, 5, 0, 0, 44, 1}
    case 22n:
      Recipe{20, 8, 0, 0, 45, 1}
    case 23n:
      Recipe{20, 7, 0, 0, 46, 1}
    case 24n:
      Recipe{20, 4, 0, 0, 47, 1}
    case 9n+p:
      Recipe{0, 0, 0, 0, 0, 0}

def recipe_data() -> List<U32>:
  5 <> 1 <> 0 <> 0 <> 8 <> 4 <> 0 <> 0 <>
  8 <> 2 <> 0 <> 0 <> 9 <> 4 <> 0 <> 0 <>
  8 <> 4 <> 0 <> 0 <> 10 <> 1 <> 0 <> 0 <>
  8 <> 3 <> 9 <> 2 <> 11 <> 1 <> 0 <> 0 <>
  1 <> 3 <> 9 <> 2 <> 17 <> 1 <> 0 <> 0 <>
  20 <> 3 <> 9 <> 2 <> 18 <> 1 <> 0 <> 0 <>
  16 <> 3 <> 9 <> 2 <> 19 <> 1 <> 0 <> 0 <>
  1 <> 8 <> 0 <> 0 <> 21 <> 1 <> 0 <> 0 <>
  14 <> 1 <> 9 <> 1 <> 22 <> 4 <> 0 <> 0 <>
  12 <> 3 <> 8 <> 3 <> 23 <> 1 <> 0 <> 0 <>
  8 <> 6 <> 0 <> 0 <> 24 <> 1 <> 0 <> 0 <>
  8 <> 2 <> 9 <> 2 <> 27 <> 1 <> 0 <> 0 <>
  20 <> 3 <> 0 <> 0 <> 28 <> 1 <> 0 <> 0 <>
  8 <> 2 <> 9 <> 1 <> 33 <> 1 <> 0 <> 0 <>
  1 <> 2 <> 9 <> 1 <> 34 <> 1 <> 0 <> 0 <>
  20 <> 2 <> 9 <> 1 <> 35 <> 1 <> 0 <> 0 <>
  16 <> 2 <> 9 <> 1 <> 36 <> 1 <> 0 <> 0 <>
  9 <> 3 <> 12 <> 3 <> 37 <> 1 <> 0 <> 0 <>
  9 <> 1 <> 14 <> 1 <> 39 <> 4 <> 0 <> 0 <>
  8 <> 6 <> 20 <> 1 <> 38 <> 1 <> 0 <> 0 <>
  26 <> 3 <> 0 <> 0 <> 41 <> 1 <> 0 <> 0 <>
  12 <> 5 <> 0 <> 0 <> 44 <> 1 <> 0 <> 0 <>
  20 <> 8 <> 0 <> 0 <> 45 <> 1 <> 0 <> 0 <>
  20 <> 7 <> 0 <> 0 <> 46 <> 1 <> 0 <> 0 <>
  20 <> 4 <> 0 <> 0 <> 47 <> 1 <> 0 <> 0 <>
  8 <> 1 <> 9 <> 2 <> 63 <> 1 <> 0 <> 0 <>
  31 <> 1 <> 9 <> 2 <> 64 <> 1 <> 0 <> 0 <>
  20 <> 1 <> 9 <> 2 <> 65 <> 1 <> 0 <> 0 <>
  16 <> 1 <> 9 <> 2 <> 66 <> 1 <> 0 <> 0 <>
  8 <> 3 <> 9 <> 2 <> 67 <> 1 <> 0 <> 0 <>
  31 <> 3 <> 9 <> 2 <> 68 <> 1 <> 0 <> 0 <>
  20 <> 3 <> 9 <> 2 <> 69 <> 1 <> 0 <> 0 <>
  16 <> 3 <> 9 <> 2 <> 70 <> 1 <> 0 <> 0 <>
  20 <> 2 <> 0 <> 0 <> 71 <> 1 <> 0 <> 0 <> Nil{}

def grid_result_slots(state: GridCraftResult) -> List<&2, Slot>:
  GridCraftResult{+slots, grid, output, amount, ok} = state
  slots

def grid_result_grid(state: GridCraftResult) -> List<&2, Slot>:
  GridCraftResult{slots, +grid, output, amount, ok} = state
  grid

def grid_result_output(state: GridCraftResult) -> U32:
  GridCraftResult{slots, grid, +output, amount, ok} = state
  output

def grid_result_amount(state: GridCraftResult) -> U32:
  GridCraftResult{slots, grid, output, +amount, ok} = state
  amount

def grid_result_ok(state: GridCraftResult) -> Bool:
  GridCraftResult{slots, grid, output, amount, +ok} = state
  ok

def empty_grid() -> List<&2, Slot>:
  empty_slots(9n)

def shape_pattern(+index: Nat) -> List<&2, U32>:
  match index:
    case 0n:
      5 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> Nil{}
    case 1n:
      8 <> 0 <> 0 <> 0 <> 8 <> 0 <> 0 <> 0 <> 0 <> Nil{}
    case 2n:
      8 <> 8 <> 8 <> 8 <> 8 <> 8 <> 8 <> 8 <> 8 <> Nil{}
    case 3n:
      8 <> 8 <> 8 <> 0 <> 9 <> 0 <> 0 <> 9 <> 0 <> Nil{}
    case 4n:
      1 <> 1 <> 1 <> 0 <> 9 <> 0 <> 0 <> 9 <> 0 <> Nil{}
    case 5n:
      20 <> 20 <> 20 <> 0 <> 9 <> 0 <> 0 <> 9 <> 0 <> Nil{}
    case 6n:
      16 <> 16 <> 16 <> 0 <> 9 <> 0 <> 0 <> 9 <> 0 <> Nil{}
    case 7n:
      1 <> 1 <> 1 <> 1 <> 0 <> 1 <> 1 <> 1 <> 1 <> Nil{}
    case 8n:
      0 <> 14 <> 0 <> 0 <> 9 <> 0 <> 0 <> 0 <> 0 <> Nil{}
    case 9n:
      12 <> 12 <> 12 <> 8 <> 8 <> 8 <> 0 <> 0 <> 0 <> Nil{}
    case 10n:
      8 <> 8 <> 0 <> 8 <> 8 <> 0 <> 0 <> 0 <> 0 <> Nil{}
    case 11n:
      8 <> 8 <> 0 <> 0 <> 9 <> 0 <> 0 <> 9 <> 0 <> Nil{}
    case 12n:
      20 <> 0 <> 20 <> 0 <> 20 <> 0 <> 0 <> 0 <> 0 <> Nil{}
    case 13n:
      0 <> 8 <> 0 <> 0 <> 8 <> 0 <> 0 <> 9 <> 0 <> Nil{}
    case 14n:
      0 <> 1 <> 0 <> 0 <> 1 <> 0 <> 0 <> 9 <> 0 <> Nil{}
    case 15n:
      0 <> 20 <> 0 <> 0 <> 20 <> 0 <> 0 <> 9 <> 0 <> Nil{}
    case 16n:
      0 <> 16 <> 0 <> 0 <> 16 <> 0 <> 0 <> 9 <> 0 <> Nil{}
    case 17n:
      0 <> 9 <> 12 <> 9 <> 0 <> 12 <> 9 <> 0 <> 12 <> Nil{}
    case 18n:
      14 <> 0 <> 0 <> 9 <> 0 <> 0 <> 0 <> 0 <> 0 <> Nil{}
    case 19n:
      9 <> 20 <> 9 <> 20 <> 20 <> 20 <> 0 <> 20 <> 0 <> Nil{}
    case 20n:
      26 <> 26 <> 26 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> Nil{}
    case 21n:
      12 <> 12 <> 12 <> 12 <> 0 <> 12 <> 0 <> 0 <> 0 <> Nil{}
    case 22n:
      20 <> 0 <> 20 <> 20 <> 20 <> 20 <> 20 <> 20 <> 20 <> Nil{}
    case 23n:
      20 <> 20 <> 20 <> 20 <> 0 <> 20 <> 20 <> 0 <> 20 <> Nil{}
    case 24n:
      20 <> 0 <> 20 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> Nil{}
    case 21n+p:
      0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> Nil{}

def grid_matches(
  grid: List<&2, Slot>, pattern: List<&2, U32>
) -> Bool:
  match grid:
    case Nil{}:
      match pattern:
        case Nil{}:
          True{}
        case Con{head, tail}:
          False{}
    case Con{+head, +rest_grid}:
      match pattern:
        case Nil{}:
          False{}
        case Con{+expected, +rest_pattern}:
          +actual = Bool.pick(U32, U32.is_eq(slot_count_value(head), 0), 0, slot_item(head))
          Bool.and(U32.is_eq(actual, expected), grid_matches(rest_grid, rest_pattern))

def consume_grid(grid: List<&2, Slot>) -> List<&2, Slot>:
  match grid:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      +count = slot_count_value(head)
      +next_count = Bool.pick(U32, U32.is_gt(count, 1), U32.sub(count, 1), 0)
      +next_item = Bool.pick(U32, U32.is_eq(next_count, 0), 0, slot_item(head))
      Con{make_slot(next_item, next_count, slot_durability(head)), consume_grid(tail)}

def recipe_output(spec: Recipe) -> U32:
  Recipe{item_a, count_a, item_b, count_b, +output, output_count} = spec
  output

def recipe_amount(spec: Recipe) -> U32:
  Recipe{item_a, count_a, item_b, count_b, output, +output_count} = spec
  output_count

def craft_grid.commit(
  original: List<&2, Slot>, original_grid: List<&2, Slot>, updated: List<&2, Slot>,
  output: U32, amount: U32, room: Bool
) -> GridCraftResult:
  match room:
    case True{}:
      GridCraftResult{updated, consume_grid(original_grid), output, amount, True{}}
    case False{}:
      GridCraftResult{original, original_grid, output, amount, False{}}

def craft_grid.after(
  +original: List<&2, Slot>, grid: List<&2, Slot>, +output: U32, +amount: U32,
  matched: Bool
) -> GridCraftResult:
  match matched:
    case False{}:
      GridCraftResult{original, grid, output, amount, False{}}
    case True{}:
      +added = add_items(original, output, amount)
      craft_grid.commit(original, grid, add_slots(added), output, amount, U32.is_eq(add_remaining(added), 0))

def craft_grid.spec(
  original: List<&2, Slot>, +grid: List<&2, Slot>, +spec: Recipe,
  pattern: List<&2, U32>
) -> GridCraftResult:
  +matched = grid_matches(grid, pattern)
  craft_grid.after(original, grid, recipe_output(spec), recipe_amount(spec), matched)

def craft_grid.if(
  slots: List<&2, Slot>, grid: List<&2, Slot>, +index: Nat, valid: Bool
) -> GridCraftResult:
  match valid:
    case False{}:
      GridCraftResult{slots, grid, 0, 0, False{}}
    case True{}:
      craft_grid.spec(slots, grid, recipe(index), shape_pattern(index))

def craft_grid(
  slots: List<&2, Slot>, grid: List<&2, Slot>, +index: Nat
) -> GridCraftResult:
  craft_grid.if(slots, grid, index, Nat.is_lt(index, 25n))

def craft.finalize.if(
  original: List<&2, Slot>, slots: List<&2, Slot>, remaining: U32, valid: Bool
) -> InventoryResult:
  match valid:
    case True{}:
      result(slots, True{})
    case False{}:
      result(original, False{})

def craft.finalize(original: List<&2, Slot>, slots: List<&2, Slot>, +remaining: U32) -> InventoryResult:
  craft.finalize.if(original, slots, remaining, U32.is_eq(remaining, 0))

def craft.after(
  original: List<&2, Slot>, slots: List<&2, Slot>, output: U32, output_count: U32,
  ingredients_ok: Bool
) -> InventoryResult:
  match ingredients_ok:
    case False{}:
      result(original, False{})
    case True{}:
      +added = add_items(slots, output, output_count)
      craft.finalize(original, add_slots(added), add_remaining(added))

def craft.spec(+slots: List<&2, Slot>, spec: Recipe) -> InventoryResult:
  Recipe{item_a, count_a, item_b, count_b, output, output_count} = spec
  +first = remove_items(slots, item_a, count_a)
  +second = remove_items(remove_slots(first), item_b, count_b)
  +ingredients_ok = Bool.and(U32.is_eq(remove_remaining(first), 0), U32.is_eq(remove_remaining(second), 0))
  craft.after(slots, remove_slots(second), output, output_count, ingredients_ok)

def craft.if(slots: List<&2, Slot>, +index: Nat, valid: Bool) -> InventoryResult:
  match valid:
    case False{}:
      result(slots, False{})
    case True{}:
      +spec = recipe(index)
      craft.spec(slots, spec)

def craft(slots: List<&2, Slot>, +index: Nat) -> InventoryResult:
  craft.if(slots, index, Nat.is_lt(index, 25n))

# --- a stack on the cursor ------------------------------------------------------
#
# An inventory screen moves items with a stack held on the cursor, and a click is a
# transition on two stacks: the slot's and the cursor's. These are the clicks of the game
# this one is modelled on.
#
# The left button takes the whole slot onto an empty cursor, puts the whole cursor into an
# empty slot, tops the slot up from the cursor when both hold the same item, and swaps the
# two otherwise. The right button takes the larger half of the slot onto an empty cursor,
# and puts one item from the cursor into a slot that is empty or holds the same item with
# room; onto a different item it swaps, and onto a full stack of the same it does nothing.
# A tool wears, so two of them are never one stack: they swap.
type Clicked is Data:
  Clicked{slot: Slot, held: Slot}

def clicked_slot(state: Clicked) -> Slot:
  Clicked{slot, held} = state
  slot

def clicked_held(state: Clicked) -> Slot:
  Clicked{slot, held} = state
  held

def stackable(+item: U32) -> Bool:
  U32.is_eq(tool_max_durability(item), 0)

# A stack of nothing is the empty slot, whatever item it was a stack of.
def stack(+item: U32, +count: U32, +durability: U32) -> Slot:
  Bool.pick(Slot, U32.is_eq(count, 0), make_slot(0, 0, 0), make_slot(item, count, durability))

def click.left(+si: U32, +sc: U32, +sd: U32, +hi: U32, +hc: U32, +hd: U32) -> Clicked:
  +same = Bool.and(Bool.and(U32.is_ne(sc, 0), U32.is_ne(hc, 0)), Bool.and(U32.is_eq(si, hi), stackable(si)))
  +moved = U32.min(hc, U32.sub(max_stack(), U32.min(sc, max_stack())))
  Bool.pick(Clicked, same,
    Clicked{stack(si, U32.add(sc, moved), sd), stack(hi, U32.sub(hc, moved), hd)},
    Clicked{stack(hi, hc, hd), stack(si, sc, sd)})

def click.right(+si: U32, +sc: U32, +sd: U32, +hi: U32, +hc: U32, +hd: U32) -> Clicked:
  +free = U32.is_eq(sc, 0)
  +alike = Bool.and(Bool.not(free), U32.is_eq(si, hi))
  +room = Bool.or(free, Bool.and(alike, Bool.and(stackable(si), U32.is_lt(sc, max_stack()))))
  +take = U32.div(U32.add(sc, 1), 2)
  Bool.pick(Clicked, U32.is_eq(hc, 0),
    Clicked{stack(si, U32.sub(sc, take), sd), stack(si, take, sd)},
    Bool.pick(Clicked, room,
      Clicked{stack(hi, U32.add(sc, 1), Bool.pick(U32, free, hd, sd)), stack(hi, U32.sub(hc, U32.min(hc, 1)), hd)},
      Bool.pick(Clicked, alike,
        Clicked{stack(si, sc, sd), stack(hi, hc, hd)},
        Clicked{stack(hi, hc, hd), stack(si, sc, sd)})))

# One click on a slot with `held` on the cursor: the slot and the cursor after it.
def click(slot: Slot, held: Slot, right: Bool) -> Clicked:
  Slot{+si, +sc, +sd} = slot
  Slot{+hi, +hc, +hd} = held
  Bool.pick(Clicked, right, click.right(si, sc, sd, hi, hc, hd), click.left(si, sc, sd, hi, hc, hd))

# --- crafting from a grid, onto the cursor --------------------------------------
#
# A crafting grid shows what it would make before anything is taken. The recipe a grid
# matches is the first whose shape it is, and 25 when it is none of them.
def craft_index.go(remaining: Nat, +index: Nat, +grid: List<&2, Slot>) -> Nat:
  match remaining:
    case 0n:
      25n
    case 1n+rest:
      Bool.pick(Nat, grid_matches(grid, shape_pattern(index)), index,
        craft_index.go(rest, Nat.add(index, 1n), grid))

def craft_index(+grid: List<&2, Slot>) -> Nat:
  craft_index.go(25n, 0n, grid)

# What the grid would make: the stack that comes out, or the empty slot.
def craft_preview.at(+found: Bool, spec: Recipe) -> Slot:
  Recipe{item_a, count_a, item_b, count_b, +output, +output_count} = spec
  Bool.pick(Slot, found, make_slot(output, output_count, tool_max_durability(output)), make_slot(0, 0, 0))

def craft_preview(+grid: List<&2, Slot>) -> Slot:
  craft_preview.at(Nat.is_lt(craft_index(grid), 25n), recipe(craft_index(grid)))

type Crafted is Data:
  Crafted{grid: List<&2, Slot>, held: Slot, ok: Bool}

def crafted_grid(state: Crafted) -> List<&2, Slot>:
  Crafted{grid, held, ok} = state
  grid

def crafted_held(state: Crafted) -> Slot:
  Crafted{grid, held, ok} = state
  held

def crafted_ok(state: Crafted) -> Bool:
  Crafted{grid, held, ok} = state
  ok

def craft_take.at(taken: Bool, +grid: List<&2, Slot>, +made: Slot, +held: Slot) -> Crafted:
  match taken:
    case True{}:
      Crafted{consume_grid(grid),
        make_slot(slot_item(made), U32.add(slot_count_value(made), slot_count_value(held)), slot_durability(made)),
        True{}}
    case False{}:
      Crafted{grid, held, False{}}

# Taking what the grid makes onto the cursor: one of each ingredient is spent and the
# result is on the cursor. It is refused, and nothing is spent, when the grid makes nothing
# or the cursor holds something the result cannot join.
def craft_take.made(+grid: List<&2, Slot>, +made: Slot, +held: Slot) -> Crafted:
  +free = U32.is_eq(slot_count_value(held), 0)
  +joins = Bool.and(Bool.and(U32.is_eq(slot_item(held), slot_item(made)), stackable(slot_item(made))),
    U32.is_le(U32.add(slot_count_value(held), slot_count_value(made)), max_stack()))
  craft_take.at(Bool.and(U32.is_ne(slot_count_value(made), 0), Bool.or(free, joins)), grid, made, held)

def craft_take(+grid: List<&2, Slot>, +held: Slot) -> Crafted:
  craft_take.made(grid, craft_preview(grid), held)

def can_collect_block(+block: U32, +y: Nat) -> Bool:
  +utility = Bool.or(Bool.or(U32.is_eq(block, 25), U32.is_eq(block, 26)), U32.is_eq(block, 27))
  Bool.and(Bool.or(utility, Bool.or(Bool.or(Bool.or(is_block_item(block), U32.is_eq(block, 11)), U32.is_eq(block, 13)), Bool.or(Bool.or(U32.is_eq(block, 14), U32.is_eq(block, 15)), Bool.or(U32.is_eq(block, 22), U32.is_eq(block, 23))))), Nat.is_gt(y, 0n))

def is_placeable(+item: U32) -> Bool:
  +utility = Bool.or(Bool.or(U32.is_eq(item, 10), U32.is_eq(item, 40)), U32.is_eq(item, 43))
  Bool.or(utility, Bool.or(Bool.or(Bool.or(Bool.or(is_block_item(item), U32.is_eq(item, 21)), U32.is_eq(item, 22)), U32.is_eq(item, 23)), U32.is_eq(item, 24)))

# The block an item puts in the world, or 0 for an item that places none. For the
# terrain blocks the item id is the block id; the rest are `mining_item.base` read the
# other way. The redstone items answer 0 here: `world/redstone.bend` owns the ids
# they place.
def placed_block(+item: U32) -> U32:
  Bool.pick(U32, Bool.and(U32.is_ne(item, 0), U32.is_lt(item, 7)), item,
    Bool.pick(U32, U32.is_eq(item, 10), 27,
      Bool.pick(U32, U32.is_eq(item, 40), 25,
        Bool.pick(U32, U32.is_eq(item, 43), 26,
          Bool.pick(U32, U32.is_eq(item, 31), 22,
            Bool.pick(U32, U32.is_eq(item, 32), 23,
              Bool.pick(U32, U32.is_eq(item, 21), 11,
                Bool.pick(U32, U32.is_eq(item, 22), 12,
                  Bool.pick(U32, U32.is_eq(item, 23), 13,
                    Bool.pick(U32, U32.is_eq(item, 24), 14, 0))))))))))

def can_place(
  +item: U32, target_empty: Bool, inside: Bool, overlaps_player: Bool
) -> Bool:
  Bool.and(Bool.and(Bool.and(is_placeable(item), target_empty), inside), Bool.not(overlaps_player))

def use_tool.if(item: U32, durability: U32, valid: Bool) -> ToolResult:
  match valid:
    case False{}:
      ToolResult{0, False{}, False{}}
    case True{}:
      +next = U32.sub(durability, 1)
      ToolResult{next, U32.is_eq(next, 0), True{}}

def use_tool(+item: U32, +durability: U32) -> ToolResult:
  +max = tool_max_durability(item)
  use_tool.if(item, durability,
    Bool.and(Bool.and(U32.is_ne(max, 0), U32.is_gt(durability, 0)), U32.is_le(durability, max)))

def use_tool_at.updated(
  tail: List<&2, Slot>, slot: Slot, +durability: U32, +broken: Bool
) -> InventoryResult:
  Slot{item, count, old_durability} = slot
  +replacement = Bool.pick(Slot, broken, make_slot(0, 0, 0), make_slot(item, count, durability))
  result(cons_slot(replacement, tail), True{})

def use_tool_at.finalize(
  original: List<&2, Slot>, tail: List<&2, Slot>, slot: Slot, used: ToolResult
) -> InventoryResult:
  ToolResult{durability, broken, valid} = used
  +updated = use_tool_at.updated(tail, slot, durability, broken)
  Bool.pick(InventoryResult, valid, updated, result(original, False{}))

def use_tool_at.at(slots: List<&2, Slot>, +index: Nat) -> InventoryResult:
  match slots:
    case Nil{}:
      result(Nil{}, False{})
    case Con{+head, +tail}:
      match index:
        case 0n:
          use_tool_at.finalize(slots, tail, head,
            use_tool(slot_item(head), slot_durability(head)))
        case 1n+p:
          +rest = use_tool_at.at(tail, p)
          result(cons_slot(head, inventory_slots(rest)), inventory_ok(rest))

def use_tool_at(slots: List<&2, Slot>, +index: Nat) -> InventoryResult:
  use_tool_at.at(slots, index)

def tool_level(+item: U32) -> U32:
  Bool.pick(U32, U32.is_eq(item, 19), 4,
    Bool.pick(U32, U32.is_eq(item, 18), 3,
      Bool.pick(U32, U32.is_eq(item, 17), 2,
        Bool.pick(U32, U32.is_eq(item, 11), 1, 0))))

def mining_block(+block: U32) -> Bool:
  +basic = Bool.or(Bool.or(U32.is_eq(block, 1), U32.is_eq(block, 2)),
    Bool.or(U32.is_eq(block, 3), U32.is_eq(block, 4)))
  +ores = Bool.or(Bool.or(U32.is_eq(block, 5), U32.is_eq(block, 6)),
    Bool.or(U32.is_eq(block, 8), U32.is_eq(block, 9)))
  +special = Bool.or(Bool.or(U32.is_eq(block, 10), U32.is_eq(block, 11)),
    Bool.or(Bool.or(U32.is_eq(block, 12), U32.is_eq(block, 13)), Bool.or(Bool.or(U32.is_eq(block, 14), U32.is_eq(block, 15)), Bool.or(Bool.or(U32.is_eq(block, 16), U32.is_eq(block, 17)), Bool.or(U32.is_eq(block, 18), Bool.or(U32.is_eq(block, 19), U32.is_eq(block, 20)))))))
  +utility = Bool.or(Bool.or(U32.is_eq(block, 25), U32.is_eq(block, 26)), U32.is_eq(block, 27))
  Bool.or(Bool.or(Bool.or(basic, ores), special), Bool.or(Bool.or(U32.is_eq(block, 22), U32.is_eq(block, 23)), utility))

def mining_level(+block: U32) -> U32:
  Bool.pick(U32, U32.is_eq(block, 23), 4,
    Bool.pick(U32, U32.is_eq(block, 10), 3,
      Bool.pick(U32, U32.is_eq(block, 9), 2,
        Bool.pick(U32, Bool.or(Bool.or(U32.is_eq(block, 1), U32.is_eq(block, 8)), U32.is_eq(block, 22)), 1, 0))))

def can_mine(+item: U32, +block: U32) -> Bool:
  Bool.and(mining_block(block), U32.is_ge(tool_level(item), mining_level(block)))

def mining_duration.tool(
  +item: U32, hand: F32, wooden: F32, stone: F32, iron: F32, diamond: F32
) -> F32:
  Bool.pick(F32, U32.is_eq(item, 19), diamond,
    Bool.pick(F32, U32.is_eq(item, 18), iron,
      Bool.pick(F32, U32.is_eq(item, 17), stone,
        Bool.pick(F32, U32.is_eq(item, 11), wooden, hand))))

# A tool in hand that does not suit what is in front of it is worse than a bare
# hand, the way it is in vanilla: the axe on stone, the shovel on wood.
def mining_duration.mismatched(+item: U32) -> F32:
  Bool.pick(F32, U32.is_eq(tool_kind(item), 0), 0.0, 5.0)

# The tiers below the pickaxe are the shovels, the axes and the shears: what a
# tier is worth is its speed on its own material, and shears are the best there
# is on leaves whatever their number says.
def mining_duration.row(
  +tier: U32, +hand: F32, +wooden: F32, +stone: F32, +iron: F32, +diamond: F32
) -> F32:
  Bool.pick(F32, U32.is_eq(tier, 5), diamond,
    Bool.pick(F32, U32.is_eq(tier, 4), diamond,
      Bool.pick(F32, U32.is_eq(tier, 3), iron,
        Bool.pick(F32, U32.is_eq(tier, 2), stone,
          Bool.pick(F32, U32.is_eq(tier, 1), wooden, hand)))))

def mining_duration.suited(
  suits: Bool, +item: U32, +tier: U32,
  +hand: F32, +wooden: F32, +stone: F32, +iron: F32, +diamond: F32
) -> F32:
  match suits:
    case True{}:
      mining_duration.row(tier, hand, wooden, stone, iron, diamond)
    case False{}:
      mining_duration.mismatched(item)

# One material's row of speeds, asked of the tool in hand: the row belongs to
# the tool that suits it, and a hand reads the row's own hand figure.
def mining_duration.for_block(
  +item: U32, +block: U32, +hand: F32, +wooden: F32, +stone: F32, +iron: F32, +diamond: F32
) -> F32:
  +kind = tool_kind(item)
  mining_duration.suited(
    Bool.or(U32.is_eq(kind, 0), U32.is_eq(kind, suited_kind(block))),
    item,
    tool_tier(item),
    hand, wooden, stone, iron, diamond)

def mining_duration.material(+item: U32, +block: U32) -> F32:
  +obsidian = U32.is_eq(block, 23)
  +diamond_ore = U32.is_eq(block, 10)
  +iron_ore = U32.is_eq(block, 9)
  +stone = Bool.or(Bool.or(U32.is_eq(block, 1), U32.is_eq(block, 8)),
    Bool.or(U32.is_eq(block, 11), U32.is_eq(block, 22)))
  +wood = U32.is_eq(block, 5)
  +dirt = Bool.or(Bool.or(U32.is_eq(block, 2), U32.is_eq(block, 3)),
    Bool.or(U32.is_eq(block, 6), U32.is_eq(block, 20)))
  +leaves = U32.is_eq(block, 4)
  Bool.pick(F32, obsidian,
    mining_duration.for_block(item, block, 0.0, 0.0, 0.0, 0.0, 9.0),
    Bool.pick(F32, diamond_ore,
      mining_duration.for_block(item, block, 0.0, 0.0, 0.0, 1.1, 0.7),
      Bool.pick(F32, iron_ore,
        mining_duration.for_block(item, block, 0.0, 0.0, 2.0, 0.8, 0.6),
        Bool.pick(F32, stone,
          mining_duration.for_block(item, block, 0.45, 1.5, 0.8, 0.55, 0.4),
          Bool.pick(F32, wood,
            mining_duration.for_block(item, block, 1.2, 0.9, 0.55, 0.35, 0.25),
            Bool.pick(F32, dirt,
              mining_duration.for_block(item, block, 0.75, 0.55, 0.35, 0.22, 0.15),
              Bool.pick(F32, leaves,
                mining_duration.for_block(item, block, 0.3, 0.25, 0.2, 0.15, 0.12),
                mining_duration.for_block(item, block, 0.35, 0.3, 0.25, 0.2, 0.15))))))))

def mining_duration(+item: U32, +block: U32) -> F32:
  Bool.pick(F32, can_mine(item, block), mining_duration.material(item, block), 0.0)

def mining_item.base(+block: U32) -> U32:
  Bool.pick(U32, U32.is_eq(block, 27), 10,
   Bool.pick(U32, U32.is_eq(block, 26), 43,
    Bool.pick(U32, U32.is_eq(block, 25), 40,
    Bool.pick(U32, U32.is_eq(block, 20), 2,
    Bool.pick(U32, U32.is_eq(block, 14), 24,
    Bool.pick(U32, U32.is_eq(block, 15), 24,
    Bool.pick(U32, U32.is_eq(block, 13), 23,
      Bool.pick(U32, U32.is_eq(block, 12), 22,
        Bool.pick(U32, U32.is_eq(block, 11), 21,
          Bool.pick(U32, U32.is_eq(block, 23), 32,
            Bool.pick(U32, U32.is_eq(block, 22), 31,
              Bool.pick(U32, U32.is_eq(block, 10), 16,
            Bool.pick(U32, U32.is_eq(block, 9), 15,
              Bool.pick(U32, U32.is_eq(block, 8), 14,
              # The redstone blocks, items 51 through 62, in the same order. A
              # piston head belongs to its piston and drops nothing. Without
              # these cases `mining_item` fell to the terrain default and
              # dropped an unrelated item (a wire as an empty bucket, a lamp as
              # obsidian, a redstone block as cobblestone).
              Bool.pick(U32, U32.is_eq(block, 28), 51,
              Bool.pick(U32, U32.is_eq(block, 29), 52,
              Bool.pick(U32, U32.is_eq(block, 30), 53,
              Bool.pick(U32, U32.is_eq(block, 31), 54,
              Bool.pick(U32, U32.is_eq(block, 32), 55,
              Bool.pick(U32, U32.is_eq(block, 33), 56,
              Bool.pick(U32, U32.is_eq(block, 34), 57,
              Bool.pick(U32, U32.is_eq(block, 35), 58,
              Bool.pick(U32, U32.is_eq(block, 36), 59,
              Bool.pick(U32, U32.is_eq(block, 37), 60,
              Bool.pick(U32, U32.is_eq(block, 38), 0,
              Bool.pick(U32, U32.is_eq(block, 39), 61,
              Bool.pick(U32, U32.is_eq(block, 40), 62, block)))))))))))))))))))))))))))

def mining_item(+block: U32) -> U32:
  +seeds = Bool.or(Bool.or(U32.is_eq(block, 16), U32.is_eq(block, 17)), U32.is_eq(block, 18))
  +wheat = U32.is_eq(block, 19)
  Bool.pick(U32, seeds, 25, Bool.pick(U32, wheat, 26, mining_item.base(block)))

def mine_drop(+item: U32, +block: U32, +y: Nat) -> MiningResult:
  MiningResult{mining_item(block), 1,
    Bool.and(Nat.is_gt(y, 0n), can_mine(item, block))}

def mine_collect.if(
  original: List<&2, Slot>, mining: MiningResult
) -> InventoryResult:
  MiningResult{item, amount, valid} = mining
  match valid:
    case False{}:
      result(original, False{})
    case True{}:
      pickup(original, item, U32.to_nat(amount))

def mine_collect(
  slots: List<&2, Slot>, +item: U32, +block: U32, +y: Nat
) -> InventoryResult:
  mine_collect.if(slots, mine_drop(item, block, y))

def leaf_bonus(+x: Nat, +y: Nat, +z: Nat) -> Bool:
  Nat.is_eq(Nat.mod(Nat.add(Nat.add(x, z), Nat.mul(y, 7n)), 8n), 0n)

def mine_drop_at(+item: U32, +block: U32, +x: Nat, +y: Nat, +z: Nat) -> MiningResult:
  +apple = Bool.and(U32.is_eq(block, 4), leaf_bonus(x, y, z))
  +drop_item = Bool.pick(U32, apple, 42, mining_item(block))
  MiningResult{drop_item, 1,
    Bool.and(Nat.is_gt(y, 0n), can_mine(item, block))}

def mine_collect_at(
  slots: List<&2, Slot>, +item: U32, +block: U32, +x: Nat, +y: Nat, +z: Nat
) -> InventoryResult:
  mine_collect.if(slots, mine_drop_at(item, block, x, y, z))

def place.valid(+original: List<&2, Slot>, +index: Nat, valid: Bool) -> InventoryResult:
  match valid:
    case False{}:
      result(original, False{})
    case True{}:
      consume(original, index, 1n)

def place.found(
  +original: List<&2, Slot>, +index: Nat, +item: U32,
  target_empty: Bool, inside: Bool, overlaps_player: Bool, slot: Slot
) -> InventoryResult:
  +valid = Bool.and(
    U32.is_eq(slot_item(slot), item),
    can_place(item, target_empty, inside, overlaps_player)
  )
  place.valid(original, index, valid)

def place.lookup(
  +original: List<&2, Slot>, +index: Nat, +item: U32,
  target_empty: Bool, inside: Bool, overlaps_player: Bool,
  lookup_result: Lookup
) -> InventoryResult:
  match lookup_result:
    case Missing{}:
      result(original, False{})
    case Found{slot}:
      place.found(original, index, item, target_empty, inside, overlaps_player, slot)

def place(
  +slots: List<&2, Slot>, +index: Nat, +item: U32,
  target_empty: Bool, inside: Bool, overlaps_player: Bool
) -> InventoryResult:
  place.lookup(slots, index, item, target_empty, inside, overlaps_player, lookup(slots, index))

def interaction.finish(
  +edit: WorldState.Edit, original: List<&2, Slot>, state: InventoryResult
) -> InteractionResult:
  InventoryResult{slots, ok} = state
  Bool.pick(
    InteractionResult,
    ok,
    InteractionResult{edit, slots, True{}},
    InteractionResult{edit, original, False{}}
  )

def mine_interaction(
  +slots: List<&2, Slot>, +tool: U32, +block: U32,
  +x: Nat, +y: Nat, +z: Nat
) -> InteractionResult:
  +edit = WorldState.make_edit(x, y, z, 0)
  interaction.finish(edit, slots, mine_collect(slots, tool, block, y))

def mine_interaction_at_finish_used(
  +edit: WorldState.Edit, original: List<&2, Slot>, collected_ok: Bool,
  state: InventoryResult
) -> InteractionResult:
  InventoryResult{used_slots, used_ok} = state
  +valid = Bool.and(collected_ok, used_ok)
  Bool.pick(
    InteractionResult,
    valid,
    InteractionResult{edit, used_slots, True{}},
    InteractionResult{edit, original, False{}}
  )

def mine_interaction_at_finish_hand(
  +edit: WorldState.Edit, original: List<&2, Slot>, slots: List<&2, Slot>,
  collected_ok: Bool
) -> InteractionResult:
  Bool.pick(
    InteractionResult,
    collected_ok,
    InteractionResult{edit, slots, True{}},
    InteractionResult{edit, original, False{}}
  )

def mine_interaction_at_finish_tool(
  +edit: WorldState.Edit, original: List<&2, Slot>, +index: Nat,
  slots: List<&2, Slot>, collected_ok: Bool
) -> InteractionResult:
  +used = use_tool_at(slots, index)
  mine_interaction_at_finish_used(edit, original, collected_ok, used)

def mine_interaction_at_finish_mode(
  +edit: WorldState.Edit, original: List<&2, Slot>, +index: Nat,
  slots: List<&2, Slot>, collected_ok: Bool, tool_empty: Bool
) -> InteractionResult:
  match tool_empty:
    case True{}:
      mine_interaction_at_finish_hand(edit, original, slots, collected_ok)
    case False{}:
      mine_interaction_at_finish_tool(edit, original, index, slots, collected_ok)

def mine_interaction_at_finish_collected(
  +edit: WorldState.Edit, original: List<&2, Slot>, +index: Nat, +tool: U32,
  state: InventoryResult
) -> InteractionResult:
  InventoryResult{slots, collected_ok} = state
  mine_interaction_at_finish_mode(
    edit,
    original,
    index,
    slots,
    collected_ok,
    U32.is_eq(tool_max_durability(tool), 0)
  )

def mine_interaction_at.finish(
  +edit: WorldState.Edit, original: List<&2, Slot>, +index: Nat, +tool: U32,
  collected: InventoryResult
) -> InteractionResult:
  mine_interaction_at_finish_collected(edit, original, index, tool, collected)

def mine_interaction_at(
  +slots: List<&2, Slot>, +index: Nat, +tool: U32, +block: U32,
  +x: Nat, +y: Nat, +z: Nat
) -> InteractionResult:
  +edit = WorldState.make_edit(x, y, z, 0)
  mine_interaction_at.finish(edit, slots, index, tool, mine_collect_at(slots, tool, block, x, y, z))

def place_interaction(
  +slots: List<&2, Slot>, +index: Nat, +item: U32, +block: U32,
  +x: Nat, +y: Nat, +z: Nat,
  target_empty: Bool, inside: Bool, overlaps_player: Bool
) -> InteractionResult:
  +edit = WorldState.make_edit(x, y, z, block)
  interaction.finish(
    edit,
    slots,
    place(slots, index, item, target_empty, inside, overlaps_player)
  )

def bucket.finalize(
  +original: List<&2, Slot>, +index: Nat, replacement: Slot, valid: Bool
) -> InventoryResult:
  match valid:
    case False{}:
      result(original, False{})
    case True{}:
      result(replace_at(original, index, replacement), True{})

def bucket.lookup(
  +original: List<&2, Slot>, +index: Nat, +from_item: U32, +to_item: U32,
  lookup_result: Lookup
) -> InventoryResult:
  match lookup_result:
    case Missing{}:
      result(original, False{})
    case Found{slot}:
      Slot{+item, +count, +durability} = slot
      bucket.finalize(
        original,
        index,
        make_slot(to_item, count, durability),
        U32.is_eq(item, from_item)
      )

def fill_bucket_at(+slots: List<&2, Slot>, +index: Nat) -> InventoryResult:
  bucket.lookup(slots, index, 28, 29, lookup(slots, index))

def empty_bucket_at(+slots: List<&2, Slot>, +index: Nat) -> InventoryResult:
  bucket.lookup(slots, index, 29, 28, lookup(slots, index))

def fill_lava_bucket_at(+slots: List<&2, Slot>, +index: Nat) -> InventoryResult:
  bucket.lookup(slots, index, 28, 30, lookup(slots, index))

def empty_lava_bucket_at(+slots: List<&2, Slot>, +index: Nat) -> InventoryResult:
  bucket.lookup(slots, index, 30, 28, lookup(slots, index))
