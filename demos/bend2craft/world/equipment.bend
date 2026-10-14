import Base

type Equipment is Data:
  Equipment{offhand: U32, helmet: U32, chest: U32, legs: U32, boots: U32}

type EquipResult is Data:
  EquipResult{equipment: Equipment, ok: Bool}

type TakeResult is Data:
  TakeResult{equipment: Equipment, item: U32, ok: Bool}

def empty() -> Equipment:
  Equipment{0, 0, 0, 0, 0}

def equip_state(result: EquipResult) -> Equipment:
  EquipResult{+equipment, ok} = result
  equipment

def equip_ok(result: EquipResult) -> Bool:
  EquipResult{equipment, +ok} = result
  ok

def take_state(result: TakeResult) -> Equipment:
  TakeResult{+equipment, item, ok} = result
  equipment

def take_item(result: TakeResult) -> U32:
  TakeResult{equipment, +item, ok} = result
  item

def take_ok(result: TakeResult) -> Bool:
  TakeResult{equipment, item, +ok} = result
  ok

def slot_for_item(+item: U32) -> U32:
  Bool.pick(U32, U32.is_eq(item, 38), 0,
    Bool.pick(U32, U32.is_eq(item, 44), 1,
      Bool.pick(U32, U32.is_eq(item, 45), 2,
        Bool.pick(U32, U32.is_eq(item, 46), 3,
          Bool.pick(U32, U32.is_eq(item, 47), 4, 99)))))

def equip_slot(state: Equipment, +slot: Nat, +item: U32) -> Equipment:
  Equipment{offhand, helmet, chest, legs, boots} = state
  match slot:
    case 0n:
      Equipment{item, helmet, chest, legs, boots}
    case 1n:
      Equipment{offhand, item, chest, legs, boots}
    case 2n:
      Equipment{offhand, helmet, item, legs, boots}
    case 3n:
      Equipment{offhand, helmet, chest, item, boots}
    case 4n:
      Equipment{offhand, helmet, chest, legs, item}
    case 5n+p:
      state

def equip.if(state: Equipment, +item: U32, +slot: Nat, valid: Bool) -> EquipResult:
  match valid:
    case True{}:
      EquipResult{equip_slot(state, slot, item), True{}}
    case False{}:
      EquipResult{state, False{}}

def equip(state: Equipment, +item: U32) -> EquipResult:
  +slot = slot_for_item(item)
  equip.if(state, item, U32.to_nat(slot), U32.is_lt(slot, 5))

def take_slot(state: Equipment, +slot: Nat) -> TakeResult:
  Equipment{+offhand, +helmet, +chest, +legs, +boots} = state
  match slot:
    case 0n:
      TakeResult{Equipment{0, helmet, chest, legs, boots}, offhand, U32.is_ne(offhand, 0)}
    case 1n:
      TakeResult{Equipment{offhand, 0, chest, legs, boots}, helmet, U32.is_ne(helmet, 0)}
    case 2n:
      TakeResult{Equipment{offhand, helmet, 0, legs, boots}, chest, U32.is_ne(chest, 0)}
    case 3n:
      TakeResult{Equipment{offhand, helmet, chest, 0, boots}, legs, U32.is_ne(legs, 0)}
    case 4n:
      TakeResult{Equipment{offhand, helmet, chest, legs, 0}, boots, U32.is_ne(boots, 0)}
    case 5n+p:
      TakeResult{state, 0, False{}}

def armor_value(+item: U32) -> U32:
  Bool.pick(U32, U32.is_eq(item, 45), 3,
    Bool.pick(U32, U32.is_eq(item, 46), 2,
      Bool.pick(U32, Bool.or(U32.is_eq(item, 44), U32.is_eq(item, 47)), 1, 0)))

def armor_defense(state: Equipment) -> U32:
  Equipment{offhand, +helmet, +chest, +legs, +boots} = state
  U32.add(U32.add(armor_value(helmet), armor_value(chest)), U32.add(armor_value(legs), armor_value(boots)))

def blocks_damage(state: Equipment) -> Bool:
  Equipment{+offhand, helmet, chest, legs, boots} = state
  U32.is_eq(offhand, 38)
