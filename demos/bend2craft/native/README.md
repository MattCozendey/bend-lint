# The native client

Bend 2.0.32 running as a native program: a window, a world derived from the
same `world/*.bend` contracts the browser bundle uses, a player that walks and
digs, and a save file. This directory is the target that ships. Experiments and
the measurements taken of it live in `lab/native/`, and nothing here imports
from there.

## Layout

| file | owns |
| --- | --- |
| `size.bend` | the resolution selector: the sizes, their measured cost, the table and the `--size` flag |
| `client.bend` | the entry point: the window, the pointer grab and the frame loop |
| `play.bend` | the client alone: the player, the world it holds, one tick, one frame, the save |
| `action.bend` | the ray as the world's cell, dig and place, the dig timer, which blocks open a screen |
| `slabs.bend` | the world's faces kept a chunk at a time |
| `hour.bend` | a room's clock |
| `room.bend` | a multiplayer room from the client's side: the socket, mobs, pickups, harm, joining |
| `voxel.bend` | the camera, the region grid, and the per-pixel DDA raycaster the face renderer is checked against |
| `face.bend` | the visible-face renderer: one pass over the bulk cells, bucket, project; the ray walk the pointer's ray and the painter's gate use |
| `paint.bend` | what draws the window: the faces projected once and cut at the near plane, dealt down a fork tree to 64-pixel tiles, each painted nearest first in its own array, a pixel written once |
| `shade.bend` | the light each corner of a face takes: open sky, shade under leaves and roofs, and the dark crease where a wall meets the ground, worked out once per chunk |
| `sky.bend` | the sky's gradient over the view, the air that hides what is far, and the hour: the colours and the light of a twelve-minute day |
| `scenery.bend` | what is in the picture and is not a block: clouds that drift, the sun and the moon on their path, the stars; and the frame's entry point |
| `frame.bend` | one frame as data: player state, camera basis, the input fold, fingerprint, and the dirty check |
| `texture.bend` | the blocks' surfaces: one colour per texel of a 16x16 face, as a rule, under the corner light and the hour's |
| `bag.bend` | the inventory: the slots, the slot in hand, and the calls into `world/inventory.bend` that dig and place |
| `screen.bend` | the inventory, crafting table, chest and furnace screens: the original's layouts, the arrow, clicks and quick moves |
| `stores.bend` | what a click does to a chest or a furnace, through the rules a room applies, and the furnaces' tick |
| `stash.bend` | the bag and the world's chests and furnaces as text, saved beside the world |
| `hud.bend` | the hand and what it holds, the hotbar, the hearts and food, and the crosshair, painted over the frame |
| `pointer.bend` | the look under WSL: the Windows host's pointer as one `Look` per frame. `pointer.c` and the two `.js` files are its effect; `pointer-host.ps1` is the Windows half |
| `net.bend` | the lines the client says to a multiplayer room and hears back, and what the room has not heard yet |
| `tag.bend` | a player's name over its head: a three-by-five font in the overlay's dots |
| `body.bend` | a room's other players, mobs, villagers and dropped items: a few flat boxes each, handed to the painter among the faces |
| `player.bend` | the player region, collision, the chunk seam, and `Player.raycast` |
| `save.bend` | the `B2CW:1` snapshot codec and the legacy browser/multiplayer migration |
| `main.bend`, `world.bend` | the 16x16 feasibility slice: a cursor, one editable cell, a two-byte save |
| the `*_test.bend` files | the focused regressions, all in `scripts/test-suite.sh` |

## Building and running

`scripts/bootstrap-native-bend.sh` builds the pinned CLI into
`.tools/bend-local/` once, from the vendored `vendor/bend` submodule.

```bash
bash scripts/bootstrap-native-bend.sh                       # once
.tools/bend-local/bin/bend native/client.bend -o .tools/bend-local/bin/bend2craft-client
.tools/bend-local/bin/bend2craft-client                     # 128x128
.tools/bend-local/bin/bend2craft-client --size=1024         # 32, 64, 128, 256, 512 or 1024
bash scripts/play-native.sh --size=1024                     # compiles when stale, then runs
```

Run it from the repository root: the save and the host pointer script are both found
relative to the working directory.

On Windows both run **inside WSL** with WSLg. On Linux or macOS they need a
graphical display.

**What has been run.** Windows 11, WSL2 Ubuntu, WSLg, an AMD Ryzen 7 9800X3D, the CPU
on the runtime's default thread pool. Every number here is `--gpu off`.

**There is no GPU option.** Bend runs a call on the GPU only where the source marks it with
`!`, and this client marks none, so `--gpu on` is refused and the frame is painted on CPU
threads everywhere. A GPU painter would be a second way of painting a tile, written to
`vendor/bend/guide/SHADERS.md`, and it could not be tried on this machine: the runtime
refuses CUDA under WSL2. A macOS build has not been made; nothing here is known to stop one
from running on its CPU threads, and nothing says it does.

## Playing in a room

`--join=host:port` joins a multiplayer room through the server's native port
(`server/native-bridge.mjs`; `scripts/play-server.mjs` prints the address):

```bash
bash scripts/play-native.sh --size=512 --join=127.0.0.1:8081
```

Blocks and players are shared both ways with every other player, browser or native: the
client says where it is, and the others are drawn where the room says they are
(`body.bend`), behind whatever block is in front of them, each with its name over its head
(`tag.bend`), which shows through walls. The hour is the room's as well:
its day is 78.5 seconds, as in the browsers, where the client's own is twelve minutes.
The room's mobs, villagers and dropped items are drawn where the room says they are, in
steps of a fifth of a second. The dig key with a mob under the crosshair hits it, an item
on the ground beside the player goes into the bag, and a monster's blow takes hearts; a
player it kills starts again at the spawn. No chests are drawn, and the bag is the client's
own. A joined client plays in the room's world and saves to `native/client-room.b2cw`. If
the room cannot be reached, refuses, or has another seed, the client says so and plays
alone. `docs/MULTIPLAYER.md` has the lines.

