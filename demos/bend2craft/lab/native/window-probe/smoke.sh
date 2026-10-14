#!/usr/bin/env bash
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
compiler="${BEND_BIN:-$repo_root/.tools/bend-local/bin/bend}"
scratch_root="$repo_root/scratchpad/window-probe"
frame_reader="$script_dir/frame-pixel.py"

for tool in Xvfb xdotool python3 timeout od; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'Missing required WSL tool: %s\n' "$tool" >&2
    exit 1
  fi
done

if [ ! -x "$compiler" ]; then
  printf 'Pinned standalone Bend compiler is missing: %s\n' "$compiler" >&2
  exit 1
fi
if [ "$("$compiler" version)" != 'bend 2.0.35' ]; then
  printf 'Native smoke requires Bend 2.0.35: %s\n' "$compiler" >&2
  exit 1
fi

run_dir=
xvfb_pid=
app_pid=

stop_pid() {
  pid=$1
  [ -n "$pid" ] || return 0
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
    deadline=$((SECONDS + 2))
    while kill -0 "$pid" 2>/dev/null && [ "$SECONDS" -lt "$deadline" ]; do
      sleep 0.05
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
  fi
  wait "$pid" 2>/dev/null || true
}

cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  stop_pid "${app_pid:-}"
  stop_pid "${xvfb_pid:-}"
  if [ "$status" -eq 0 ] && [ -n "$run_dir" ]; then
    rm -rf -- "$run_dir"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

printf 'PREFLIGHT DISPLAY=%s\n' "${DISPLAY-<unset>}"
printf 'PREFLIGHT existing X/native processes:\n'
ps -eo pid=,args= 2>/dev/null | grep -E '[X]vfb|[X]org|[b]end2craft-native-probe' || true
printf 'PREFLIGHT existing X11 sockets:\n'
if [ -d /tmp/.X11-unix ]; then
  find /tmp/.X11-unix -maxdepth 1 -type s -print
fi
printf 'PREFLIGHT existing X11 lock files:\n'
for lock_file in /tmp/.X*-lock; do
  if [ -e "$lock_file" ]; then
    printf '%s\n' "$lock_file"
  fi
done
printf 'PREFLIGHT TCP display listeners (Xvfb will use -nolisten tcp):\n'
if command -v ss >/dev/null 2>&1; then
  ss -ltn 2>/dev/null | grep -E ':60[0-9][0-9][[:space:]]' || true
fi

mkdir -p "$scratch_root"
run_dir=$(mktemp -d "$scratch_root/run.XXXXXX")
mkdir "$run_dir/native" "$run_dir/framebuffer"
binary="$run_dir/bend2craft-native-probe"
timeout 60s "$compiler" "$repo_root/native/main.bend" -o "$binary"
save_file="$run_dir/native/native-edit.bin"
display_file="$run_dir/display"
xvfb_log="$run_dir/xvfb.log"
app_log="$run_dir/app.log"
frame_file="$run_dir/framebuffer/Xvfb_screen0"
if [ -e "$save_file" ]; then
  printf 'Isolated save unexpectedly exists before startup: %s\n' "$save_file" >&2
  exit 1
fi

# Use Xtrans's abstract local socket; do not change the system-owned /tmp socket directory.
Xvfb -displayfd 3 -screen 0 256x256x24 -nolisten tcp -nolisten unix -listen local \
  -fbdir "$run_dir/framebuffer" 3>"$display_file" >"$xvfb_log" 2>&1 &
xvfb_pid=$!

display_number=
deadline=$((SECONDS + 10))
while [ "$SECONDS" -lt "$deadline" ]; do
  if [ -s "$display_file" ]; then
    IFS= read -r display_number < "$display_file" || true
    case "$display_number" in
      ''|*[!0-9]*) display_number= ;;
      *) break ;;
    esac
  fi
  if ! kill -0 "$xvfb_pid" 2>/dev/null; then
    printf 'Xvfb exited during startup; see %s\n' "$xvfb_log" >&2
    exit 1
  fi
  sleep 0.05
done
if [ -z "$display_number" ]; then
  printf 'Timed out waiting for Xvfb display assignment; see %s\n' "$xvfb_log" >&2
  exit 1
fi
export DISPLAY=":$display_number"

geometry=$(timeout 2s xdotool getdisplaygeometry)
if [ "$geometry" != '256 256' ]; then
  printf 'Unexpected Xvfb display geometry: %s\n' "$geometry" >&2
  exit 1
fi
printf 'XVFB_DISPLAY=:%s geometry=%s\n' "$display_number" "$geometry"

(
  cd "$run_dir"
  exec "$binary"
) >"$app_log" 2>&1 &
app_pid=$!

