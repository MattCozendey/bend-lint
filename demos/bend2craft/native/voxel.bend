import Base
import ../world/world.bend as World

type Vec is Data:
  Vec{x: F32, y: F32, z: F32}

type Camera is Data:
  Camera{eye: Vec, forward: Vec, right: Vec, up: Vec}

type VoxelGrid is Data:
  VoxelGrid{layers: List<&2, List<&2, List<&2, U32>>>}

type Walk is Data:
  Walk{x: U32, y: U32, z: U32, tx: F32, ty: F32, tz: F32, dx: F32,
    dy: F32, dz: F32, sx: Bool, sy: Bool, sz: Bool, face: U32, probes: U32}

type Trace is Data:
  Miss{probes: U32}
  Hit{block: U32, face: U32, probes: U32}

type Phase is Data:
  Scan{walk: Walk}
  XStep{walk: Walk}
  YStep{walk: Walk}
  Found{block: U32, face: U32, probes: U32}
  Stop{probes: U32}

def Vec.add(+a: Vec, +b: Vec) -> Vec:
  Vec{ax, ay, az} = a
  Vec{bx, by, bz} = b
  Vec{(ax + bx : F32), (ay + by : F32), (az + bz : F32)}

def Vec.scale(+v: Vec, +k: F32) -> Vec:
  Vec{x, y, z} = v
  Vec{(x * k : F32), (y * k : F32), (z * k : F32)}

def Vec.dot(+a: Vec, +b: Vec) -> F32:
  Vec{ax, ay, az} = a
  Vec{bx, by, bz} = b
  (ax * bx + ay * by + az * bz : F32)

def Vec.unit(+v: Vec) -> Vec:
  Vec.scale(v, (1.0 / F32.sqrt(Vec.dot(v, v)) : F32))

# The one camera basis: any eye, yaw and pitch. The basis itself depends on the
# angles only, so the eye is data on the camera rather than a ray argument.
#
# These three vectors are the game's camera, not a private one. `forward` is
# exactly `Player.direction` in `world/player.bend`, which is what the browser
# client feeds to gl-matrix `lookAt` (`web/game-state.js` `cameraDirection`), and
# `right` and `up` are the pair that client builds from it:
# `normalize(cross(direction, [0, 1, 0]))` and then `cross(right, direction)`.
# A renderer that differs here looks the other way from the one the player sees
# and disagrees with `Player.raycast`, which is the same direction, so the aim
# and the view would point apart. `Camera.orientation_test` pins it.
def Camera.look(+eye: Vec, +yaw: F32, +pitch: F32) -> Camera:
  +sy = F32.sin(yaw)
  +cy = F32.cos(yaw)
  +sp = F32.sin(pitch)
  +cp = F32.cos(pitch)
  Camera{eye, Vec{(sy * cp : F32), sp, (0.0 - cy * cp : F32)},
    Vec{cy, 0.0, sy}, Vec{(0.0 - sy * sp : F32), cp, (cy * sp : F32)}}

# The probe's pinned frame: a fixed eye, a fixed downward pitch, and a yaw the
# caller turns from "looking down the chunk". Yaw 0 in `Player.direction` looks
# toward -z, so the frame adds half a turn to look back into the chunk from its
# -z edge, and negates the pitch to look down. The 32x32 golden fingerprints hang
# on this exact pair.
def Camera.at(+yaw: F32) -> Camera:
  Camera.look(Vec{8.0, 14.0, 0.5}, F32.add(yaw, 3.1415927), F32.neg(0.30))

def Camera.eye(+camera: Camera) -> Vec:
  Camera{eye, _, _, _} = camera
  eye

# `half` is half the frame width and `focal` the 1.5 * `half` projection length,
# both constant across the recursion, so a 2^k frame keeps the pinned field of
# view at every resolution.
def Camera.ray_for(+camera: Camera, +x: U32, +y: U32, +half: F32, +focal: F32) -> Vec:
  Camera{_, forward, right, up} = camera
  +sx = ((U32.to_f32(x) + 0.5 - half) / focal : F32)
  +sy = ((half - U32.to_f32(y) - 0.5) / focal : F32)
  Vec.unit(Vec.add(forward, Vec.add(Vec.scale(right, sx), Vec.scale(up, sy))))

def Camera.ray(+camera: Camera, +x: U32, +y: U32) -> Vec:
  Camera.ray_for(camera, x, y, 16.0, 24.0)