## Choosing a resolution

The client prints its table before the window opens:

```
     32x32   1.1 ms   ~60 FPS   fits 60 Hz with 15.6 ms to spare
     64x64   1.3 ms   ~60 FPS   fits 60 Hz with 15.4 ms to spare
  * 128x128   2.0 ms   ~60 FPS   fits 60 Hz with 14.7 ms to spare
    256x256   2.3 ms   ~60 FPS   fits 60 Hz with 14.4 ms to spare
    512x512   3.2 ms   ~60 FPS   fits 60 Hz with 13.5 ms to spare
    1024x1024   6.1 ms   ~60 FPS   fits 60 Hz with 10.6 ms to spare
```

`--size=32|64|128|256|512|1024` chooses; the default is 128 and an unknown width falls
back to it. The cost column is the measured frame on the machine named in
`lab/native/2026-09-30-native-renderer-investigation.md`, and the FPS column is
`10000 / tenths` capped at 60, because the runtime's `window_pace` sleeps every
presented frame to a 16.666667 ms tick — so 60 is a ceiling, not a budget, and a
size cheaper than the tick still presents at 60 rather than at the quotient.

Bend 2.0.32 has no stdin, which is why the choice is a command-line flag rather
than a prompt: `IO` offers `print`, `args`, `get_env`, `sleep`, `now`,
`thread_count` and `random_u32`, and nothing that reads a key from a terminal.
`native/size_test.bend` divides the rate back out of each cost field rather than
reading it out of a table, so a re-measurement that drifts fails the test.

## Controls

`W`, `A`, `S`, `D` walk, `Space` jumps, the mouse or the arrow keys look, `1` to `9`
pick a hotbar slot, the left mouse button or `F`, held, digs the aimed block with what is
in hand — a bar under the crosshair fills as it goes — the right mouse button or `R` places what is in hand or opens the block it is on,
`E` opens the inventory, `Control` sprints, `Shift` sneaks, `T` writes the save, `Escape`
leaves. Placing, opening and saving act on the press and
not while a key is held; digging is the one that takes holding.

## The inventory

`E` opens the inventory screen, which is laid out as the original's: nine hotbar slots,
three rows of nine above them, four armour slots and the player's box, and a crafting grid
of two by two with the slot its result appears in. The mouse moves an arrow the client
draws itself, since the window holds the real pointer. The left button takes a whole
stack, puts one down, tops a stack up or swaps two; the right button takes half or puts
one item down. Items in the grid show what they would make, and a click on the result
takes it onto the arrow and spends one of each ingredient. `E` or `Escape` closes the
screen and puts what is on the arrow and in the grid back in the bag. While it is open
the player stands still. Shift with the left button sends a stack where the original sends
it, without carrying it.

The right button on a crafting table opens the same panel with a grid of three by three,
which is where tools are made; the bag starts with one table to place. On a chest it opens
the chest's nine slots, and on a furnace its three: something to smelt, coal to burn, and
what it made, with a flame while it burns and an arrow that fills. A chest that holds
something cannot be dug. `T` saves the bag and every chest and furnace beside the world.

In a room the chests and furnaces are the room's: their screens open the same, and a click
asks the room and is answered a moment later.

Not there yet: dragging a stack over slots, the number keys, throwing a stack away by
clicking outside, and armour.

The rules are `world/inventory.bend`'s, as in the browser: a dug block lands in the bag,
a placed one is spent from the slot in hand, and a bare hand cannot break stone — the
sixth slot starts with a diamond pickaxe for that, and the next two with a crafting table
and a chest.
The world is drawn five chunks by five around the player, eighty cells a side, and that
region follows the player as they walk, on either side of the world's origin.

## The picture

A face is lit at its corners: fully under the open sky, less under leaves, least under a
roof, and darker in every corner a wall or the ground closes. The air starts to show 22
cells from the eye and hides everything at 58, in the colour the sky has at the horizon,
so the edge of the region is behind it. The sky is pale at the horizon and deep overhead
wherever the camera looks, with clouds that drift, a sun that crosses it in a twelve-minute
day and sets orange, and a moon and stars at night, when the world's own colours fall to a
quarter of their light. Far water takes the colour of the sky.

`bash lab/native/paint/shot.sh` writes the frame from twenty-two cameras, hours and screens as PNG
files under `scratchpad/shots/`, which is how a change to the picture is looked at.

The mouse is taken when the window is in front and the cursor is inside it, and let go
when another window comes to the front (`Alt+Tab`). Under WSL the movement is read from
the Windows host by `pointer-host.ps1`, because WSLg cannot report relative motion; on
any other display it is the runtime's own grab. The client prints which one it chose.

The save goes to `native/client-world.b2cw` relative to the working directory,
in the `B2CW:1` format. It is **not** compatible with browser or multiplayer
saves; `native/save.bend` reads those instead, as a migration.

## Window size

`native/size.bend` is the selector: the sizes, what each costs, the table printed before
the window opens, and which `--size` flag wins. 128 is the default, and the benchmarks
measure it (`window_width()` and `frame_depth()` live in
`lab/native/client-probe/frame_bench.bend` now). Every size the selector offers fits the tick: `lab/native/paint/README.md` has the measured
per-size, per-thread table behind the selector, and
`lab/native/2026-09-30-native-renderer-investigation.md` has the investigation.
