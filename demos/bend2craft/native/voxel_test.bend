import Base
import ../world/player.bend as Player
import ../world/world.bend as World
import ./voxel.bend as Voxel

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, message)

def occlusion_test() -> IO(Unit):
  +origin : Voxel.Vec = Voxel.Vec{8.5, 8.5, 0.5}
  +forward : Voxel.Vec = Voxel.Vec{0.0, 0.0, 1.0}
  +near_index = Voxel.chunk_index(8, 2, 8)
  +far_index = Voxel.chunk_index(8, 5, 8)
  far_only = Array.set(U32, Array.new(U32, 13n, 0), near_index, 10)
  near_and_far = Array.set(U32,
    Array.set(U32, Array.new(U32, 13n, 0), near_index, 1), far_index, 10)
  +far_hit = Voxel.hit_block(Voxel.trace_chunk(far_only, origin, forward))
  +both_hit = Voxel.hit_block(Voxel.trace_chunk(near_and_far, origin, forward))
  do IO<Unit>:
    Unit <- check(U32.is_eq(far_hit, 10), "far opaque block fixture was not visible alone")
    check(U32.is_eq(both_hit, 1), "near opaque block did not occlude the farther block")

def boundary_test() -> IO(Unit):
  +first = Voxel.chunk_index(0, 0, 0)
  +last = Voxel.chunk_index(15, 15, 19)
  chunk = Array.set(U32, Array.set(U32, Array.new(U32, 13n, 0), first, 6), last, 10)
  +grid : Voxel.VoxelGrid = Voxel.grid_from_chunk(chunk)
  +first_block = Voxel.grid_at(grid, 0, 0, 0)
  +last_block = Voxel.grid_at(grid, 15, 19, 15)
  +outside_block = Voxel.grid_at(grid, 16, 19, 15)
  do IO<Unit>:
    Unit <- check(U32.is_eq(first_block, 6), "nested grid lost the first chunk cell")
    Unit <- check(U32.is_eq(last_block, 10), "nested grid lost the last world cell")
    check(U32.is_eq(outside_block, 0), "nested grid exposed a cell beyond the chunk boundary")

# Four blocks turn every camera assertion into an exact pixel color instead of a
# hash inequality. From the eye (8.5, 8.5, 0.5) at yaw 0 and pitch 0 the screen
# center reads the stone at (8, 8, 4); the same center reads the leaves at
# (12, 8, 0) when the camera turns to +x, reads the dirt at (8, 8, 10) when the
# eye moves to z 6.5, and pixel (16, 17) reads the grass at (8, 6, 3) when the
# camera pitches down. The colors are 0xRRGGBB after the probe's per-face tint:
# 84% on a z face, 72% on an x face, 100% on a y face.
def camera_chunk() -> Array<U32>:
  ahead = Array.set(U32, Array.new(U32, 13n, 0), Voxel.chunk_index(8, 6, 8), 1)
  turned = Array.set(U32, ahead, Voxel.chunk_index(12, 7, 8), 4)
  tilted = Array.set(U32, turned, Voxel.chunk_index(8, 6, 6), 3)
  Array.set(U32, tilted, Voxel.chunk_index(8, 10, 8), 2)

# The camera basis has to be the game's, because the game's aim is
# `Player.direction` and the browser client builds its view from exactly that
# vector. These are the yaw/pitch pairs the native renderer is used with,
# compared component by component: an equal basis is what lets the native client
# dig the cell the player is looking at instead of the one behind them.
def check_basis(forward: Voxel.Vec, direction: Player.Direction) -> IO(Unit):
  Voxel.Vec{fx, fy, fz} = forward
  Player.Direction{dx, dy, dz} = direction
  same = Bool.and(F32.is_eq(fx, dx), Bool.and(F32.is_eq(fy, dy), F32.is_eq(fz, dz)))
  check(same, "the camera basis is not Player.direction")

def forward_of(camera: Voxel.Camera, direction: Player.Direction) -> IO(Unit):
  Voxel.Camera{eye, forward, right, up} = camera
  check_basis(forward, direction)

def compare_basis(yaw: F32, pitch: F32, direction: Player.Direction) -> IO(Unit):
  camera = Voxel.Camera.look(Voxel.Vec{8.0, 14.0, 0.5}, yaw, pitch)
  forward_of(camera, direction)

