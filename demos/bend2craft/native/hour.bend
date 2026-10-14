import Base
import ./sky.bend as Sky

# The hour a room's client keeps. The sun, the air and the light are rules on a clock
# (`native/sky.bend`); a client alone counts its own, and in a room the clock is the room's.

# A room's hour, as the client holds it. The room says how far round its day it is and how
# long its day lasts, when the client joins and when someone calls the morning. That is
# `Heard`, until the next tick reads the time and it becomes `Running`: the clock it was at
# `start`, when that was, and the clock now, which every tick works out again from how long
# ago that was. So the hour follows the room's own rate without being told again, and a late
# frame does not put it behind.
type Hour is Data:
  Unheard{}
  Heard{turn: U32, length: U32}
  Running{clock: U32, start: U32, length: U32, at: Nat}

# The hour at the time `now`, in milliseconds as `IO.now` counts them.
def hour.at(hour: Hour, +now: Nat) -> Hour:
  match hour:
    case Unheard{}:
      Unheard{}
    case Heard{+turn, length}:
      Running{Sky.clock_of_turn(turn), Sky.clock_of_turn(turn), length, now}
    case Running{clock, +start, +length, +at}:
      Running{Sky.clock_after(start, U32.from_nat(Nat.sub(now, at)), length), start, length, at}

# The clock the sun is read from: the room's once it has said, and the client's own until.
def hour.clock(hour: Hour, own: U32) -> U32:
  match hour:
    case Running{clock, start, length, at}:
      clock
    case Heard{turn, length}:
      own
    case Unheard{}:
      own

def hour.running(hour: Hour) -> Bool:
  match hour:
    case Running{clock, start, length, at}:
      True{}
    case Heard{turn, length}:
      False{}
    case Unheard{}:
      False{}
