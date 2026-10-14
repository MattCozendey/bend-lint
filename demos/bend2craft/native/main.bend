import Base
import ./world.bend as Game

def Native.keydown.edit(code: U32, state: Game.State, edit: Bool) ->
  IO(Maybe<Game.State>):
  match edit:
    case True{}:
      IO.bind(Game.State, Maybe<Game.State>, Game.edit_state(state),
        state => IO.pure(Maybe<Game.State>, Some{state}))
    case False{}:
      IO.pure(Maybe<Game.State>, Some{Game.move_state(state, code)})

def Native.keydown.if(code: U32, state: Game.State, escape: Bool,
  edit: Bool) -> IO(Maybe<Game.State>):
  match escape:
    case True{}:
      IO.pure(Maybe<Game.State>, None{})
    case False{}:
      Native.keydown.edit(code, state, edit)

def Native.key(+code: U32, down: Bool, state: Game.State) ->
  IO(Maybe<Game.State>):
  match down:
    case False{}:
      IO.pure(Maybe<Game.State>, Some{state})
    case True{}:
      Native.keydown.if(code, state, U32.is_eq(code, 27), U32.is_eq(code, 101))

def Native.event(event: Event, state: Game.State) -> IO(Maybe<Game.State>):
  match event:
    case Close{}:
      IO.pure(Maybe<Game.State>, None{})
    case Key{code, down}:
      Native.key(code, down, state)
    case _:
      IO.pure(Maybe<Game.State>, Some{state})

def Native.events(events: List<Event>, state: Game.State) -> IO(Maybe<Game.State>):
  match events:
    case Nil{}:
      IO.pure(Maybe<Game.State>, Some{state})
    case event <> rest:
      IO.bind(Maybe<Game.State>, Maybe<Game.State>, Native.event(event, state),
        App.more(Game.State, state => Native.events(rest, state)))

def Native.tick(events: List<Event>, state: Game.State) -> IO(Maybe<Game.State>):
  Native.events(events, state)

def main() -> IO(Unit):
  do IO<Unit>:
    state : Game.State <- Game.start()
    App.run(~Game.State, ~App{Game.view, Native.tick}, "Bend2Craft native", 256, 256, state)
