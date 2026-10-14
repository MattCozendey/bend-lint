import Base
import ../../../world/player.bend as Player
import ../../../native/size.bend as Size
import ../../../native/client.bend as Client
import ../../../native/frame.bend as Frame
import ../../../native/player.bend as PlayerProbe
import ../../../native/play.bend as Play

# The client's own loop with the player's window cell and the region's first chunk printed
# after every tick, so a driver that holds a key can read whether the region followed.
#
# The player starts fifteen cells east of the spawn, outside the village house the spawn is
# in, so a held `W` walks north across open ground toward the world's origin and past it.
# Everything else is the client's: its window, tick, collision region and view.

def cell_text(+value: F32) -> String:
  U32.show(F32.to_u32(F32.floor(value)))

def line.at(player: Player.State, +home: Frame.Home) -> String:
  Player.State{x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall,
    poison} = player
  "cell=" ++ cell_text(x) ++ "," ++ cell_text(y) ++ "," ++ cell_text(z)
    ++ " home=" ++ Nat.show(Frame.home_x(home)) ++ "," ++ Nat.show(Frame.home_z(home))

def line(+state: Play.Client) -> String:
  line.at(Play.player_of(state), Play.home_of(state))

def said(next: Maybe<Play.Client>) -> IO(Maybe<Play.Client>):
  match next:
    case None{}:
      IO.pure(Maybe<Play.Client>, None{})
    case Some{+state}:
      do IO<Maybe<Play.Client>>:
        printed : Unit <- IO.print(line(state))
        return Some{state}

def tick(events: List<&1, Event>, state: Play.Client) -> IO(Maybe<Play.Client>):
  do IO<Maybe<Play.Client>>:
    next : Maybe<Play.Client> <- Play.tick.events(events, state)
    said(next)

def app() -> App<Play.Client>:
  App{Play.view, tick}

def frames(fuel: Nat, window: Window, +state: Play.Client) -> IO(Unit):
  match fuel:
    case 0n:
      Window.close(window)
    case 1n+f:
      do IO<Unit>:
        held : Window <- Client.grabbed(window)
        App.step(Play.Client, app(), held, state, w => s => frames(f, w, s))

def moved(state: Play.Client) -> Play.Client:
  Play.with_player(state, PlayerProbe.create_player(40n, 25n, 14n))

# Twenty seconds at the runtime's 60 Hz pacing.
def main() -> IO(Unit):
  do IO<Unit>:
    state : Play.Client <- Play.start(Size.size_128())
    window : Window <- Client.opened(128)
    frames(1200n, window, moved(state))