window_id=
deadline=$((SECONDS + 15))
while [ "$SECONDS" -lt "$deadline" ]; do
  if ! kill -0 "$app_pid" 2>/dev/null; then
    printf 'Native app exited before opening a window; see %s\n' "$app_log" >&2
    exit 1
  fi
  if window_ids=$(timeout 2s xdotool search --onlyvisible --name '^Bend2Craft native$' 2>/dev/null); then
    window_id=${window_ids%%$'\n'*}
    if [ -n "$window_id" ]; then
      break
    fi
  fi
  sleep 0.05
done
if [ -z "$window_id" ]; then
  printf 'Timed out waiting for visible Bend2Craft native window; see %s\n' "$app_log" >&2
  exit 1
fi
printf 'WINDOW_OPEN=verified window_id=%s\n' "$window_id"

timeout 2s xdotool windowfocus --sync "$window_id"
focused_window=$(timeout 2s xdotool getwindowfocus)
if [ "$focused_window" != "$window_id" ]; then
  printf 'Window focus mismatch: expected %s, got %s\n' "$window_id" "$focused_window" >&2
  exit 1
fi

window_geometry=$(timeout 2s xdotool getwindowgeometry --shell "$window_id")
window_x=$(printf '%s\n' "$window_geometry" | sed -n 's/^X=//p')
window_y=$(printf '%s\n' "$window_geometry" | sed -n 's/^Y=//p')
window_width=$(printf '%s\n' "$window_geometry" | sed -n 's/^WIDTH=//p')
window_height=$(printf '%s\n' "$window_geometry" | sed -n 's/^HEIGHT=//p')
for dimension in "$window_x" "$window_y" "$window_width" "$window_height"; do
  case "$dimension" in
    ''|*[!0-9]*) printf 'Could not read native window geometry:\n%s\n' "$window_geometry" >&2; exit 1 ;;
  esac
done
if [ "$window_width" -ne 256 ] || [ "$window_height" -ne 256 ]; then
  printf 'Unexpected native window size: %sx%s\n' "$window_width" "$window_height" >&2
  exit 1
fi

wait_for_frame_pixel() {
  cell_x=$1
  cell_z=$2
  label=$3
  expected_rgb=$4
  deadline=$((SECONDS + 5))
  last_result='framebuffer file not present yet'
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ -f "$frame_file" ]; then
      # The 16x16 world fills this 256x256 window; sample the cursor cell center.
      pixel_x=$((window_x + cell_x * 16 + 8))
      pixel_y=$((window_y + cell_z * 16 + 8))
      if result=$(python3 "$frame_reader" "$frame_file" "$pixel_x" "$pixel_y" "$expected_rgb" 2>&1); then
        printf 'VISIBLE_%s=verified %s\n' "$label" "$result"
        return 0
      else
        result_status=$?
      fi
      last_result=$result
      if [ "$result_status" -eq 2 ]; then
        printf 'VISIBLE_%s=not-verified %s\n' "$label" "$last_result"
        return 2
      fi
    fi
    if ! kill -0 "$app_pid" 2>/dev/null; then
      printf 'Native app exited before cursor frame was observed\n' >&2
      return 3
    fi
    sleep 0.05
  done
  printf 'VISIBLE_%s=not-verified timeout; last result: %s\n' "$label" "$last_result"
  return 1
}

wait_for_frame_pixel 8 8 initial_cursor ffffff

timeout 2s xdotool key --clearmodifiers w
wait_for_frame_pixel 8 7 after_w ffffff

timeout 2s xdotool key --clearmodifiers e
deadline=$((SECONDS + 10))
while [ "$SECONDS" -lt "$deadline" ]; do
  if [ -f "$save_file" ] && [ "$(wc -c < "$save_file")" -eq 2 ]; then
    saved_bytes=$(od -An -tu1 -v "$save_file" | awk '{$1=$1; print}')
    if [ "$saved_bytes" = '8 7' ]; then
      break
    fi
  fi
  if ! kill -0 "$app_pid" 2>/dev/null; then
    printf 'Native app exited before writing the expected edit; see %s\n' "$app_log" >&2
    exit 1
  fi
  sleep 0.05
done
if [ ! -f "$save_file" ] || [ "$(wc -c < "$save_file")" -ne 2 ] || [ "${saved_bytes-}" != '8 7' ]; then
  actual_bytes='<missing or wrong length>'
  if [ -f "$save_file" ]; then
    actual_bytes=$(od -An -tu1 -v "$save_file" | awk '{$1=$1; print}')
  fi
  printf 'Expected native edit bytes [8,7], got [%s]; save=%s\n' "$actual_bytes" "$save_file" >&2
  exit 1
fi
printf 'KEY_W_AND_E_SAVE=verified bytes=[%s]\n' "${saved_bytes/ /,}"

