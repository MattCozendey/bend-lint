import Base
import ../world/inventory.bend as Inventory
import ../world/digging.bend as Digging

# The dig timer, headless. The rule is `world/digging.bend`'s and the client only holds the
# dig between ticks, so this is the rule held to what a player sees: a block comes away when
# the button has been held on it for as long as `Inventory.mining_duration` says, looking at
# another cell starts over, and a block the hand cannot break gets nowhere.

def require(condition: Bool, message: String) -> IO(Unit):
  match condition:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "digging: " ++ message)

def check(condition: Bool, message: String) -> IO(Unit):
  require(condition, message)

def near(+a: F32, +b: F32) -> Bool:
  F32.is_lt(F32.abs(F32.sub(a, b)), 0.0001)

def done_of(dig: Digging.Dig) -> F32:
  Digging.Dig{x, y, z, done, need} = dig
  done

def need_of(dig: Digging.Dig) -> F32:
  Digging.Dig{x, y, z, done, need} = dig
  need

def at_cell(dig: Digging.Dig, wx: Nat, wy: Nat, wz: Nat) -> Bool:
  Digging.Dig{x, y, z, done, need} = dig
  Bool.and(Bool.and(Nat.is_eq(x, wx), Nat.is_eq(y, wy)), Nat.is_eq(z, wz))

def dig_of(mined: Digging.Mined) -> Digging.Dig:
  Digging.Mined{dig, breaks} = mined
  dig

def breaks_of(mined: Digging.Mined) -> Bool:
  Digging.Mined{dig, breaks} = mined
  breaks

# A hand on dirt, which it can break and takes some time over.
def dirt() -> U32:
  2

def stone() -> U32:
  1

def hand() -> U32:
  0

def quarter() -> F32:
  F32.div(Inventory.mining_duration(hand(), dirt()), 4.0)

def step_at(wz: Nat, dig: Digging.Dig) -> Digging.Mined:
  Digging.step(dirt(), 3n, 4n, wz, dig, hand(), quarter())

def second_tick(first: Digging.Mined) -> Digging.Mined:
  step_at(5n, dig_of(first))

# One tick on a block that can be broken starts the dig on that cell with the time that tick
# took, and the time it needs, and does not break it.
def verify_start() -> IO(Unit):
  +first : Digging.Mined = step_at(5n, Digging.resting())
  do IO<Unit>:
    Unit <- require(Bool.not(breaks_of(first)), "one tick of a dig broke the block")
    Unit <- require(at_cell(dig_of(first), 3n, 4n, 5n), "the dig is not on the cell that was struck")
    Unit <- require(near(done_of(dig_of(first)), quarter()), "the dig did not take one tick's time")
    check(near(need_of(dig_of(first)), Inventory.mining_duration(hand(), dirt())),
      "the dig does not carry how long the block takes")

# Holding on the same cell adds to the time; another cell starts over from one tick.
def verify_carry() -> IO(Unit):
  +first : Digging.Mined = step_at(5n, Digging.resting())
  +second : Digging.Mined = second_tick(first)
  do IO<Unit>:
    Unit <- require(near(done_of(dig_of(second)), F32.mul(quarter(), 2.0)),
      "a second tick on the same cell did not add to the first")
    Unit <- require(near(done_of(dig_of(step_at(6n, dig_of(second)))), quarter()),
      "looking at another cell did not start the dig over")
    check(at_cell(dig_of(step_at(6n, dig_of(second))), 3n, 4n, 6n),
      "the dig did not move to the other cell")

# The block comes away on the tick that makes the dig as long as the block takes, and the dig
# is then at rest.
def verify_break() -> IO(Unit):
  +second : Digging.Mined = second_tick(step_at(5n, Digging.resting()))
  +third : Digging.Mined = second_tick(second)
  +fourth : Digging.Mined = second_tick(third)
  do IO<Unit>:
    Unit <- require(Bool.not(breaks_of(third)), "the block came away a tick early")
    Unit <- require(breaks_of(fourth), "the block did not come away when the dig was as long as it takes")
    check(U32.is_eq(Digging.progress(dig_of(fourth)), 0), "a block that came away left a dig going")

# A bare hand cannot break stone, and nothing is there to dig in air: neither gets anywhere,
# however long the button is held, and the dig that was going is dropped.
def verify_refused() -> IO(Unit):
  +going : Digging.Dig = dig_of(step_at(5n, Digging.resting()))
  +stone_tick : Digging.Mined = Digging.step(stone(), 3n, 4n, 5n, going, hand(), quarter())
  +air_tick : Digging.Mined = Digging.step(0, 3n, 4n, 5n, going, hand(), quarter())
  do IO<Unit>:
    Unit <- require(Bool.not(breaks_of(stone_tick)), "a bare hand broke stone")
    Unit <- require(U32.is_eq(Digging.progress(dig_of(stone_tick)), 0), "a bare hand made progress on stone")
    Unit <- require(Bool.not(breaks_of(air_tick)), "air was broken")
    check(U32.is_eq(Digging.progress(dig_of(air_tick)), 0), "air was dug into")

# Progress is how far along over 256, and a dig that has not started has none.
def verify_progress() -> IO(Unit):
  +half : Digging.Mined = second_tick(step_at(5n, Digging.resting()))
  do IO<Unit>:
    Unit <- require(U32.is_eq(Digging.progress(Digging.resting()), 0), "a dig at rest has progress")
    Unit <- require(U32.is_eq(Digging.progress(dig_of(step_at(5n, Digging.resting()))), 64),
      "a quarter of the way is not 64 of 256")
    check(U32.is_eq(Digging.progress(dig_of(half)), 128), "half way is not 128 of 256")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- verify_start()
    Unit <- verify_carry()
    Unit <- verify_break()
    Unit <- verify_refused()
    Unit <- verify_progress()
    IO.print("digging: a dig starts, carries over on a cell, restarts on another, comes away on time and is refused")

#|digging: a dig starts, carries over on a cell, restarts on another, comes away on time and is refused