# Half the width of a 2^depth frame, so depth 5 keeps the pinned 16.0/24.0 pair.
def projection_half(depth: Nat) -> F32:
  match depth:
    case 0n:
      0.5
    case 1n+p:
      F32.mul(2.0, projection_half(p))

def chunk_index(+x: U32, +z: U32, +y: U32) -> U32:
  +size = U32.from_nat(World.chunk_size())
  (x + z * size + y * size * size : U32)

def share_blocks(blocks: List<&1, U32>) -> List<&2, U32>:
  match blocks:
    case Nil{}:
      []
    case +block <> rest:
      block <> share_blocks(rest)

def shared_blocks(chunk: Array<U32>) -> List<&2, U32>:
  share_blocks(Array.to_list(~U32, chunk))

def grid_rows(remaining: Nat, +blocks: List<&2, U32>, +base: U32,
  +rows: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match remaining:
    case 0n:
      List.reverse(&2, List<&2, U32>, rows)
    case 1n+p:
      +row : List<&2, U32> = List.take(&2, U32,
        List.drop(&2, U32, blocks, U32.to_nat(base)), World.chunk_size())
      grid_rows(p, blocks, (base + U32.from_nat(World.chunk_size()) : U32), row <> rows)

def grid_layers(remaining: Nat, +blocks: List<&2, U32>, +y: U32,
  +layers: List<&2, List<&2, List<&2, U32>>>) -> List<&2, List<&2, List<&2, U32>>>:
  match remaining:
    case 0n:
      List.reverse(&2, List<&2, List<&2, U32>>, layers)
    case 1n+p:
      +size = U32.from_nat(World.chunk_size())
      +base = (y * size * size : U32)
      +layer : List<&2, List<&2, U32>> = grid_rows(World.chunk_size(), blocks, base, [])
      grid_layers(p, blocks, (y + 1 : U32), layer <> layers)

def grid_from_blocks(+blocks: List<&2, U32>) -> VoxelGrid:
  VoxelGrid{grid_layers(World.max_y(), blocks, 0, [])}

def grid_from_chunk(chunk: Array<U32>) -> VoxelGrid:
  grid_from_blocks(shared_blocks(chunk))

def grid_at(+grid: VoxelGrid, +x: U32, +y: U32, +z: U32) -> U32:
  VoxelGrid{layers} = grid
  +size = U32.from_nat(World.chunk_size())
  +height = U32.from_nat(World.max_y())
  +valid = Bool.and(Bool.and(U32.is_lt(x, size), U32.is_lt(y, height)), U32.is_lt(z, size))
  +layer = Maybe.default(&2, List<&2, List<&2, U32>>,
    List.get(&2, List<&2, List<&2, U32>>, layers, U32.to_nat(y)), [])
  +row = Maybe.default(&2, List<&2, U32>,
    List.get(&2, List<&2, U32>, layer, U32.to_nat(z)), [])
  Bool.pick(U32, valid, Maybe.default(&2, U32, List.get(&2, U32, row, U32.to_nat(x)), 0), 0)

def list_block_at(blocks: List<&2, U32>, +x: U32, +y: U32, +z: U32) -> U32:
  Maybe.default(&2, U32,
    List.get(&2, U32, blocks, U32.to_nat(chunk_index(x, z, y))), 0)

def axis_delta(+direction: F32) -> F32:
  (1.0 / Bool.pick(F32, F32.is_gt(F32.abs(direction), 0.00001),
    F32.abs(direction), 1.0) : F32)

def boundary_time(+origin: F32, +direction: F32) -> F32:
  +cell = F32.floor(origin)
  +forward = F32.is_gt(direction, 0.0)
  +backward = F32.is_lt(direction, 0.0)
  +positive_t = ((cell + 1.0 - origin)
    / Bool.pick(F32, forward, direction, 1.0) : F32)
  +negative_t = ((origin - cell)
    / Bool.pick(F32, backward, F32.abs(direction), 1.0) : F32)
  Bool.pick(F32, forward, positive_t,
    Bool.pick(F32, backward, negative_t, 1000000.0))

def trace_steps(fuel: Nat, +grid: VoxelGrid, +phase: Phase) -> Trace:
  match fuel:
    case 0n:
      Miss{0}
    case 1n+p:
      match phase:
        case Scan{walk}:
          Walk{+x, +y, +z, +tx, +ty, +tz, +dx, +dy, +dz, +sx, +sy, +sz, +face, +probes} = walk
          +block = grid_at(grid, x, y, z)
          +next_probes = (probes + 1 : U32)
          +scanned : Walk = Walk{x, y, z, tx, ty, tz, dx, dy, dz, sx, sy, sz, face, next_probes}
          trace_steps(p, grid,
            Bool.pick(Phase, U32.is_ne(block, 0), Found{block, face, next_probes}, XStep{scanned}))
        case XStep{walk}:
          Walk{+x, +y, +z, +tx, +ty, +tz, +dx, +dy, +dz, +sx, +sy, +sz, _, +probes} = walk
          +first_x = Bool.and(F32.is_le(tx, ty), F32.is_le(tx, tz))
          +next_x = Bool.pick(U32, sx, (x + 1 : U32), (x - 1 : U32))
          +next_walk : Walk = Walk{next_x, y, z, (tx + dx : F32), ty, tz, dx, dy, dz, sx, sy, sz,
            Bool.pick(U32, sx, 3, 0), probes}
          +valid_x = Bool.pick(Bool, sx, U32.is_lt(x, 15), U32.is_gt(x, 0))
          +next_x_phase : Phase = Bool.pick(Phase, valid_x, Scan{next_walk}, Stop{probes})
          trace_steps(p, grid, Bool.pick(Phase, first_x, next_x_phase, YStep{walk}))
        case YStep{walk}:
          Walk{+x, +y, +z, +tx, +ty, +tz, +dx, +dy, +dz, +sx, +sy, +sz, _, +probes} = walk
          +step_y = F32.is_le(ty, tz)
          +next_y = Bool.pick(U32, sy, (y + 1 : U32), (y - 1 : U32))
          +next_z = Bool.pick(U32, sz, (z + 1 : U32), (z - 1 : U32))
          +walk_y : Walk = Walk{x, next_y, z, tx, (ty + dy : F32), tz, dx, dy, dz, sx, sy, sz,
            Bool.pick(U32, sy, 4, 1), probes}
          +walk_z : Walk = Walk{x, y, next_z, tx, ty, (tz + dz : F32), dx, dy, dz, sx, sy, sz,
            Bool.pick(U32, sz, 5, 2), probes}
          +valid_y = Bool.pick(Bool, sy, U32.is_lt(y, 19), U32.is_gt(y, 0))
          +valid_z = Bool.pick(Bool, sz, U32.is_lt(z, 15), U32.is_gt(z, 0))
          +next_y_phase : Phase = Bool.pick(Phase, valid_y, Scan{walk_y}, Stop{probes})
          +next_z_phase : Phase = Bool.pick(Phase, valid_z, Scan{walk_z}, Stop{probes})
          trace_steps(p, grid, Bool.pick(Phase, step_y, next_y_phase, next_z_phase))
        case Found{block, face, probes}:
          Hit{block, face, probes}
        case Stop{probes}:
          Miss{probes}

def trace_start(valid: Bool, +grid: VoxelGrid, +origin: Vec, +direction: Vec) -> Trace:
  match valid:
    case False{}:
      Miss{0}
    case True{}:
      Vec{+ox, +oy, +oz} = origin
      Vec{+dx, +dy, +dz} = direction
      +x = F32.to_u32(F32.floor(ox))
      +y = F32.to_u32(F32.floor(oy))
      +z = F32.to_u32(F32.floor(oz))
      trace_steps(300n, grid, Scan{Walk{x, y, z, boundary_time(ox, dx), boundary_time(oy, dy),
        boundary_time(oz, dz), axis_delta(dx), axis_delta(dy), axis_delta(dz),
        F32.is_gt(dx, 0.0), F32.is_gt(dy, 0.0), F32.is_gt(dz, 0.0), 2, 0}})

def trace_inside(+grid: VoxelGrid, +origin: Vec, +direction: Vec) -> Trace:
  Vec{+ox, +oy, +oz} = origin
  Vec{+dx, +dy, +dz} = direction
  +magnitude = F32.sqrt((dx * dx + dy * dy + dz * dz : F32))
  +valid = Bool.and(Bool.and(F32.is_ge(ox, 0.0), F32.is_lt(ox, 16.0)),
    Bool.and(Bool.and(F32.is_ge(oy, 0.0), F32.is_lt(oy, 20.0)),
      Bool.and(F32.is_ge(oz, 0.0), F32.is_lt(oz, 16.0))))
  trace_start(Bool.and(valid, F32.is_gt(magnitude, 0.00001)), grid, origin, direction)

def trace_chunk(chunk: Array<U32>, +origin: Vec, +direction: Vec) -> Trace:
  trace_inside(grid_from_chunk(chunk), origin, direction)

def hit_block(+trace: Trace) -> U32:
  match trace:
    case Miss{_}:
      0
    case Hit{block, _, _}:
      block

def trace_probes(+trace: Trace) -> U32:
  match trace:
    case Miss{probes}:
      probes
    case Hit{_, _, probes}:
      probes

# Pack a colour from its channels. The table below is written this way rather than as
# packed literals so a value can be read against the browser palette it came from.
def rgb(+r: U32, +g: U32, +b: U32) -> U32:
  U32.or(U32.shln(r, 16n), U32.or(U32.shln(g, 8n), b))

# The colour the renderer falls back to for an id it has never heard of. It is
# deliberately a colour no real block uses, so "the palette ran out" is visible in a
# frame instead of quietly looking like a material.
def unknown_block_color() -> U32:
  rgb(170, 170, 170)

# One colour per block id, in the id order `world/world.bend` declares:
# 0 air, 1 stone, 2 dirt, 3 grass, 4 leaves, 5 wood, 6 sand, 7 water, 8 coal ore,
# 9 iron ore, 10 diamond ore, 11 furnace, 12 torch, 13 bed, 14 closed door,
# 15 open door, 16-19 wheat, 20 farmland, 21 lava, 22 cobblestone, 23 obsidian,
# 25 glass, 26 chest, 27 crafting table, 28 redstone dust, 29 redstone torch.
#
# Ids 0-10 keep the values they always had, so every pinned golden in the probe tests
# still holds; the rest are the base colour of the matching material in the browser's
# texture atlas, which is the renderer that has always displayed these correctly.
#
# Ids 21-29 were once in the *atlas's* order (grass top, wood top, lava, fire,
# cobblestone, obsidian, glass, chest, crafting table) instead of the world's, which is
# four ids out of step: a crafting table painted in glass's pale blue and a chest in
# obsidian's near-black. A block in another block's colour still renders and still
# raycasts to the right cell, so only a test that names the colours can see it.
#
# `world/structures.bend` builds a village out of ids 11 (furnace), 13 (bed) and
# 14 (door), so before 11-20 were here every one of those painted as the unknown-block
# grey and the village read as a flat slab.
def block_color(+block: U32) -> U32:
  match block:
    case 0:
      1842204
    case 1:
      7829367
    case 2:
      7951674
    case 3:
      5875274
    case 4:
      3705667
    case 5:
      8082480
    case 6:
      13812341
    case 7:
      3831748
    case 8:
      3289655
    case 9:
      11631194
    case 10:
      3594458
    case 11:
      rgb(122, 126, 128)
    case 12:
      rgb(74, 58, 44)
    case 13:
      rgb(179, 54, 63)
    case 14:
      rgb(143, 99, 61)
    case 15:
      rgb(143, 99, 61)
    case 16:
      rgb(122, 168, 62)
    case 17:
      rgb(140, 178, 70)
    case 18:
      rgb(195, 177, 74)
    case 19:
      rgb(218, 179, 79)
    case 20:
      rgb(74, 51, 34)
    case 21:
      rgb(224, 86, 26)
    case 22:
      rgb(122, 126, 127)
    case 23:
      rgb(29, 21, 48)
    case 24:
      rgb(239, 106, 30)
    case 25:
      rgb(191, 224, 234)
    case 26:
      rgb(154, 106, 60)
    case 27:
      rgb(148, 100, 58)
    case 41:
      rgb(74, 76, 82)
    case 28:
      rgb(170, 30, 30)
    case 29:
      rgb(214, 62, 44)
    case _:
      unknown_block_color()

def shade_color(+color: U32, +face: U32) -> U32:
  +axis = U32.mod(face, 3)
  +light = Bool.pick(U32, U32.is_eq(axis, 1), 100,
    Bool.pick(U32, U32.is_eq(axis, 0), 72, 84))
  +r = U32.div(U32.mul(U32.and((color >> 16n : U32), 255), light), 100)
  +g = U32.div(U32.mul(U32.and((color >> 8n : U32), 255), light), 100)
  +b = U32.div(U32.mul(U32.and(color, 255), light), 100)
  U32.or(U32.shln(r, 16n), U32.or(U32.shln(g, 8n), b))

def sky_color(+y: U32) -> U32:
  +amount = U32.div(U32.mul(y, 18), 31)
  +r = (126 + amount : U32)
  +g = (174 + amount : U32)
  +b = (224 + amount : U32)
  U32.or(U32.shln(r, 16n), U32.or(U32.shln(g, 8n), b))

# The same gradient over a frame of `size` rows. `sky_color` is this at 32, the size it was
# written for: its `y * 18 / 31` runs each channel past 255 from row 54 of a taller frame,
# and the overflow carries into the channel above, which is a sky of coloured bands.
def sky_color_at(+y: U32, +size: U32) -> U32:
  +amount = U32.div(U32.mul(y, 18), U32.sub(size, 1))
  +r = (126 + amount : U32)
  +g = (174 + amount : U32)
  +b = (224 + amount : U32)
  U32.or(U32.shln(r, 16n), U32.or(U32.shln(g, 8n), b))

def pixel_hit_color(hit: Trace, +y: U32) -> U32:
  match hit:
    case Miss{_}:
      sky_color(y)
    case Hit{block, face, _}:
      shade_color(block_color(block), face)

def pixel_color_for(+grid: VoxelGrid, +camera: Camera, +x: U32, +y: U32,
  +half: F32, +focal: F32) -> U32:
  pixel_hit_color(
    trace_inside(grid, Camera.eye(camera), Camera.ray_for(camera, x, y, half, focal)), y)

def pixel_color(+grid: VoxelGrid, +camera: Camera, +x: U32, +y: U32) -> U32:
  pixel_color_for(grid, camera, x, y, 16.0, 24.0)

def image(+depth: Nat, +grid: VoxelGrid, +camera: Camera, +half: F32, +focal: F32,
  +x: U32, +y: U32) -> Image:
  match depth:
    case 0n:
      Pix{pixel_color_for(grid, camera, x, y, half, focal)}
    case 1n+p:
      +step = U32.shln(1, p)
      tl tr bl br = image(p, grid, camera, half, focal, x, y)
        image(p, grid, camera, half, focal, (x + step : U32), y)
        image(p, grid, camera, half, focal, x, (y + step : U32))
        image(p, grid, camera, half, focal, (x + step : U32), (y + step : U32))
      Qua{tl, tr, bl, br}

# `depth` is the quadtree depth, so a 2^depth square frame; 5 is the pinned 32x32.
def render_size(+grid: VoxelGrid, +camera: Camera, +depth: Nat) -> Image:
  +half = projection_half(depth)
  image(depth, grid, camera, half, F32.mul(1.5, half), 0, 0)

def render_view(+grid: VoxelGrid, +camera: Camera) -> Image:
  render_size(grid, camera, 5n)

def render_grid(+grid: VoxelGrid, +yaw: F32) -> Image:
  render_view(grid, Camera.at(yaw))

def render_chunk(chunk: Array<U32>, +yaw: F32) -> Image:
  render_grid(grid_from_chunk(chunk), yaw)

# A full frame from a bulk chunk at any eye, yaw, pitch and 2^depth size.
def render_size_at(chunk: Array<U32>, +eye: Vec, +yaw: F32, +pitch: F32,
  depth: Nat) -> Image:
  render_size(grid_from_chunk(chunk), Camera.look(eye, yaw, pitch), depth)

def render_at(chunk: Array<U32>, +eye: Vec, +yaw: F32, +pitch: F32) -> Image:
  render_size_at(chunk, eye, yaw, pitch, 5n)

def fingerprint_step(+hash: U32, +color: U32) -> U32:
  U32.mul(U32.xor(hash, color), 16777619)

def fingerprint_go(image: Image, +hash: U32) -> U32:
  match image:
    case Pix{color}:
      fingerprint_step(hash, color)
    case Qua{tl, tr, bl, br}:
      +a = fingerprint_go(tl, hash)
      +b = fingerprint_go(tr, a)
      +c = fingerprint_go(bl, b)
      fingerprint_go(br, c)

def fingerprint(image: Image) -> U32:
  fingerprint_go(image, 2166136261)
