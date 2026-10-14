import Base
import ./inventory.bend as Inventory

# How a dig goes: a block comes away when the dig button has been held on it for as long as
# `Inventory.mining_duration` says with what is in hand, as in the browser; looking at another
# cell or letting go starts over, and a block the hand cannot break gets nowhere. A client
# holds the `Dig` between ticks and asks `step` once a tick the button is held; what is dug
# and what comes of it is `Inventory.mine_interaction_at`'s.

# The block being dug: its cell, how long it has been dug, and how long it takes.
type Dig is Data:
  Dig{x: Nat, y: Nat, z: Nat, done: F32, need: F32}

# Nothing is being dug.
def resting() -> Dig:
  Dig{0n, 0n, 0n, 0.0, 0.0}

# How far a dig has got, over 256.
def progress(dig: Dig) -> U32:
  Dig{x, y, z, +done, +need} = dig
  Bool.pick(U32, F32.is_gt(need, 0.0),
    F32.to_u32(F32.min(F32.div(F32.mul(done, 256.0), F32.max(need, 0.001)), 256.0)), 0)

# What a tick of holding the dig button came to: the dig as it now stands, and whether the
# block comes away this tick.
type Mined is Data:
  Mined{dig: Dig, breaks: Bool}

def refused() -> Mined:
  Mined{resting(), False{}}

# The time the dig has on `cell` after a tick of `dt`: it carries over when it is the cell the
# last tick dug, and starts again when it is another.
def so_far(dig: Dig, +x: Nat, +y: Nat, +z: Nat, +dt: F32) -> F32:
  Dig{dx, dy, dz, done, need} = dig
  F32.add(
    Bool.pick(F32, Bool.and(Bool.and(Nat.is_eq(x, dx), Nat.is_eq(y, dy)), Nat.is_eq(z, dz)), done, 0.0),
    dt)

def step.timed(+block: U32, +x: Nat, +y: Nat, +z: Nat, +item: U32, +time: F32) -> Mined:
  Bool.pick(Mined, F32.is_ge(time, Inventory.mining_duration(item, block)),
    Mined{resting(), True{}},
    Mined{Dig{x, y, z, time, Inventory.mining_duration(item, block)}, False{}})

# A dig the rules refuse is the dig at rest, whatever was going: whether it is allowed is
# decided first and alone, so nothing about the time can make a refused block progress.
def step.allowed(allowed: Bool, +block: U32, +x: Nat, +y: Nat, +z: Nat, +item: U32, +time: F32) -> Mined:
  match allowed:
    case True{}:
      step.timed(block, x, y, z, item, time)
    case False{}:
      refused()

# One more tick of `dt` on the block `block` at (`x`, `y`, `z`), with `item` in hand. Air and
# a block the hand cannot break are refused.
def step(+block: U32, +x: Nat, +y: Nat, +z: Nat, dig: Dig, +item: U32, +dt: F32) -> Mined:
  step.allowed(Bool.and(U32.is_ne(block, 0), Inventory.can_mine(item, block)), block, x, y, z, item,
    so_far(dig, x, y, z, dt))

def mined_dig(mined: Mined) -> Dig:
  Mined{dig, breaks} = mined
  dig

def mined_breaks(mined: Mined) -> Bool:
  Mined{dig, breaks} = mined
  breaks
