# A place and a command script as text, for the tools: a place is
# "x y degrees" (map units, the angle in steps of 45 as a thing's is);
# a script is runs a space apart, each "count,forward,side,turn,buttons"
# in a demo file's units, but for the buttons: use 1, attack 2, a change
# of weapon 4 and eight times the weapon's number from 0 (tools/demo.nu
# says why).
import Base
import ../src/angle.bend as A
import ../src/level.bend as L
import ../src/keys.bend as K

# A whole number with its sign, in U32's wrapping arithmetic.
def Script.int(s: String) -> U32:
  match s:
    case SCon{Chr{45}, rest}:
      (0 - Maybe.default(&2, U32, U32.read(rest), 0) : U32)
    case other:
      Maybe.default(&2, U32, U32.read(other), 0)

def Script.place(words: List<&2, String>) -> L.Level.Start:
  match words:
    case x <> y <> degrees <> rest:
      L.Start{(Script.int(x) << 16n : U32), (Script.int(y) << 16n : U32), A.Angle.of_thing(Script.int(degrees))}
    case _:
      L.Start{0, 0, 0}

# The demo's buttons byte: the script's, its two low bits trading places.
def Script.buttons(+b: U32) -> U32:
  ((b .&. 252) + ((b .&. 1) << 1n) + ((b >> 1n) .&. 1) : U32)

def Script.run(fields: List<&2, String>) -> List<&2, K.Cmd>:
  match fields:
    case [n, forward, side, turn, buttons]:
      List.replicate(K.Cmd, U32.to_nat(Script.int(n)),
        K.Cmd.demo(Script.int(forward), Script.int(side), Script.int(turn), Script.buttons(Script.int(buttons))))
    case _:
      []

# Each run's commands.
def Script.runs(runs: List<&2, String>) -> List<&2, List<&2, K.Cmd>>:
  match runs:
    case []:
      []
    case run <> rest:
      Script.run(String.split(run, ',')) <> Script.runs(rest)
