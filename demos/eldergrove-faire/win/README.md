# The Windows build

`EldergroveFaire.exe` is the same generated C as the Linux binary (`park.c`, from
`bend main.bend -o park.c`), compiled natively with MSYS2's UCRT64 GCC. Nothing runs through
WSL, and the exe needs only DLLs that ship with Windows 10 and 11.

```bash
bend main.bend -o park.c        # in WSL or on Linux: Bend only emits C for this target
win/build.sh                    # in Git Bash or an MSYS2 shell: build/win/EldergroveFaire.exe
win/build.sh --console build/win/eldergrove-console.exe   # a console build, for the developer modes
```

The build needs MSYS2 (https://www.msys2.org) with `pacman -S mingw-w64-ucrt-x86_64-gcc`. Set `UCRT`
if it isn't at `C:\msys64\ucrt64\bin`. Compiling `park.c` takes about a minute and a half.
`build.sh` keeps the object file and recompiles it only when `park.c` changes.

## How it works

Bend's runtime is written against POSIX. Rather than patching the generated file, the build
force-includes `compat/bend_win.h`. That header renames the calls Windows lacks, or does
differently, to `win_*` functions in `winplat.c`:

| POSIX in `park.c` | Windows in `winplat.c` |
|---|---|
| `mmap` with `MAP_NORESERVE` (an 8 GiB heap, 2 GiB work stacks) | `VirtualAlloc(MEM_RESERVE)`, plus a vectored exception handler that commits 1 MiB on first touch |
| the event loop's wake pipe, `fcntl(O_NONBLOCK)`, `select` | a CRT pipe polled with `PeekNamedPipe`, and an event the writer signals |
| `sigaltstack`/`sigaction(SIGSEGV)` | the fault handler calls the runtime's trap for a fault in a guard page |
| `nanosleep` (the 60 Hz frame pacing) | a high-resolution waitable timer |
| `open` | `_open` in binary mode |

`windows.h` never meets the generated code, because its macros (`TRUE`, `ERROR`, `small`, ...)
would clash with it. Everything that needs Win32 sits in `winplat.c` behind plain C declarations.
The empty headers in `compat/` (`sys/mman.h`, `poll.h`, ...) exist only so that `park.c`'s
includes resolve.

One change is made to the generated C itself. The work loop's segments enter one another with
`musttail` and pass a 16-byte struct. The Windows x64 convention passes such a struct by
reference, which a tail call can't do. `build.sh` therefore inserts `compat/win_abi.h`, which
gives the segments GCC's `sysv_abi` attribute. `-mincoming-stack-boundary=4` works around a GCC 15
crash on calls between the two conventions. If Bend's output changes shape, `build.sh` stops and
says so rather than guessing.

The window and the sound are the game's own effects: `Win.open`, `Win.frame`, `Win.config` and
`Win.close` in `../win_frame.c`, and `Snd.open` and `Snd.write` in `../snd.c`. On Windows they call
`winplat.c`:

- **Window.** It runs on its own thread, which pumps its messages. The frame thread fills a
  32-bit buffer and blits it with GDI (`SetDIBitsToDevice`). Keys and mouse events are translated
  to the same codes the X11 port produces. The process is DPI-aware, so pixels stay crisp.
- **Sound.** waveOut plays 16-bit stereo in eight blocks of 256 frames. The device is closed at
  exit, which a process with blocks still queued needs before it can end.

`eldergrove.ico` is drawn by `../tools/genicon.py`, and `eldergrove.rc` adds it and the version
details to the exe.

## Checked

The console build's `--scen`, `--uitest`, `--coastertest`, `--bridgetest` and `--savetest`
output, a `--shot` frame and a `--wav` recording are identical to the Linux build's. `--bench`
times match: about 10 ms for a full frame on the development machine. Played live, the game
holds 60 fps with the mouse, the keyboard, sound, and closing from the window's button and
Alt+F4.
