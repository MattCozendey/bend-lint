import Base

# A chest holds nine generic slots. Non-tool items merge into existing
# stacks; damageable tools keep their exact durability and only use empty
# slots so the chest never repairs them.

type Slot is Data:
  Slot{item: U32, count: U32, durability: U32}

type DepositResult is Data:
  DepositResult{slots: List<&2, Slot>, ok: Bool}

type WithdrawResult is Data:
  WithdrawResult{slots: List<&2, Slot>, item: U32, amount: U32, durability: U32, ok: Bool}

type AddResult is Data:
  AddResult{slots: List<&2, Slot>, remaining: U32}

def chest_size() -> Nat:
  9n

def max_stack() -> U32:
  64

def empty_slot() -> Slot:
  Slot{0, 0, 0}

def empty_slots(+remaining: Nat) -> List<&2, Slot>:
  match remaining:
    case 0n:
      Nil{}
    case 1n+p:
      Con{empty_slot(), empty_slots(p)}

def empty() -> List<&2, Slot>:
  empty_slots(chest_size())

def make_slot(item: U32, count: U32, durability: U32) -> Slot:
  Slot{item, count, durability}

def cons_slot(slot: Slot, tail: List<&2, Slot>) -> List<&2, Slot>:
  Con{slot, tail}

def slot_item(slot: Slot) -> U32:
  Slot{+item, count, durability} = slot
  item

def slot_count_value(slot: Slot) -> U32:
  Slot{item, +count, durability} = slot
  count

def slot_durability(slot: Slot) -> U32:
  Slot{item, count, +durability} = slot
  durability

def deposit_slots(state: DepositResult) -> List<&2, Slot>:
  DepositResult{slots, ok} = state
  slots

def deposit_ok(state: DepositResult) -> Bool:
  DepositResult{slots, +ok} = state
  ok

def withdraw_slots(state: WithdrawResult) -> List<&2, Slot>:
  WithdrawResult{slots, item, amount, durability, ok} = state
  slots

def withdraw_item(state: WithdrawResult) -> U32:
  WithdrawResult{slots, +item, amount, durability, ok} = state
  item

def withdraw_amount(state: WithdrawResult) -> U32:
  WithdrawResult{slots, item, +amount, durability, ok} = state
  amount

def withdraw_durability(state: WithdrawResult) -> U32:
  WithdrawResult{slots, item, amount, +durability, ok} = state
  durability

def withdraw_ok(state: WithdrawResult) -> Bool:
  WithdrawResult{slots, item, amount, durability, +ok} = state
  ok

def add_slots(state: AddResult) -> List<&2, Slot>:
  AddResult{+slots, remaining} = state
  slots

def add_remaining(state: AddResult) -> U32:
  AddResult{slots, +remaining} = state
  remaining

def damageable(+item: U32) -> Bool:
  Bool.or(
    Bool.or(Bool.or(U32.is_eq(item, 11), U32.is_eq(item, 17)), U32.is_eq(item, 18)),
    Bool.or(
      Bool.or(Bool.or(U32.is_eq(item, 19), U32.is_eq(item, 27)), U32.is_eq(item, 33)),
      Bool.or(Bool.or(U32.is_eq(item, 34), U32.is_eq(item, 35)), Bool.or(U32.is_eq(item, 36), Bool.or(U32.is_eq(item, 37), U32.is_eq(item, 38))))
    )
  )

def add_existing(
  slots: List<&2, Slot>, +item: U32, +amount: U32
) -> AddResult:
  match slots:
    case Nil{}:
      AddResult{Nil{}, amount}
    case Con{+head, tail}:
      +same = Bool.and(U32.is_eq(slot_item(head), item), U32.is_lt(slot_count_value(head), max_stack()))
      +space = U32.sub(max_stack(), slot_count_value(head))
      +added = Bool.pick(U32, same, U32.min(amount, space), 0)
      +updated = Bool.pick(Slot, U32.is_ne(added, 0), make_slot(item, U32.add(slot_count_value(head), added), slot_durability(head)), head)
      +rest = add_existing(tail, item, U32.sub(amount, added))
      AddResult{Con{updated, add_slots(rest)}, add_remaining(rest)}

