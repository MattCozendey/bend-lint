import Base
import ../../../native/size.bend as Size
import ../../../native/client.bend as Client
import ../../../native/play.bend as Play

# The live client's presented frame rate, measured by running the client's own loop for
# a fixed number of frames and timing it.
#
# Why this file exists. `lab/native/client-probe/frame_bench.bend` times the client's stages
# in a harness and `lab/native/client-probe/smoke.sh` proves the client works under a real
# display, but neither counts the frames the client actually presents, and that is the
# number the goal is about. It is not measurable from outside the process here: this WSL
# has no `strace`, `ltrace` or `perf`, so `XPutImage` cannot be counted, and reading
# `/proc`'s CPU time does not separate a frame's cost from the number of frames.
#
# `App.loop`'s third argument is a frame countdown — the prelude decrements it once per
# `App.step`, and `App.step` is one `Window.frame` — so handing it a known count and
# timing the call measures the presented rate exactly, using the same loop, the same
# window effect and the same pacing the shipping client runs. Nothing in
# `native/client.bend` is changed to do it.
#
# The window is the client's own size, at the client's own tile edge, with the client's
# own `view` and `tick`, so the frame it draws is the frame it ships.

# Frames to present. 600 is ten seconds at 60 Hz, long enough that the world build at
# startup and the first frames do not weigh on the mean, and short enough to run in a
# check.
def frames() -> Nat:
  600n

# A hundredths field is two digits, so a value under ten needs a leading zero. Bend has
# no conditional expression, so the test is a parameter and the choice is a `match`.
def pad.wide(wide: Bool, +hundredths: Nat) -> String:
  match wide:
    case True{}:
      ""
    case False{}:
      "0"

def pad(+hundredths: Nat) -> String:
  pad.wide(U32.is_ge(U32.from_nat(hundredths), 10), hundredths)

def report(+elapsed_ms: Nat) -> IO(Unit):
  +elapsed = Bool.pick(Nat, Nat.is_eq(elapsed_ms, 0n), 1n, elapsed_ms)
  # Frames per second to two decimals, as hundredths, so the print is integer-only.
  # `frames * 100000 / elapsed_ms` is the rate times one hundred: the elapsed is in
  # milliseconds, so a second is a thousand of them, and a hundredth of the rate is a
  # ten-thousandth of that.
  +rate_hundredths = Nat.div(Nat.mul(frames(), 100000n), elapsed)
  +whole = Nat.div(rate_hundredths, 100n)
  +hundredths = U32.to_nat(U32.mod(U32.from_nat(rate_hundredths), 100))
  +ms_per_frame = Nat.div(elapsed, frames())
  IO.print("fps_probe frames=" ++ Nat.show(frames())
    ++ " elapsed_ms=" ++ Nat.show(elapsed)
    ++ " ms_per_frame=" ++ Nat.show(ms_per_frame)
    ++ " fps=" ++ Nat.show(whole) ++ "." ++ pad(hundredths) ++ Nat.show(hundredths))

def run_at(+state: Play.Client, +width: U32) -> IO(Unit):
  do IO<Unit>:
    window : Window <- IO.try(Window, Window.open(Client.title(), width, width))
    grabbed : Window <- Client.grabbed(window)
    # The grab refuses to engage until the window holds input focus, and focus arrives
    # after the window is mapped, so grabbing and looping immediately loses that race —
    # the pointer then arrives as `Move` rather than `Look` and the player can only walk.
    # `Client.run` waits for the same reason; this probe did not, and the difference is
    # invisible until something asks the camera to turn.
    pause : Unit <- IO.sleep(Client.grab_wait_ms())
    held : Window <- Client.grabbed(grabbed)
    started : Nat <- IO.now()
    App.loop(Play.Client, Play.app(), frames(), held, state)
    finished : Nat <- IO.now()
    report(Nat.sub(finished, started))

def start_at(+chosen: Size.Size) -> IO(Unit):
  do IO<Unit>:
    state : Play.Client <- Play.start(chosen)
    run_at(state, Size.width_of(chosen))

def chosen() -> IO(Unit):
  do IO<Unit>:
    for_client : Size.Size <- Size.from_args()
    start_at(for_client)

def main() -> IO(Unit):
  chosen()





# The client's entry point takes the size the selector chose. This probe measures
# whichever size it is asked for, so a resolution that has just become affordable can be
# measured live instead of only in the harness: `--size=256` opens a 256x256 window and
# counts its frames, and with no argument it measures `window_width` — the size the
# benchmarks measure, and the one the client picks with no flag.
