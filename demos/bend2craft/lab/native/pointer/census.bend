import Base

# An event census: every event the runtime hands a frame, one line per frame.
#
# The window asks for the pointer grab every frame, exactly as the client does, and draws
# nothing. What it prints is the whole of what the runtime knows about the mouse, so a
# question about what a display delivers is answered by running this under that display
# and reading the lines, not by reading `effs/window.c` and inferring.

def signed(+value: F32) -> String:
  Bool.pick(String, F32.is_lt(value, 0.0), "-", "") ++ U32.show(F32.to_u32(F32.abs(value)))

def flag(down: Bool) -> String:
  Bool.pick(String, down, "down", "up")

def show_event(event: Event) -> String:
  match event:
    case Key{code, down}:
      " Key{" ++ U32.show(code) ++ " " ++ flag(down) ++ "}"
    case Mouse{x, y, button, down}:
      " Mouse{" ++ U32.show(x) ++ " " ++ U32.show(y) ++ " b" ++ U32.show(button) ++ " "
        ++ flag(down) ++ "}"
    case Move{x, y}:
      " Move{" ++ U32.show(x) ++ " " ++ U32.show(y) ++ "}"
    case Look{dx, dy}:
      " Look{" ++ signed(dx) ++ " " ++ signed(dy) ++ "}"
    case Scroll{x, y, dx, dy}:
      " Scroll{" ++ signed(dx) ++ " " ++ signed(dy) ++ "}"
    case Close{}:
      " Close{}"

def show_events(events: List<&1, Event>) -> String:
  match events:
    case Nil{}:
      ""
    case event <> rest:
      show_event(event) ++ show_events(rest)

def view(frame: U32) -> U32 & Image:
  (frame, Pix{2109504})

def tick.at(events: List<&1, Event>, +frame: U32) -> IO(Maybe<U32>):
  do IO<Maybe<U32>>:
    said : Unit <- IO.print("frame=" ++ U32.show(frame) ++ show_events(events))
    return Some{U32.add(frame, 1)}

def tick(events: List<&1, Event>, frame: U32) -> IO(Maybe<U32>):
  tick.at(events, frame)

def app() -> App<U32>:
  App{view, tick}

def frames(fuel: Nat, window: Window, +frame: U32) -> IO(Unit):
  match fuel:
    case 0n:
      Window.close(window)
    case 1n+f:
      do IO<Unit>:
        held : Window <- Window.grab(window, True{})
        App.step(U32, app(), held, frame, w => s => frames(f, w, s))

# Six seconds at the runtime's 60 Hz pacing.
def main() -> IO(Unit):
  do IO<Unit>:
    window : Window <- IO.try(Window, Window.open("Bend2Craft pointer census", 256, 256))
    frames(360n, window, 0)
