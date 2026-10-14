# Third-party notices

Eldergrove Faire is MIT-licensed (see [LICENSE](LICENSE)), with these exceptions:

| File | Origin | License |
|---|---|---|
| `win_frame.c` | Adapted from Bend's Linux window effects (`bend2/effs/window_open.c`, `window_frame.c`, `window_close.c`), Copyright HigherOrderCO. Changed: a parallel blit of the frame's quadtree, a helper thread, window resizing and scaling modes, and a native Windows window behind the same interface. | Apache License 2.0 |
| `win_frame.js`, `win_open.js`, `win_close.js` | Adapted from Bend's `window_frame.js`, `window_open.js` and `window_close.js`, Copyright HigherOrderCO. | Apache License 2.0 |
| `snd.c` | Adapted from Bend's audio effect (`bend2/effs/audio.c`), Copyright HigherOrderCO. Changed: the sample ring is pumped to PulseAudio through `pacat`, or to waveOut on Windows. | Apache License 2.0 |

The Apache License 2.0 is at https://www.apache.org/licenses/LICENSE-2.0. Each of these files says
at its top where it came from and that it was modified.

The Windows build (`EldergroveFaire.exe`) is statically linked with runtime libraries from the
MinGW-w64 project, built by MSYS2: the mingw-w64 C runtime startup code and winpthreads (MIT
license, with parts under a BSD license from Lockless Inc.), and GCC's support library (GPL with
the GCC Runtime Library Exception, which places no conditions on the program). The Windows
download carries their license texts in `licenses/`.

The game's art, font, music and sound effects are original: drawn and synthesized by the code in this
repository. No assets from RollerCoaster Tycoon or any other game are used. RollerCoaster Tycoon is a
trademark of its owners; this project is not affiliated with or endorsed by them.