def basis_at(+yaw: F32, +pitch: F32) -> IO(Unit):
  compare_basis(yaw, pitch, Player.direction(Player.state(0.0, 0.0, 0.0, yaw, pitch, 0.0,
    False{}, 20.0, 20.0)))

def basis_test() -> IO(Unit):
  do IO<Unit>:
    Unit <- basis_at(0.0, 0.0)
    Unit <- basis_at(0.7, 0.30)
    Unit <- basis_at(1.5707963, 0.0)
    Unit <- basis_at(0.0, 0.6)
    IO.print("voxel_probe=basis pass")

# An equal basis is not yet the player's view: a camera whose right axis were
# mirrored would still light the centre pixel. These count the block-coloured
# pixels per half of a 32x32 frame with one block in the world, so a mirrored or
# upside-down renderer cannot pass. The eye is at the middle of a chunk looking at
# yaw 0 pitch 0, which is toward -z with screen right = +x and screen up = +y.
type Halves is Data:
  Halves{left: U32, right: U32, top: U32, bottom: U32}

def shaded(face: U32) -> U32:
  Voxel.shade_color(Voxel.block_color(2), face)

def is_block(+color: U32) -> Bool:
  Bool.or(U32.is_eq(color, shaded(0)),
    Bool.or(U32.is_eq(color, shaded(1)), U32.is_eq(color, shaded(2))))

def count.go(image: Image, +size: Nat) -> U32:
  match image:
    case Pix{color}:
      Bool.pick(U32, is_block(color), U32.from_nat(size), 0)
    case Qua{tl, tr, bl, br}:
      +a = count.go(tl, size)
      +b = count.go(tr, size)
      +c = count.go(bl, size)
      +d = count.go(br, size)
      +ab = U32.add(a, b)
      +cd = U32.add(c, d)
      U32.add(ab, cd)

def halves(image: Image) -> Halves:
  match image:
    case Qua{tl, tr, bl, br}:
      +a = count.go(tl, 16n)
      +b = count.go(tr, 16n)
      +c = count.go(bl, 16n)
      +d = count.go(br, 16n)
      Halves{U32.add(a, c), U32.add(b, d), U32.add(a, b), U32.add(c, d)}
    case Pix{color}:
      Halves{color, 0, 0, 0}

def one_at(x: Nat, y: Nat, z: Nat) -> Array<U32>:
  Array.set(U32, Array.new(U32, 13n, 0), Voxel.chunk_index(U32.from_nat(x),
    U32.from_nat(z), U32.from_nat(y)), 2)

def half_of(x: Nat, y: Nat, z: Nat) -> Halves:
  halves(Voxel.render_at(one_at(x, y, z), Voxel.Vec{8.5, 14.0, 8.5}, 0.0, 0.0))

def check_sides(to_right: Halves, to_left: Halves, above: Halves, below: Halves,
  behind: Halves) -> IO(Unit):
  Halves{right_left, right_right, _, _} = to_right
  Halves{left_left, left_right, _, _} = to_left
  Halves{_, _, above_top, above_bottom} = above
  Halves{_, _, below_top, below_bottom} = below
  Halves{behind_left, behind_right, _, _} = behind
  do IO<Unit>:
    Unit <- check(Bool.and(U32.is_gt(right_right, 0), U32.is_eq(right_left, 0)),
      "a block at +x did not land only on the right half of the frame")
    Unit <- check(Bool.and(U32.is_gt(left_left, 0), U32.is_eq(left_right, 0)),
      "a block at -x did not land only on the left half of the frame")
    Unit <- check(Bool.and(U32.is_gt(above_top, 0), U32.is_eq(above_bottom, 0)),
      "a block above the eye did not land only in the top half of the frame")
    Unit <- check(Bool.and(U32.is_gt(below_bottom, 0), U32.is_eq(below_top, 0)),
      "a block below the eye did not land only in the bottom half of the frame")
    check(Bool.and(U32.is_eq(behind_left, 0), U32.is_eq(behind_right, 0)),
      "a block behind the eye was rendered in front of the camera")

def screen_orientation_test() -> IO(Unit):
  +to_right : Halves = half_of(10n, 14n, 4n)
  +to_left : Halves = half_of(6n, 14n, 4n)
  +above : Halves = half_of(8n, 16n, 4n)
  +below : Halves = half_of(8n, 12n, 4n)
  +behind : Halves = half_of(8n, 14n, 12n)
  check_sides(to_right, to_left, above, below, behind)

