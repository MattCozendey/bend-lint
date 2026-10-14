import Base
import ../../../native/size.bend as Size
import ../../../native/client.bend as Client
import ../../../native/player.bend as PlayerProbe
import ../../../native/play.bend as Play

# The live client's frame pacing while the player walks, frame by frame.
#
# `fps_probe.bend` counts the frames of a client that stands still at the spawn, which is
# inside a house facing a wall: the cheapest frame the client draws, with no region ever
# moving. This probe is the case a player is in. The player starts on open ground fifteen
# cells east of the spawn and walks south with the jump held, so the frame is terrain to the
# edge of the region and the region moves every sixteen cells. Each tick is timed with
# `IO.now`, and what is printed is the rate, how many frames ran past the 16.67 ms tick by
# more than a millisecond, and the longest one.
#
# The keys are put into the first tick's events here rather than sent by a driver, so
# nothing outside the client is running to be measured with it.

type Pace is Data:
  Pace{client: Play.Client, last: Nat, frames: U32, late: U32, worst: Nat, first: Nat}

def frames_to_run() -> Nat:
  900n

def view.at(drawn: Play.Client & Image, last: Nat, frames: U32, late: U32, worst: Nat,
  first: Nat) -> Pace & Image:
  (client, image) = drawn
  (Pace{client, last, frames, late, worst, first}, image)

def view(pace: Pace) -> Pace & Image:
  Pace{client, last, frames, late, worst, first} = pace
  view.at(Play.view(client), last, frames, late, worst, first)

# The walk: `S` and `Space` pressed in the first tick and never released.
def walking(started: Bool, events: List<&1, Event>) -> List<&1, Event>:
  match started:
    case True{}:
      events
    case False{}:
      Key{115, True{}} <> Key{32, True{}} <> events

def paced(next: Maybe<Play.Client>, +now: Nat, +last: Nat, +frames: U32, +late: U32,
  +worst: Nat, +first: Nat) -> IO(Maybe<Pace>):
  match next:
    case None{}:
      IO.pure(Maybe<Pace>, None{})
    case Some{client}:
      +took = Nat.sub(now, last)
      # The first frames carry the window's own start, so they are not counted as late.
      +counted = U32.is_gt(frames, 30)
      IO.pure(Maybe<Pace>, Some{Pace{client, now, U32.add(frames, 1),
        U32.add(late, Bool.pick(U32, Bool.and(counted, Nat.is_gt(took, 18n)), 1, 0)),
        Bool.pick(Nat, Bool.and(counted, Nat.is_gt(took, worst)), took, worst),
        Bool.pick(Nat, U32.is_eq(frames, 30), now, first)}})

def tick.timed(events: List<&1, Event>, client: Play.Client, +last: Nat, +frames: U32,
  +late: U32, +worst: Nat, +first: Nat) -> IO(Maybe<Pace>):
  do IO<Maybe<Pace>>:
    +now : Nat <- IO.now()
    next : Maybe<Play.Client> <- Play.tick.events(walking(U32.is_gt(frames, 0), events), client)
    paced(next, now, last, frames, late, worst, first)

def tick(events: List<&1, Event>, pace: Pace) -> IO(Maybe<Pace>):
  Pace{client, last, frames, late, worst, first} = pace
  tick.timed(events, client, last, frames, late, worst, first)

def app() -> App<Pace>:
  App{view, tick}

def summary(pace: Pace) -> String:
  Pace{client, +last, +frames, late, worst, +first} = pace
  +counted = U32.to_nat(U32.sub(frames, 31))
  +elapsed = Nat.sub(last, first)
  "pace_probe frames=" ++ Nat.show(counted) ++ " elapsed_ms=" ++ Nat.show(elapsed)
    ++ " fps_x100=" ++ Nat.show(Nat.div(Nat.mul(counted, 100000n), Nat.add(elapsed, 1n)))
    ++ " late=" ++ U32.show(late) ++ " worst_ms=" ++ Nat.show(worst)

def frames(fuel: Nat, window: Window, +pace: Pace) -> IO(Unit):
  match fuel:
    case 0n:
      do IO<Unit>:
        said : Unit <- IO.print(summary(pace))
        Window.close(window)
    case 1n+f:
      do IO<Unit>:
        held : Window <- Client.grabbed(window)
        App.step(Pace, app(), held, pace, w => s => frames(f, w, s))

def moved(state: Play.Client) -> Play.Client:
  Play.with_player(state, PlayerProbe.create_player(40n, 25n, 14n))

def run(+size: Size.Size, state: Play.Client) -> IO(Unit):
  do IO<Unit>:
    window : Window <- Client.opened(Size.width_of(size))
    +now : Nat <- IO.now()
    frames(frames_to_run(), window, Pace{moved(state), now, 0, 0, 0n, now})

def main() -> IO(Unit):
  do IO<Unit>:
    for_client : Size.Size <- Size.from_args()
    state : Play.Client <- Play.start(for_client)
    for_window : Size.Size <- Size.from_args()
    run(for_window, state)
