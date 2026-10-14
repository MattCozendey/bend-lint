# The status bar's icons on chosen inventories, 4294967295 for none.
# ST_updateWidgets' keyboxes over the three colours, the icons numbered
# as ST_loadGraphics loads STKEYS0 to STKEYS5 from slot 21: a colour
# with neither key shows nothing, the blue card shows the first icon,
# the blue skull over it shows the fourth, and the red skull alone shows
# the sixth in the bottom slot.
# ST_createWidgets' w_arms reads weaponowned[i + 1], so the arms panel
# counts the pistol first and the BFG last and never the fist or the
# chainsaw: the starting pair shows the pistol's yellow number, slot 12,
# and a grey number for every other, and owning the chainsaw leaves slot
# 6 grey while owning the BFG turns it yellow.
import Base
import ../src/bar.bend as Y

def words(xs: List<&2, U32>) -> String:
  List.show(~&2, ~U32, ~U32.show, xs)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("keyboxes " ++ words([Y.Bar.keybox(0, 0), Y.Bar.keybox(0, 2), Y.Bar.keybox(1, 0), Y.Bar.keybox(1, 1),
      Y.Bar.keybox(9, 0), Y.Bar.keybox(32, 2), Y.Bar.keybox(32, 0)]))
    IO.print("arms " ++ words([Y.Bar.arm(3, 0), Y.Bar.arm(3, 1), Y.Bar.arm(7, 1), Y.Bar.arm(3, 5), Y.Bar.arm(131, 5),
      Y.Bar.arm(64, 5)]))

#|keyboxes [4294967295, 4294967295, 21, 4294967295, 24, 26, 4294967295]
#|arms [12, 28, 13, 32, 32, 17]