def eye_move_test() -> IO(Unit):
  +grid : Voxel.VoxelGrid = Voxel.grid_from_chunk(camera_chunk())
  +before : Voxel.Camera = Voxel.Camera.look(Voxel.Vec{8.5, 8.5, 7.5}, 0.0, 0.0)
  +after : Voxel.Camera = Voxel.Camera.look(Voxel.Vec{8.5, 8.5, 10.5}, 0.0, 0.0)
  +stone : U32 = Voxel.pixel_color(grid, before, 16, 16)
  +dirt : U32 = Voxel.pixel_color(grid, after, 16, 16)
  do IO<Unit>:
    Unit <- check(U32.is_ne(stone, dirt), "moving the eye left the center pixel color unchanged")
    Unit <- check(U32.is_eq(stone, 6513507), "center pixel did not show the stone -z face shade")
    check(U32.is_eq(dirt, 6637360), "translated eye did not show the dirt -z face shade")

def camera_turn_test() -> IO(Unit):
  +grid : Voxel.VoxelGrid = Voxel.grid_from_chunk(camera_chunk())
  +forward : Voxel.Camera = Voxel.Camera.look(Voxel.Vec{8.5, 8.5, 7.5}, 0.0, 0.0)
  +turned : Voxel.Camera = Voxel.Camera.look(Voxel.Vec{8.5, 8.5, 7.5}, 1.5707963, 0.0)
  +tilted : Voxel.Camera = Voxel.Camera.look(Voxel.Vec{8.5, 8.5, 7.5}, 0.0, F32.neg(1.2))
  +stone : U32 = Voxel.pixel_color(grid, forward, 16, 16)
  +leaves : U32 = Voxel.pixel_color(grid, turned, 16, 16)
  +stone_below : U32 = Voxel.pixel_color(grid, forward, 16, 17)
  +grass : U32 = Voxel.pixel_color(grid, tilted, 16, 16)
  do IO<Unit>:
    Unit <- check(U32.is_ne(stone, leaves), "turning the camera left the center pixel color unchanged")
    Unit <- check(U32.is_eq(leaves, 2647088), "turned camera did not show the leaves -x face shade")
    Unit <- check(U32.is_ne(stone_below, grass), "pitching the camera left the center pixel unchanged")
    check(U32.is_eq(grass, 5875274), "pitched camera did not show the grass +y face shade")

def outside_eye_test() -> IO(Unit):
  +grid : Voxel.VoxelGrid = Voxel.grid_from_chunk(camera_chunk())
  +outside : Voxel.Camera = Voxel.Camera.look(Voxel.Vec{40.0, 8.5, 7.5}, 0.0, 0.30)
  +inside : Voxel.Camera = Voxel.Camera.look(Voxel.Vec{8.5, 8.5, 7.5}, 0.0, 0.30)
  +top_left : U32 = Voxel.pixel_color(grid, outside, 0, 0)
  +bottom_right : U32 = Voxel.pixel_color(grid, outside, 31, 31)
  +outside_frame : U32 = Voxel.fingerprint(Voxel.render_at(camera_chunk(), Voxel.Vec{40.0, 8.5, 7.5}, 0.0, 0.30))
  +repeat_frame : U32 = Voxel.fingerprint(Voxel.render_at(camera_chunk(), Voxel.Vec{40.0, 8.5, 7.5}, 0.0, 0.30))
  +inside_frame : U32 = Voxel.fingerprint(Voxel.render_at(camera_chunk(), Voxel.Vec{8.5, 8.5, 7.5}, 0.0, 0.30))
  do IO<Unit>:
    Unit <- check(U32.is_eq(top_left, Voxel.sky_color(0)), "eye outside the chunk did not read the top sky row")
    Unit <- check(U32.is_eq(bottom_right, Voxel.sky_color(31)), "eye outside the chunk did not read the bottom sky row")
    Unit <- check(U32.is_eq(outside_frame, repeat_frame), "eye outside the chunk rendered an undefined frame")
    check(U32.is_ne(outside_frame, inside_frame), "an eye outside the chunk rendered the inside-chunk frame")