def add_empty(
  slots: List<&2, Slot>, +item: U32, +amount: U32
) -> AddResult:
  match slots:
    case Nil{}:
      AddResult{Nil{}, amount}
    case Con{+head, tail}:
      +slot_empty = Bool.and(U32.is_eq(slot_item(head), 0), U32.is_eq(slot_count_value(head), 0))
      +added = Bool.pick(U32, slot_empty, U32.min(amount, max_stack()), 0)
      +updated = Bool.pick(Slot, U32.is_ne(added, 0), make_slot(item, added, 0), head)
      +rest = add_empty(tail, item, U32.sub(amount, added))
      AddResult{Con{updated, add_slots(rest)}, add_remaining(rest)}

def bulk_deposit(
  slots: List<&2, Slot>, +item: U32, +count: U32, +durability: U32
) -> DepositResult:
  +first = add_existing(slots, item, count)
  +second = add_empty(add_slots(first), item, add_remaining(first))
  DepositResult{add_slots(second), U32.is_eq(add_remaining(second), 0)}

def tool_deposit.slots(
  slots: List<&2, Slot>, +item: U32, +count: U32, +durability: U32
) -> DepositResult:
  match slots:
    case Nil{}:
      DepositResult{Nil{}, U32.is_eq(count, 0)}
    case Con{+head, tail}:
      +slot_empty = Bool.and(U32.is_eq(slot_item(head), 0), U32.is_eq(slot_count_value(head), 0))
      +placing = Bool.pick(U32, Bool.and(slot_empty, U32.is_ne(count, 0)), U32.min(count, max_stack()), 0)
      +updated = Bool.pick(Slot, U32.is_ne(placing, 0), make_slot(item, placing, durability), head)
      +rest = tool_deposit.slots(tail, item, U32.sub(count, placing), durability)
      DepositResult{Con{updated, deposit_slots(rest)}, Bool.and(U32.is_eq(placing, count), deposit_ok(rest))}

def deposit.if(
  slots: List<&2, Slot>, +item: U32, +count: U32, +durability: U32, is_tool: Bool
) -> DepositResult:
  match is_tool:
    case True{}:
      tool_deposit.slots(slots, item, count, durability)
    case False{}:
      bulk_deposit(slots, item, count, durability)

def deposit(
  slots: List<&2, Slot>, +item: U32, +count: U32, +durability: U32
) -> DepositResult:
  +is_tool = damageable(item)
  deposit.if(slots, item, count, durability, is_tool)

def withdraw.head.if(
  tail: List<&2, Slot>, original: Slot, replacement: Slot,
  +item: U32, +amount: U32, +durability: U32, valid: Bool
) -> WithdrawResult:
  match valid:
    case True{}:
      WithdrawResult{Con{replacement, tail}, item, amount, durability, True{}}
    case False{}:
      WithdrawResult{Con{original, tail}, 0, 0, 0, False{}}

def withdraw.head(
  tail: List<&2, Slot>, +amount: U32, slot: Slot
) -> WithdrawResult:
  Slot{+item, +count, +durability} = slot
  +available = count
  +take = U32.min(amount, available)
  +left = U32.sub(available, take)
  +cleared = U32.is_eq(left, 0)
  +next_item = Bool.pick(U32, cleared, 0, item)
  +next_durability = Bool.pick(U32, cleared, 0, durability)
  +updated = make_slot(next_item, left, next_durability)
  +valid = Bool.and(U32.is_ne(item, 0), U32.is_ne(take, 0))
  withdraw.head.if(tail, make_slot(item, count, durability), updated, item, take, durability, valid)

def prepend_withdraw(head: Slot, state: WithdrawResult) -> WithdrawResult:
  WithdrawResult{+slots, +item, +amount, +durability, +ok} = state
  WithdrawResult{Con{head, slots}, item, amount, durability, ok}

def withdraw.at(
  slots: List<&2, Slot>, +index: Nat, +amount: U32
) -> WithdrawResult:
  match slots:
    case Nil{}:
      WithdrawResult{Nil{}, 0, 0, 0, False{}}
    case Con{+head, tail}:
      match index:
        case 0n:
          withdraw.head(tail, amount, head)
        case 1n+p:
          prepend_withdraw(head, withdraw.at(tail, p, amount))

def withdraw(slots: List<&2, Slot>, +index: Nat, +amount: U32) -> WithdrawResult:
  withdraw.at(slots, index, amount)
