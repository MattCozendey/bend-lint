#!/usr/bin/env bash
# Native frame-cost probe.
#
# Correctness first: the focused test runs at every measured thread count before a
# single timing is taken, and the benchmark itself refuses to run if the cached-grid
# frame, the rebuild-per-frame frame and the `sky` control do not answer three
# different images. Then seven timed samples per phase, with the median and the
# range over those seven.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
SCRATCH="$ROOT/scratchpad/frame-probe"
BEND="${BEND_BIN:-$ROOT/.tools/bend-local/bin/bend}"
RUNS=7
# The budget table needs a single-thread and a parallel column; override to sweep
# another set.
THREAD_COUNTS="${THREAD_COUNTS:-1 8}"

if [ ! -x "$BEND" ]; then
  printf 'Bend 2 compiler is missing or not executable: %s\n' "$BEND" >&2
  exit 1
fi
if [ "$("$BEND" version)" != 'bend 2.0.35' ]; then
  printf 'Native frame probe requires Bend 2.0.35: %s\n' "$BEND" >&2
  exit 1
fi

mkdir -p "$SCRATCH"
TEST_BIN="$SCRATCH/frame_probe_test"
BENCH_BIN="$SCRATCH/frame_bench"
RUN_OUTPUT="$SCRATCH/run-output.txt"
SAMPLES="$SCRATCH/phase-samples.txt"

printf 'compiler: '
"$BEND" version
printf 'target: native C executable; --gpu off; one whole frame per sample\n'
printf 'frame: events -> Player.step against a cached 2x2 chunk region -> Camera.look\n'
printf '  -> render -> image fingerprint; the render stage is frame_probe.render\n'
printf 'platform: '
uname -a
if [ -r /proc/cpuinfo ]; then
  printf 'cpu: '
  awk -F: '/^model name[[:space:]]*:/ { sub(/^[[:space:]]*/, "", $2); print $2; exit }' /proc/cpuinfo
else
  printf 'cpu: unavailable\n'
fi
printf 'visible processors: '
nproc 2>/dev/null || printf 'unavailable\n'
printf 'thread counts: %s\n' "$THREAD_COUNTS"
printf 'C compiler: '
clang --version | sed -n '1p'
printf 'samples per phase: %d\n' "$RUNS"

# A stale binary would let a failed check look green, so clear the binaries and
# treat any checker complaint as a hard failure.
rm -f "$TEST_BIN" "$BENCH_BIN"
"$BEND" lab/native/frame/frame_test.bend -o "$TEST_BIN"
"$BEND" lab/native/frame/frame_bench.bend -o "$BENCH_BIN"

# Collect no timing until the dirty-frame condition, the eye rebasing, the input
# fold, the multi-chunk region, the render seam and the dirty path have all passed
# at every measured thread count.
for threads in $THREAD_COUNTS; do
  printf 'frame-probe test --threads %s: ' "$threads"
  "$TEST_BIN" --threads "$threads" --gpu off | tail -n 1
done

# Warm the executable and its code pages; every measured process re-runs every
# timed phase, and every timed phase prints its own forcing IO.print.
"$BENCH_BIN" --threads 1 --gpu off > /dev/null

: > "$SAMPLES"
for threads in $THREAD_COUNTS; do
  run=1
  while [ "$run" -le "$RUNS" ]; do
    "$BENCH_BIN" --threads "$threads" --gpu off > "$RUN_OUTPUT"
    # The benchmark's own contract: the cached-grid frame and the
    # rebuild-per-frame frame must agree at every size, and neither may equal the
    # sky control. A disagreement means the numbers below are three programs.
    grep '^agreement ' "$RUN_OUTPUT" | sed "s/^/threads=$threads /" >> "$SAMPLES"
    grep '^phase=' "$RUN_OUTPUT" | sed "s/ digest=[0-9]*\$//" \
      | sed "s/^/threads=$threads /" >> "$SAMPLES"
    printf 'threads=%s sample=%d phases=%d\n' "$threads" "$run" \
      "$(grep -c '^phase=' "$RUN_OUTPUT")"
    run=$((run + 1))
  done
done

# Median and range per phase, size, iteration count and thread count. `per_frame_ms`
# and `fps` are the per-frame figures the budget table needs, derived from the same
# medians rather than from a separate run.
printf '\nagreement (the cached frame, the rebuilt frame and the sky control):\n'
sort -u "$SAMPLES" | grep '^threads=[0-9]* agreement ' \
  | sed -e 's/^threads=\([0-9]*\) /\1 /' -e 's/^/  /' | sort -k1,1n -k2,2n

printf '\nmedians over %d samples:\n' "$RUNS"
awk '
  /^threads=/ {
    threads = ""
    phase = ""
    size = ""
    iters = ""
    for (i = 1; i <= NF; i++) {
      split($i, kv, "=")
      if (kv[1] == "threads") threads = kv[2]
      else if (kv[1] == "phase") phase = kv[2]
      else if (kv[1] == "size") size = kv[2]
      else if (kv[1] == "iterations") iters = kv[2]
      else if (kv[1] == "elapsed_ms") {
        key = phase " size=" size " iterations=" iters " threads=" threads
        n[key]++
        value[key, n[key]] = kv[2] + 0
      }
    }
  }
  END {
    for (key in n) {
      count = n[key]
      for (i = 2; i <= count; i++) {
        current = value[key, i]
        j = i - 1
        while (j >= 1 && value[key, j] > current) {
          value[key, j + 1] = value[key, j]
          j--
        }
        value[key, j + 1] = current
      }
      median = value[key, (count + 1) / 2]
      split(key, part, " ")
      iterations = 0
      for (i = 1; i <= 5; i++) {
        if (part[i] ~ /^iterations=/) {
          split(part[i], kv, "=")
          iterations = kv[2] + 0
        }
      }
      if (iterations > 0) {
        per_frame = median / iterations
        fps = per_frame > 0 ? 1000 / per_frame : 0
        printf "%s median_ms=%.0f range_ms=[%.0f,%.0f] per_frame_ms=%.3f fps=%.1f samples=%d\n",
          key, median, value[key, 1], value[key, count], per_frame, fps, count
      } else {
        printf "%s median_ms=%.0f range_ms=[%.0f,%.0f] samples=%d\n",
          key, median, value[key, 1], value[key, count], count
      }
    }
  }
  ' "$SAMPLES" | sort -k1,1 -k3,3n -k7,7n

printf '\nbudget: 16.7 ms is 60 FPS and 33.3 ms is 30 FPS. A size fits when its\n'
printf 'per_frame_ms at the row above is at or under the budget.\n'