# The palette must cover every block id the world can produce. A block that falls
# through to `unknown_block_color` still renders, still raycasts to the right cell and
# still agrees with the other renderer, so no other check in this file can see it: the
# village built by world/structures.bend out of ids 11, 13 and 14 used to paint as one
# flat grey slab. This walks the id range and fails on the first id with no colour.
#
# One definition, not a helper chain, because the language allows no helper cycles: the
# countdown is a Nat so the match can both end the walk and hand the self-call a value
# that visibly shrank.
def palette_walk(remaining: Nat, +id: U32) -> IO(Unit):
  match remaining:
    case 0n:
      IO.print("voxel_probe=palette pass ids=0..29 all coloured")
    case 1n+r:
      do IO<Unit>:
        colour : U32 <- IO.pure(U32, Voxel.block_color(id))
        Unit <- check(U32.is_ne(colour, Voxel.unknown_block_color()),
          "block id has no colour and would render as the unknown-block grey")
        palette_walk(r, U32.add(id, 1))

# The three village materials have to be distinguishable from each other, not merely
# present, or a palette that mapped them all to one colour would still pass.
def distinct(a: U32, b: U32) -> Bool:
  U32.is_ne(a, b)

def village_palette_test() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(distinct(Voxel.block_color(11), Voxel.block_color(13)),
      "furnace and bed share a colour")
    Unit <- check(distinct(Voxel.block_color(13), Voxel.block_color(14)),
      "bed and door share a colour")
    IO.print("voxel_probe=village palette pass furnace, bed and door are distinct")

# The ids past 20 are the world's, not the texture atlas's. `world/world.bend` says 21 is
# lava, 22 cobblestone, 23 obsidian, 25 glass, 26 chest and 27 the crafting table; the
# palette once had them in the atlas's order, four ids out of step, and painted a crafting
# table as glass.
def world_palette_test() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(Voxel.block_color(21), Voxel.rgb(224, 86, 26)), "block 21 is not lava's colour")
    Unit <- check(U32.is_eq(Voxel.block_color(22), Voxel.rgb(122, 126, 127)), "block 22 is not cobblestone's colour")
    Unit <- check(U32.is_eq(Voxel.block_color(23), Voxel.rgb(29, 21, 48)), "block 23 is not obsidian's colour")
    Unit <- check(U32.is_eq(Voxel.block_color(25), Voxel.rgb(191, 224, 234)), "block 25 is not glass's colour")
    Unit <- check(U32.is_eq(Voxel.block_color(26), Voxel.rgb(154, 106, 60)), "block 26 is not a chest's colour")
    Unit <- check(U32.is_eq(Voxel.block_color(27), Voxel.rgb(148, 100, 58)), "block 27 is not a crafting table's colour")
    IO.print("voxel_probe=world palette pass ids 21-27 are the world's")

def main() -> IO(Unit):
  do IO<Unit>:
    +front : U32 = Voxel.fingerprint(Voxel.render_chunk(World.chunk(1337n, 0n, 0n), 0.0))
    +turned : U32 = Voxel.fingerprint(Voxel.render_chunk(World.chunk(1337n, 0n, 0n), 0.7))
    report : Unit <- IO.print("golden yaw=0 fingerprint=" ++ U32.show(front)
      ++ " yaw=0.7 fingerprint=" ++ U32.show(turned))
    front_check : Unit <- check(U32.is_eq(front, 2451398749), "yaw=0 render golden changed")
    turned_check : Unit <- check(U32.is_eq(turned, 3646106801), "yaw=0.7 render golden changed")
    direction_check : Unit <- check(U32.is_ne(front, turned),
      "camera direction change did not change the rendered image")
    boundaries_check : Unit <- boundary_test()
    occlusion_check : Unit <- occlusion_test()
    basis_checks : Unit <- basis_test()
    screen_checks : Unit <- screen_orientation_test()
    eye_check : Unit <- eye_move_test()
    turn_check : Unit <- camera_turn_test()
    outside_check : Unit <- outside_eye_test()
    palette_check : Unit <- palette_walk(30n, 0)
    village_check : Unit <- village_palette_test()
    world_check : Unit <- world_palette_test()
    IO.print("voxel_probe=pass image=32x32 occlusion=pass basis=pass screen=pass eye=pass turn=pass outside=pass palette=pass")

#|golden yaw=0 fingerprint=2451398749 yaw=0.7 fingerprint=3646106801
#|voxel_probe=basis pass
#|voxel_probe=pass image=32x32 occlusion=pass basis=pass screen=pass eye=pass turn=pass outside=pass palette=pass
