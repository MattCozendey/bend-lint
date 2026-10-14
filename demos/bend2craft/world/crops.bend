import Base
import ./farmland.bend as Farmland

type Crop is Data:
  Crop{x: Nat, y: Nat, z: Nat, stage: U32, age: Nat}

type State is Data:
  State{crops: List<&2, Crop>}

type CropResult is Data:
  CropResult{state: State, ok: Bool}

type HarvestResult is Data:
  HarvestResult{state: State, seeds: U32, wheat: U32, ok: Bool}

def empty() -> State:
  State{Nil{}}

def entries(state: State) -> List<&2, Crop>:
  State{crops} = state
  crops

def same_crop(crop: Crop, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Crop{+cx, +cy, +cz, stage, age} = crop
  Bool.and(Bool.and(Nat.is_eq(cx, x), Nat.is_eq(cy, y)), Nat.is_eq(cz, z))

def contains(crops: List<&2, Crop>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  match crops:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Bool.or(same_crop(head, x, y, z), contains(tail, x, y, z))

def plant(+state: State, +x: Nat, +y: Nat, +z: Nat, +ground: U32, +occupied: U32) -> CropResult:
  State{+stored} = state
  +valid_ground = U32.is_eq(ground, 20)
  +valid = Bool.and(Bool.and(valid_ground, U32.is_eq(occupied, 0)), Bool.not(contains(stored, x, y, z)))
  Bool.pick(CropResult, valid, CropResult{State{Con{Crop{x, y, z, 16, 0n}, stored}}, True{}}, CropResult{state, False{}})

def next_stage(+stage: U32, +age: Nat) -> U32:
  Bool.pick(U32, Bool.and(U32.is_lt(stage, 19), Nat.is_ge(age, 4n)), U32.add(stage, 1), stage)

def next_age(+stage: U32, +age: Nat) -> Nat:
  Bool.pick(Nat, Bool.and(U32.is_lt(stage, 19), Nat.is_ge(age, 4n)), 0n, Nat.add(age, 1n))

def tick_entries(+entries: List<&2, Crop>, +steps: Nat) -> List<&2, Crop>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Crop{+x, +y, +z, +stage, +age} = head
      +next_age_value = Nat.add(age, steps)
      +next_stage_value = next_stage(stage, next_age_value)
      +remaining_age = Bool.pick(Nat, U32.is_ne(next_stage_value, stage), 0n, next_age_value)
      Con{Crop{x, y, z, next_stage_value, remaining_age}, tick_entries(tail, steps)}

def tick(+state: State, +steps: Nat) -> State:
  State{+stored} = state
  State{tick_entries(stored, steps)}

def tick_entries_farmland(
  entries: List<&2, Crop>, +steps: Nat, +farmland: Farmland.State
) -> List<&2, Crop>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Crop{+x, +y, +z, +stage, +age} = head
      +moisture = Farmland.moisture_at(farmland, x, Nat.sub(y, 1n), z)
      +growing = U32.is_gt(moisture, 0)
      +next_age_value = Bool.pick(Nat, growing, Nat.add(age, steps), age)
      +next_stage_value = next_stage(stage, next_age_value)
      +remaining_age = Bool.pick(Nat, U32.is_ne(next_stage_value, stage), 0n, next_age_value)
      Con{Crop{x, y, z, next_stage_value, remaining_age}, tick_entries_farmland(tail, steps, farmland)}

def tick_with_farmland(+state: State, +steps: Nat, +farmland: Farmland.State) -> State:
  State{+stored} = state
  State{tick_entries_farmland(stored, steps, farmland)}

def crop_block(crop: Crop) -> U32:
  Crop{x, y, z, stage, age} = crop
  stage

def remove_entries(entries: List<&2, Crop>, +x: Nat, +y: Nat, +z: Nat) -> List<&2, Crop>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Bool.pick(List<&2, Crop>, same_crop(head, x, y, z), tail,
        Con{head, remove_entries(tail, x, y, z)})

def remove(+state: State, +x: Nat, +y: Nat, +z: Nat) -> State:
  State{+stored} = state
  State{remove_entries(stored, x, y, z)}

def harvest_entries.state(result: HarvestResult) -> List<&2, Crop>:
  HarvestResult{state, seeds, wheat, ok} = result
  entries(state)

def harvest_entries(
  entries: List<&2, Crop>, +x: Nat, +y: Nat, +z: Nat
) -> HarvestResult:
  match entries:
    case Nil{}:
      HarvestResult{State{Nil{}}, 0, 0, False{}}
    case Con{+head, +tail}:
      Crop{+cx, +cy, +cz, +stage, +age} = head
      +same = Bool.and(Bool.and(Nat.is_eq(cx, x), Nat.is_eq(cy, y)), Nat.is_eq(cz, z))
      +rest = harvest_entries(tail, x, y, z)
      +ripe = U32.is_eq(stage, 19)
      +success = Bool.and(same, ripe)
      +rest_entries = harvest_entries.state(rest)
      +next_entries = Bool.pick(List<&2, Crop>, success, rest_entries, Con{head, rest_entries})
      HarvestResult{State{next_entries}, Bool.pick(U32, success, 1, 0), Bool.pick(U32, success, 1, 0), success}

def harvest(+state: State, +x: Nat, +y: Nat, +z: Nat) -> HarvestResult:
  +result = harvest_entries(entries(state), x, y, z)
  result
