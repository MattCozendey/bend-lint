# Release the Bend compiler's memory before clang starts.
compile_bend() {
  local source=$1 binary=$2 target_os=$3
  local flags=(-std=c11 -O3) libraries=(-lpthread -lm)
  bend "$source" -o "$binary.c"
  test -s "$binary.c"
  if [ "$target_os" = darwin ]; then
    if grep -q '^#import ' "$binary.c"; then
      flags+=(-x objective-c -fobjc-arc -fmodules)
    fi
  else
    if grep -q '#include <X11/' "$binary.c"; then libraries+=(-lX11); fi
    if grep -q '#include <alsa/' "$binary.c"; then libraries+=(-lasound); fi
  fi
  "$CC" "${flags[@]}" "$binary.c" "${libraries[@]}" -o "$binary"
}
