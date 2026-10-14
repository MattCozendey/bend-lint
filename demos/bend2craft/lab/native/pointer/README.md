# lab/native/pointer

Measures the look: what a display delivers for the mouse, and what the client's camera
does with it. `native/pointer.bend` and the fold in `native/frame.bend` are the modules
under test.

| file | what it answers |
| --- | --- |
| `census.bend`, `census-xvfb.sh` | every event the runtime hands a frame while the pointer is grabbed, under a real X server, for a known amount of relative mouse travel |
| `look_probe.bend`, `look-probe.sh` | the client's own tick with the yaw printed every frame, on the runtime's grab (`display`) or on the Windows host (`host`) |
| `walk_probe.bend`, `walk-probe.sh` | the client's own loop with a key held down: the player's window cell and the region's first chunk every tick |
| `host-probe.ps1` | the Windows half of the hosted run: a window in front with the client's title, and the real cursor moved by a known amount |

```bash
bash lab/native/pointer/census-xvfb.sh
bash lab/native/pointer/look-probe.sh display
```

```powershell
powershell -ExecutionPolicy Bypass -File lab\native\pointer\host-probe.ps1
```

The last one takes the real mouse for about five seconds and shows a small window.

## Measured

2026-10-01, WSL2 2.6.3, WSLg 1.0.71 (weston 9, FreeRDP 2.4.0), Bend 2.0.32.

**A grab on a real X server delivers deltas.** `census-xvfb.sh` moves the pointer by
eight relative steps of +10 px, 100 ms apart, then eight of -10 px. The census received
eight `Look{10 0}` and eight `Look{-10 0}`, each on its own frame, and nothing else. So
`Look` is this frame's movement, as `window.c:591` intends, and a fold has to sum it.

**The client's camera follows it.** `look-probe.sh display` runs the client's own
window, grab, tick and fold under Xvfb for the same travel. The yaw, in ten-thousandths
of a radian: `0 120 240 359 480 600 720 840 960 840 720 600 480 359 239 119 -0`. That is
80 px at `Frame.look_sensitivity` 0.0012, and back.

**The fold it replaced did not.** It differenced each `Look` against the previous
frame's, on the theory that WSLg reported positions. For that same travel it sees eight
equal deltas and turns on the first one only.

**The hosted pointer follows it too.** `host-probe.ps1` starts the same probe in WSL
from the repository root, so the client starts `native/pointer-host.ps1` through
interop, and moves the real Windows cursor by the same sixteen steps:

```
foreground=True
host_took_cursor=True after_ms=793
steps_pulled_back=16 of 16
pointer=host
yaw:0 120 240 359 480 600 720 840 960 840 720 600 480 359 239 119 -0
```

The host script was holding the cursor 793 ms after the probe was launched, pulled it
back to the centre after every one of the sixteen steps, and the camera turned by
exactly the travel and returned.

Four runs were taken. In the other three the sequence starts `0 36 156 ... 996` and
returns to `36`: the script was already holding the cursor when the probe placed it three
pixels off the centre, so those three pixels were a real displacement and were turned by
(3 x 0.0012 rad), which is the right answer. One of those three ended one step lower, at
`-84`: a seventeenth `-10 0` after the last step. It did not repeat in the two runs after
it and its cause is not established — the real mouse being touched during the run would
do it, and so would a race this probe has not caught. Treat a second sighting as a defect
in `native/pointer-host.ps1` and print its lines before changing anything.

**The region follows a walking player.** `walk-probe.sh s` starts the player fifteen cells
east of the spawn and holds `S` and `Space` for twenty seconds: the player went from window
cell 32793 to 32863 on z and the region's first chunk went 2048, 2049, 2050, 2051, 2052.
`walk-probe.sh w` walks north instead: the region moved to chunk 2047, which is before the
world's origin, and the player stopped at window cell 32768 against a three-block rise in
the terrain there, which `World.block` and the collision region agree on.

## Not measured

The hosted run's window is a Windows form with the client's title, because the probe's
own window is in Xvfb. Two things about a live WSLg window are therefore still
unmeasured: that its Windows title starts with `Bend2Craft native` (WSLg appends the
distro name, and the host script matches on the prefix), and that the grab's blank
cursor hides the Windows cursor while the host script holds it. When this was written
WSLg's compositor would not start on this machine (`WSLGd` exits with `Input/output
error @main.cpp:324`, the `chmod` of its shared-memory mount, on every start of the
distro), which needs `wsl --shutdown` and was not this session's to do.

## Why the display cannot do this under WSLg

WSLg carries each X window to Windows over RDP as a remote application window. FreeRDP
2.4.0 has no relative pointer input, so the compositor only ever learns an absolute
cursor position, and only while the Windows cursor is over the window. `XWarpPointer`
moves the X server's idea of the pointer and never the Windows cursor. An earlier
instrumented session saw exactly one `Look` for a whole run. `window.c` is byte-identical
upstream through 2.0.34, so this is not something a newer pin fixes either.
