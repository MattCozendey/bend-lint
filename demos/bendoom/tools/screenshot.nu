#!/usr/bin/env nu
# Screenshots the game's window through niri, which composites Xwayland
# windows the X root never shows: runs the binary, waits for the window,
# holds each key in turn, screenshots the window, quits the game and
# prints the PNG's path.
#
# Keys are xdotool key names (xdotool is in the dev shell) sent to the X
# window, each held for half a second:
#
#   tools/screenshot.nu Right Right Up
#   tools/screenshot.nu --binary ./bendoom --wait 4sec

def main [
  ...keys: string                            # keys to hold in turn
  --binary: path = result/bin/bendoom        # the game to run
  --wait: duration = 2sec                    # time for the window to open
]: nothing -> string {
  hide-env --ignore-errors LD_LIBRARY_PATH
  $env.DISPLAY = ($env.DISPLAY? | default ":1")
  job spawn { ^$binary }
  sleep $wait
  let window = ^niri msg --json windows | from json | where title == "Bendoom" | first
  if ($keys | is-not-empty) {
    let x = ^xdotool search --name Bendoom | lines | first
    for key in $keys {
      ^xdotool keydown --window $x $key
      sleep 500ms
      ^xdotool keyup --window $x $key
    }
    sleep 300ms
  }
  ^niri msg action screenshot-window --id $window.id --write-to-disk true
  sleep 500ms
  kill $window.pid
  ls ~/Pictures/Screenshots/*.png | sort-by modified | last | get name
}
