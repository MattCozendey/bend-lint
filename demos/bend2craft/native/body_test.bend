import Base
import ./voxel.bend as Voxel
import ./face.bend as Face
import ./paint.bend as Paint
import ./sky.bend as Sky
import ./scenery.bend as Scenery
import ./body.bend as Body
import ./hud.bend as Hud

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "body: " ++ message)

# A player is read back out of a painted frame, 256 pixels a side, at noon. It stands at
# (8.5, 0, 16) facing -z, and the eye is level with its head, four cells to one side of it
# along z: behind it at z = 20, in front of it at z = 12.
def noon() -> U32:
  10800

def pixel(read: Array<U32> & U32) -> U32:
  (frame, cell) = read
  cell

def stood() -> List<&2, Body.Body>:
  [Body.Body{0, 8.5, 0.0, 16.0, 0.0}]

def half_turn() -> F32:
  3.1415927

def at(groups: List<&2, Paint.Group>, bodies: List<&2, Body.Body>, +eye_z: F32, +yaw: F32,
  +x: U32, +y: U32) -> U32:
  pixel(Scenery.pixels_among(groups, Voxel.Vec{8.5, 1.6, eye_z}, yaw, 0.0, 8n, Paint.QNil{}, 0.0,
    0.0, noon(), noon(), bodies)[U32.add(U32.mul(y, 256), x)])

# A side that faces along the body, at noon and near enough that there is no air between.
def lit(+color: U32) -> U32:
  Body.tone(color, Body.light_front(), Sky.level_at(noon()))

# The three pixels a body's head, torso and legs are under, from four cells off.
def head_y() -> U32:
  123

def torso_y() -> U32:
  150

def legs_y() -> U32:
  190

# From behind, a player is a head over a torso over legs, each in its own colour.
def a_player_is_drawn() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(at([], stood(), 20.0, 0.0, 128, head_y()), lit(Body.skin())),
      "the head is not where the player's head is")
    Unit <- check(U32.is_eq(at([], stood(), 20.0, 0.0, 128, torso_y()), lit(Body.shirt())),
      "the torso is not where the player's torso is")
    check(U32.is_eq(at([], stood(), 20.0, 0.0, 128, legs_y()), lit(Body.pants())),
      "the legs are not where the player's legs are")

# With nobody there, and with the player behind the eye, those pixels are the sky.
def nobody_is_not_drawn() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_ne(at([], [], 20.0, 0.0, 128, head_y()), lit(Body.skin())),
      "a frame with no player has a head in it")
    Unit <- check(U32.is_eq(at([], stood(), 20.0, half_turn(), 128, head_y()), at([], [], 20.0, half_turn(), 128, head_y())),
      "a player behind the eye is in the frame")
    check(U32.is_eq(at([], [Body.Body{0, 8.5, 0.0, F32.neg(80.0), 0.0}], 20.0, 0.0, 128, 127), at([], [], 20.0, 0.0, 128, 127)),
      "a player past the end of the air is in the frame")

# The eyes are on the side a player faces: seen from in front there is an eye where, from
# behind, there is the back of the head.
def the_eyes_say_which_way() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(at([], stood(), 12.0, half_turn(), 122, 121), lit(Body.eye())),
      "a player seen from in front has no eye")
    Unit <- check(U32.is_eq(at([], stood(), 12.0, half_turn(), 128, head_y()), lit(Body.skin())),
      "between the eyes is not the face")
    check(U32.is_eq(at([], stood(), 20.0, 0.0, 122, 121), lit(Body.skin())),
      "a player seen from behind has an eye")

# One block's side facing +z, as the one face of a group: stone at (8, 1, `z`).
def wall(+z: U32) -> List<&2, Paint.Group>:
  [Paint.Group{0, 0, False{}, [Face.Face{8, 1, z, 2n, 1}]}]

# A player is among the blocks, not over them: a block between the eye and the player hides
# what is behind it and nothing else, and a block behind the player is hidden by the player.
def a_block_in_front_hides_the_player() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_ne(at(wall(17), stood(), 20.0, 0.0, 128, head_y()), lit(Body.skin())),
      "the head shows through a block in front of it")
    Unit <- check(U32.is_eq(at(wall(17), stood(), 20.0, 0.0, 128, legs_y()), lit(Body.pants())),
      "a block in front of the head hid the legs")
    check(U32.is_eq(at(wall(12), stood(), 20.0, 0.0, 128, head_y()), lit(Body.skin())),
      "a block behind the player is painted over it")

# One body of a kind where the player stood, facing -z.
def a(+kind: U32) -> List<&2, Body.Body>:
  [Body.Body{kind, 8.5, 0.0, 16.0, 0.0}]

# A mob is its own shape in its own colours: a pig's flank where a player's legs would be
# blue, and nothing where a player's head would be. An item on the ground is a small cube in
# the colour the hotbar shows the item in.
def a_kind_is_its_shape() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(at([], a(1), 20.0, 0.0, 128, 180), lit(Body.pig_skin())),
      "a pig is not a pig's colour where its body is")
    Unit <- check(U32.is_eq(at([], a(1), 20.0, 0.0, 128, head_y()), at([], [], 20.0, 0.0, 128, head_y())),
      "a pig is as tall as a player")
    Unit <- check(U32.is_eq(at([], a(2), 20.0, 0.0, 128, head_y()), lit(Body.zombie_skin())),
      "a zombie's head is not a zombie's colour")
    Unit <- check(U32.is_eq(at([], a(9), 20.0, 0.0, 128, head_y()), lit(Body.zombie_skin())),
      "a kind nobody knows is not drawn as a zombie")
    check(U32.is_eq(at([], a(1001), 20.0, 0.0, 128, 200), lit(Hud.item_color(1))),
      "stone on the ground is not a cube of stone's colour")

# A villager turns to whoever looks at it: its eyes are there from either side, where a
# player seen from behind shows the back of its head.
def a_villager_faces_the_eye() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(at([], a(11), 20.0, 0.0, 123, 130), lit(Body.eye())),
      "a villager seen from one side has no eye")
    Unit <- check(U32.is_eq(at([], a(11), 12.0, half_turn(), 123, 130), lit(Body.eye())),
      "a villager seen from the other side has no eye")
    check(U32.is_eq(at([], a(12), 20.0, 0.0, 128, 180), lit(Body.robe_green())),
      "the second profession does not wear green")

# The nearer of two bodies hides the further, whichever the room named first.
def the_nearer_body_is_in_front() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(at([], [Body.Body{1, 8.5, 0.0, 16.0, 0.0}, Body.Body{4, 8.5, 0.0, 13.0, 0.0}],
        20.0, 0.0, 128, 180), lit(Body.pig_skin())),
      "a brute behind a pig is painted over it")
    check(U32.is_eq(at([], [Body.Body{4, 8.5, 0.0, 13.0, 0.0}, Body.Body{1, 8.5, 0.0, 16.0, 0.0}],
        20.0, 0.0, 128, 180), lit(Body.pig_skin())),
      "the order the bodies were named in changed which is in front")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- a_player_is_drawn()
    Unit <- nobody_is_not_drawn()
    Unit <- the_eyes_say_which_way()
    Unit <- a_block_in_front_hides_the_player()
    Unit <- a_kind_is_its_shape()
    Unit <- a_villager_faces_the_eye()
    Unit <- the_nearer_body_is_in_front()
    IO.print("body: the parts, an empty frame, the eyes, the order among blocks, the kinds, a villager and two bodies passed")
