import Base
import ./hour.bend as Hour

def require(condition: Bool, message: String) -> IO(Unit):
  match condition:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "hour: " ++ message)

def check(condition: Bool, message: String) -> IO(Unit):
  require(condition, message)

# --- a room's hour -------------------------------------------------------------
#
# The room says its hour once, and the client runs it on from the time it heard: a quarter
# of the room's day after a quarter turn is sunset, whatever the client's own clock says.
def near_clock(+a: U32, +b: U32) -> Bool:
  Bool.and(U32.is_le(a, U32.add(b, 20)), U32.is_le(b, U32.add(a, 20)))

def verify_hour() -> IO(Unit):
  do IO<Unit>:
    +first : Hour.Hour = Hour.hour.at(Hour.Heard{1571, 78540}, 5000n)
    Unit <- check(U32.is_eq(Hour.hour.clock(Hour.Unheard{}, 4800), 4800),
      "a client alone does not read its own clock")
    Unit <- check(U32.is_eq(Hour.hour.clock(Hour.Heard{1571, 78540}, 4800), 4800),
      "an hour not yet timed is already the clock")
    Unit <- check(near_clock(Hour.hour.clock(first, 4800), 10800),
      "a room at a quarter turn is not at noon")
    Unit <- check(near_clock(Hour.hour.clock(Hour.hour.at(first, 24635n), 4800), 21600),
      "a quarter of the room's day after its noon is not sunset")
    check(near_clock(Hour.hour.clock(Hour.hour.at(Hour.hour.at(first, 9000n), 24635n), 4800), 21600),
      "the hour drifted with how often it was worked out")


def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- verify_hour()
    IO.print("hour: a room's hour runs on from the time it was heard")

#|hour: a room's hour runs on from the time it was heard
