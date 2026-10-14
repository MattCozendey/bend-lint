#!/bin/bash
# Builds the native Windows game, EldergroveFaire.exe, from park.c with
# MSYS2's UCRT64 gcc (https://www.msys2.org; pacman -S mingw-w64-ucrt-x86_64-gcc).
#
# usage: win/build.sh [--console] [out.exe]
#   park.c must be current: bend main.bend -o park.c (in WSL or on Linux).
#   --console builds a console program (for the developer modes' output);
#   the default is a GUI program that attaches to a console if started
#   from one.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="${UCRT:-/c/msys64/ucrt64/bin}:$PATH"
sub=-mwindows
if [ "${1:-}" = "--console" ]; then
  sub=-mconsole
  shift
fi
out=${1:-build/win/EldergroveFaire.exe}
obj=build/win
mkdir -p "$obj" "$(dirname "$out")"

# The one change to Bend's generated C (see win/compat/win_abi.h), placed
# after the line that ends its attribute macros.
anchor='#define FAR static __attribute__((noinline))'
if [ "$(grep -cxF "$anchor" park.c)" != 1 ]; then
  echo "win/build.sh: park.c has changed shape (no single '$anchor' line)" >&2
  exit 1
fi
awk -v a="$anchor" '{ print } $0 == a { print "#include \"win_abi.h\"" }' park.c > "$obj/park_win.c"

# -mincoming-stack-boundary=4: the Windows x64 ABI's 16-byte stack alignment,
# stated; without it GCC 15 crashes (in choose_baseaddr) on a Windows-
# convention function that calls a System V one defined in the same file.
cflags="-std=gnu11 -O3 -D_FILE_OFFSET_BITS=64 -mincoming-stack-boundary=4"
if [ ! -f "$obj/park.o" ] || ! cmp -s "$obj/park_win.c" "$obj/park_win.last"; then
  echo "compiling park.c (a few minutes)"
  gcc $cflags -w -Iwin/compat -include win/compat/bend_win.h -c "$obj/park_win.c" -o "$obj/park.o"
  cp "$obj/park_win.c" "$obj/park_win.last"
fi
gcc $cflags -Wall -c win/winplat.c -o "$obj/winplat.o"
windres win/eldergrove.rc -O coff -o "$obj/res.o"
gcc -static $sub -Wl,--stack,16777216 "$obj/park.o" "$obj/winplat.o" "$obj/res.o" \
  -lwinmm -lgdi32 -o "$out"
strip "$out"
echo "built $out ($(wc -c < "$out") bytes)"
