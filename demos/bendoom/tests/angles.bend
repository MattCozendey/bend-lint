# Binary angles and vanilla's tables on chosen values. The fine angle of
# a binary angle is its top thirteen bits: a quarter turn is 2048. The
# sine table at zero, a quarter turn and a half turn is 25, 65535 and
# -25, the cosine at zero 65535, and the tangent at the table's middle
# 25. R_PointToAngle puts due east at 0 and due north at ANG90 - 1 -
# tantoangle[0], a quarter turn less one.
# Last the rotation a thing shows, by R_ProjectSprite's rule from the
# angle of the thing from the eye and the thing's facing, 0 for its
# front. Facing east, it shows its front to an eye east of it (the angle
# 180), its back, 4, to one west (0), 2 to one north (270) and 6 to one
# south (90); facing north, its front to one north. A rotation spans the
# eighth of a turn centred on its angle, so the front runs from 157.5
# degrees (0x70000000) and one less is 7.
import Base
import ../src/vec.bend as V
import ../src/angle.bend as A
import ../src/tables.bend as T
import ../src/sprites.bend as Z

def words(xs: List<&2, U32>) -> String:
  List.show(~&2, ~U32, ~U32.show, xs)

def main() -> IO(Unit):
  +sines = V.Vec.of_list(T.Tables.finesine(), 10240)
  +tanto = V.Vec.of_list(T.Tables.tantoangle(), 2049)
  do IO<Unit>:
    IO.print("fine " ++ U32.show(A.Angle.fine(1073741824)))
    IO.print("sine " ++ words([A.Angle.sin(sines, 0), A.Angle.sin(sines, 2048), A.Angle.sin(sines, 4096)]))
    IO.print("cosine " ++ U32.show(A.Angle.cos(sines, 0)))
    IO.print("tangent " ++ Maybe.show(~&2, ~U32, ~U32.show, List.get(&2, U32, T.Tables.finetangent(), 2048n)))
    IO.print("of " ++ words([A.Angle.of(tanto, 65536, 0), A.Angle.of(tanto, 0, 65536)]))
    IO.print("rotation " ++ words([Z.Sprites.rotation(A.Angle.ang180(), 0), Z.Sprites.rotation(0, 0),
      Z.Sprites.rotation(A.Angle.ang270(), 0), Z.Sprites.rotation(A.Angle.ang90(), 0),
      Z.Sprites.rotation(A.Angle.ang270(), A.Angle.ang90()), Z.Sprites.rotation(1879048192, 0),
      Z.Sprites.rotation(1879048191, 0)]))

#|fine 2048
#|sine [25, 65535, 4294967271]
#|cosine 65535
#|tangent Some(25)
#|of [0, 1073741823]
#|rotation [0, 4, 2, 6, 0, 0, 7]
