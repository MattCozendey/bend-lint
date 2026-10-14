import Base

# Furnace item IDs are shared with world/inventory.bend:
# raw iron = 15, coal = 14, iron ingot = 20, sand = 6, glass = 40,
# cobblestone item = 31, stone = 1.

def smeltable(+item: U32) -> Bool:
  Bool.or(U32.is_eq(item, 15), Bool.or(U32.is_eq(item, 6), Bool.or(U32.is_eq(item, 31), U32.is_eq(item, 26))))

def smelt_output(+input: U32) -> U32:
  Bool.pick(U32, U32.is_eq(input, 15), 20,
    Bool.pick(U32, U32.is_eq(input, 6), 40,
      Bool.pick(U32, U32.is_eq(input, 31), 1, 41)))

type Furnace is Data:
  Furnace{input: U32, input_count: U32, fuel: U32, fuel_count: U32, output: U32, output_count: U32, progress: U32, burn: U32}

type FurnaceResult is Data:
  FurnaceResult{furnace: Furnace, ok: Bool}

type StepResult is Data:
  StepResult{furnace: Furnace, produced: Bool, ok: Bool}

type TransferResult is Data:
  TransferResult{furnace: Furnace, item: U32, amount: U32, ok: Bool}

def step_furnace(result: StepResult) -> Furnace:
  StepResult{furnace, produced, ok} = result
  furnace

def max_stack() -> U32:
  64

def smelt_time() -> U32:
  8

def empty() -> Furnace:
  Furnace{0, 0, 0, 0, 0, 0, 0, 0}

def load_input.finalize(original: Furnace, updated: Furnace, +valid: Bool) -> FurnaceResult:
  match valid:
    case True{}:
      FurnaceResult{updated, True{}}
    case False{}:
      FurnaceResult{original, False{}}

def load_input(+state: Furnace, +item: U32, +amount: Nat) -> FurnaceResult:
  Furnace{+input, +input_count, +fuel, +fuel_count, +output, +output_count, +progress, +burn} = state
  +same_item = Bool.or(U32.is_eq(input, 0), U32.is_eq(input, item))
  +space = U32.sub(max_stack(), input_count)
  +requested = U32.from_nat(amount)
  +valid = Bool.and(Bool.and(smeltable(item), Nat.is_gt(amount, 0n)),
    Bool.and(same_item, U32.is_le(requested, space)))
  +next_count = U32.add(input_count, requested)
  +next_input = Bool.pick(U32, U32.is_eq(input, 0), item, input)
  load_input.finalize(state, Furnace{next_input, next_count, fuel, fuel_count, output, output_count, progress, burn}, valid)

def load_fuel.finalize(original: Furnace, updated: Furnace, +valid: Bool) -> FurnaceResult:
  match valid:
    case True{}:
      FurnaceResult{updated, True{}}
    case False{}:
      FurnaceResult{original, False{}}

def load_fuel(+state: Furnace, +item: U32, +amount: Nat) -> FurnaceResult:
  Furnace{+input, +input_count, +fuel, +fuel_count, +output, +output_count, +progress, +burn} = state
  +same_fuel = Bool.or(U32.is_eq(fuel, 0), U32.is_eq(fuel, item))
  +space = U32.sub(max_stack(), fuel_count)
  +requested = U32.from_nat(amount)
  +valid = Bool.and(Bool.and(U32.is_eq(item, 14), Nat.is_gt(amount, 0n)),
    Bool.and(same_fuel, U32.is_le(requested, space)))
  +next_fuel = Bool.pick(U32, U32.is_eq(fuel, 0), item, fuel)
  +next_count = U32.add(fuel_count, requested)
  load_fuel.finalize(state, Furnace{input, input_count, next_fuel, next_count, output, output_count, progress, burn}, valid)

def tick.finalize(original: Furnace, updated: Furnace, +valid: Bool, +produced: Bool) -> StepResult:
  match valid:
    case True{}:
      StepResult{updated, produced, True{}}
    case False{}:
      StepResult{original, False{}, False{}}

def tick(+state: Furnace) -> StepResult:
  Furnace{+input, +input_count, +fuel, +fuel_count, +output, +output_count, +progress, +burn} = state
  +recipe_out = smelt_output(input)
  +output_fits = Bool.or(U32.is_eq(output, 0), U32.is_eq(output, recipe_out))
  +has_input = Bool.and(Bool.and(Bool.and(smeltable(input), U32.is_gt(input_count, 0)), U32.is_lt(output_count, max_stack())), output_fits)
  +has_fuel = Bool.or(U32.is_gt(burn, 0), U32.is_gt(fuel_count, 0))
  +valid = Bool.and(has_input, has_fuel)
  +needs_fuel = U32.is_eq(burn, 0)
  +fuel_used = Bool.pick(U32, needs_fuel, 1, 0)
  +next_fuel_count = U32.sub(fuel_count, fuel_used)
  +next_burn = Bool.pick(U32, needs_fuel, smelt_time(), burn)
  +burn_left = U32.sub(next_burn, 1)
  +next_progress = U32.add(progress, 1)
  +produced = U32.is_ge(next_progress, smelt_time())
  +progress_left = Bool.pick(U32, produced, 0, next_progress)
  +next_input_count = Bool.pick(U32, produced, U32.sub(input_count, 1), input_count)
  +next_input = Bool.pick(U32, U32.is_eq(next_input_count, 0), 0, input)
  +next_output = Bool.pick(U32, U32.is_eq(output, 0), recipe_out, output)
  +next_output_count = Bool.pick(U32, produced, U32.add(output_count, 1), output_count)
  tick.finalize(state, Furnace{next_input, next_input_count, fuel, next_fuel_count, next_output, next_output_count, progress_left, burn_left}, valid, produced)

def take_output.finalize(original: Furnace, updated: Furnace, +item: U32, +amount: U32, +valid: Bool) -> TransferResult:
  match valid:
    case True{}:
      TransferResult{updated, item, amount, True{}}
    case False{}:
      TransferResult{original, 0, 0, False{}}

def clear_output(
  +input: U32, +input_count: U32, +fuel: U32, +fuel_count: U32,
  +progress: U32, +burn: U32
) -> Furnace:
  Furnace{input, input_count, fuel, fuel_count, 0, 0, progress, burn}

def take_output(+state: Furnace) -> TransferResult:
  Furnace{+input, +input_count, +fuel, +fuel_count, +output, +output_count, +progress, +burn} = state
  +valid = Bool.and(U32.is_ne(output, 0), U32.is_gt(output_count, 0))
  +updated = clear_output(input, input_count, fuel, fuel_count, progress, burn)
  take_output.finalize(state, updated, output, output_count, valid)