timeout 2s xdotool key --clearmodifiers Escape
deadline=$((SECONDS + 10))
while kill -0 "$app_pid" 2>/dev/null && [ "$SECONDS" -lt "$deadline" ]; do
  sleep 0.05
done
if kill -0 "$app_pid" 2>/dev/null; then
  printf 'Native app did not exit after Escape; see %s\n' "$app_log" >&2
  exit 1
fi
if wait "$app_pid"; then
  app_status=0
else
  app_status=$?
fi
first_app_pid=$app_pid
app_pid=
if [ "$app_status" -ne 0 ]; then
  printf 'Native app exited with status %s after Escape; see %s\n' "$app_status" "$app_log" >&2
  exit 1
fi
if timeout 2s xdotool search --onlyvisible --name '^Bend2Craft native$' >/dev/null 2>&1; then
  printf 'Native window remained visible after Escape\n' >&2
  exit 1
fi
printf 'ESCAPE_EXIT=verified status=0\n'
printf 'FIRST_PROCESS_EXIT=verified pid=%s\n' "$first_app_pid"

restart_log="$run_dir/restart.log"
(
  cd "$run_dir"
  exec "$binary"
) >"$restart_log" 2>&1 &
app_pid=$!

window_id=
deadline=$((SECONDS + 15))
while [ "$SECONDS" -lt "$deadline" ]; do
  if ! kill -0 "$app_pid" 2>/dev/null; then
    printf 'Native app exited before restoring saved cursor; see %s\n' "$restart_log" >&2
    exit 1
  fi
  if window_ids=$(timeout 2s xdotool search --onlyvisible --name '^Bend2Craft native$' 2>/dev/null); then
    window_id=${window_ids%%$'\n'*}
    if [ -n "$window_id" ]; then
      break
    fi
  fi
  sleep 0.05
done
if [ -z "$window_id" ]; then
  printf 'Timed out waiting for restored native window; see %s\n' "$restart_log" >&2
  exit 1
fi
printf 'WINDOW_REOPEN=verified window_id=%s\n' "$window_id"
printf 'PROCESS_RESTART=verified prior_pid=%s relaunched_pid=%s\n' "$first_app_pid" "$app_pid"

timeout 2s xdotool windowfocus --sync "$window_id"
focused_window=$(timeout 2s xdotool getwindowfocus)
if [ "$focused_window" != "$window_id" ]; then
  printf 'Restarted window focus mismatch: expected %s, got %s\n' "$window_id" "$focused_window" >&2
  exit 1
fi

window_geometry=$(timeout 2s xdotool getwindowgeometry --shell "$window_id")
window_x=$(printf '%s\n' "$window_geometry" | sed -n 's/^X=//p')
window_y=$(printf '%s\n' "$window_geometry" | sed -n 's/^Y=//p')
window_width=$(printf '%s\n' "$window_geometry" | sed -n 's/^WIDTH=//p')
window_height=$(printf '%s\n' "$window_geometry" | sed -n 's/^HEIGHT=//p')
for dimension in "$window_x" "$window_y" "$window_width" "$window_height"; do
  case "$dimension" in
    ''|*[!0-9]*) printf 'Could not read restarted window geometry:\n%s\n' "$window_geometry" >&2; exit 1 ;;
  esac
done
if [ "$window_width" -ne 256 ] || [ "$window_height" -ne 256 ]; then
  printf 'Unexpected restarted window size: %sx%s\n' "$window_width" "$window_height" >&2
  exit 1
fi

wait_for_frame_pixel 8 7 restored_cursor ffffff
timeout 2s xdotool key --clearmodifiers d
wait_for_frame_pixel 8 7 persisted_edit 858585
wait_for_frame_pixel 9 7 after_d_cursor ffffff

second_app_pid=$app_pid
timeout 2s xdotool key --clearmodifiers Escape
deadline=$((SECONDS + 10))
while kill -0 "$app_pid" 2>/dev/null && [ "$SECONDS" -lt "$deadline" ]; do
  sleep 0.05
done
if kill -0 "$app_pid" 2>/dev/null; then
  printf 'Restarted native app did not exit after Escape; see %s\n' "$restart_log" >&2
  exit 1
fi
if wait "$app_pid"; then
  app_status=0
else
  app_status=$?
fi
app_pid=
if [ "$app_status" -ne 0 ]; then
  printf 'Restarted app exited with status %s after Escape; see %s\n' "$app_status" "$restart_log" >&2
  exit 1
fi
if timeout 2s xdotool search --onlyvisible --name '^Bend2Craft native$' >/dev/null 2>&1; then
  printf 'Restarted native window remained visible after Escape\n' >&2
  exit 1
fi
printf 'RESTART_ESCAPE_EXIT=verified pid=%s status=0 no_window=true\n' "$second_app_pid"

stop_pid "$xvfb_pid"
xvfb_pid=
printf 'SMOKE=PASS\n'
