import Base
import ./play.bend as Play
import ./pointer.bend as Pointer
import ./room.bend as Room
import ./size.bend as Size

# The native client's entry point: the window, the pointer grab and the frame loop. It owns no
# game rule and no state: the client is `native/play.bend`, a room is `native/room.bend`, the
# size is chosen by `native/size.bend` before the window opens, and what is here is the
# wiring between them and the runtime's `Window`.

def title() -> String:
  "Bend2Craft native"

# Which pointer the look is read from, said once before the first frame so a player who
# cannot turn knows which half to look at.
def pointer_note(hosted: Bool) -> String:
  Bool.pick(String, hosted,
    "  Pointer: read from the Windows host. It is taken while the window is in front"
      ++ " with the cursor inside it; Alt+Tab lets it go.\n",
    "  Pointer: the display's own grab. Click the window to take it.\n")

def report(chosen: U32, hosted: Bool) -> IO(Unit):
  IO.print(Size.table(chosen) ++ pointer_note(hosted))

# The window is opened and driven by hand rather than through `App.run`, because
# `App.run` has nowhere to put the pointer grab. The runtime only raises `Look` deltas
# while the pointer is grabbed, and the grab is also what hides the cursor.
def grabbed(window: Window) -> IO(Window):
  Window.grab(window, True{})

# The runtime's pointer grab refuses to engage until the window holds input focus,
# and focus arrives after the window is mapped, so a single grab at startup is a race
# the client can lose and then never turn again: without the grab the mouse arrives as
# `Move` rather than `Look`, and the player can only walk. The runtime ignores the call
# once the grab is held, so asking a second time after a pause is free and covers the
# case where focus arrived late. Two grabs rather than a retry loop, because a `Window`
# is a linear handle and a loop would need the same one twice in a pass.
def grab_wait_ms() -> U32:
  250

# The window is opened at the size the selector chose, and the table is printed
# first so the choice is made against its cost rather than guessed.
def opened(+width: U32) -> IO(Window):
  IO.try(Window, Window.open(title(), width, width))

# The frame loop, which asks for the grab **every frame** rather than once at startup.
#
# `window_grab` in the pinned runtime engages only `if (on && !win->grab && focus ==
# win->win)` — the X11 path in `vendor/bend/bend2/effs/window.c:771`. Focus is not
# something the client can arrange: the window can be mapped without it, and the player
# has to click the window to give it focus, which is after the loop has started. So a
# startup-only grab can be lost for the whole session. The runtime also clears
# `win->grab` on `FocusOut` (`window.c:584`), so alt-tabbing away and back would leave the
# mouse dead for the rest of the session too. Asking again every frame costs one
# already-held grab check per frame, which the runtime short-circuits on `!win->grab`.
#
# `App.step` rather than `App.loop` for exactly this: `App.loop` builds its own
# continuation and never hands the window anywhere a grab can be taken, while `App.step`
# takes the continuation as an argument. Quitting is unchanged — the continuation is only
# reached when the tick hands back a client, and `App.next` closes the window when it
# hands back nothing.
#
# The grab is taken whether or not the pointer is hosted. Hosted, the movement comes from
# `native/pointer.bend` and the grab is only what hides the cursor over the window; the
# `Look` events it raises are dropped by `Pointer.events`.
def frames(fuel: Nat, window: Window, state: Room.Session) -> IO(Unit):
  match fuel:
    case 0n:
      Window.close(window)
    case 1n+f:
      do IO<Unit>:
        held : Window <- grabbed(window)
        App.step(Room.Session, Room.session_app(), held, state, w => s => frames(f, w, s))

def session.hosting(session: Room.Session, hosted: Bool) -> Room.Session:
  Room.Session{client, link} = session
  Room.Session{Play.hosting(client, hosted), link}

# The host's pointer is asked for before the window opens, so the table can say which
# pointer the look is read from and is still printed before the window. The host script
# finds the window by its title and waits for it to appear.
def run.hosted(+width: U32, state: Room.Session, +hosted: Bool) -> IO(Unit):
  do IO<Unit>:
    shown : Unit <- report(width, hosted)
    window : Window <- opened(width)
    early : Window <- grabbed(window)
    pause : Unit <- IO.sleep(grab_wait_ms())
    frames(4294967295n, early, session.hosting(state, hosted))

def run(+width: U32, state: Room.Session) -> IO(Unit):
  do IO<Unit>:
    opened : U32 <- Pointer.host_open(title())
    run.hosted(width, state, U32.is_eq(opened, 1))

# A bound value is spent once, and the width is wanted twice: once for the client
# and once for the window. `Size.from_args` is a pure function of the arguments, so it
# is asked twice rather than shared, and the two answers cannot disagree.
def main() -> IO(Unit):
  do IO<Unit>:
    for_client : Size.Size <- Size.from_args()
    state : Room.Session <- Room.session.start(for_client)
    for_window : Size.Size <- Size.from_args()
    run(Size.width_of(for_window), state)
