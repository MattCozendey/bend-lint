# P_UpdateSpecials' translation on Freedoom's numbers: the flat an
# animated flat shows after 0, 1, 8 and 9 tics and one cycle past the
# 9th. FWATER1 is the WAD's flat 141, the first of 4, numbered 3 here:
# before the first tic it shows itself; the first tic runs with the
# level's time 0 and sets 3 + (0 + 141) mod 4 = 4, which holds through
# the 8th; the 9th runs with time 8 and sets 3 + (1 + 141) mod 4 = 5; and
# after the 41st, 32 tics on, it is 5 again. NUKAGE3 is flat 124, the
# last of 3, numbered 2 with NUKAGE1 at 0: 0 + (0 + 124) mod 3 = 1 after
# tics 1 to 8, then 2 after the 9th and, 24 tics on, after the 33rd.
import Base
import ../src/gfx.bend as G

def words(xs: List<&2, U32>) -> String:
  List.show(~&2, ~U32, ~U32.show, xs)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("FWATER1 " ++ words([G.Gfx.anim.shown(0, 3, 4, 141, 0), G.Gfx.anim.shown(1, 3, 4, 141, 0),
      G.Gfx.anim.shown(8, 3, 4, 141, 0), G.Gfx.anim.shown(9, 3, 4, 141, 0), G.Gfx.anim.shown(41, 3, 4, 141, 0)]))
    IO.print("NUKAGE3 " ++ words([G.Gfx.anim.shown(0, 2, 3, 124, 2), G.Gfx.anim.shown(1, 2, 3, 124, 2),
      G.Gfx.anim.shown(8, 2, 3, 124, 2), G.Gfx.anim.shown(9, 2, 3, 124, 2), G.Gfx.anim.shown(33, 2, 3, 124, 2)]))

#|FWATER1 [3, 4, 4, 5, 5]
#|NUKAGE3 [2, 1, 1, 2, 2]
