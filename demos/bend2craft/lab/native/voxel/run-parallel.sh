#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
SCRATCH="$ROOT/scratchpad/voxel-probe"
BEND="${BEND_BIN:-$ROOT/.tools/bend-local/bin/bend}"
RUNS=7
# The thread counts the frame is measured at. The default is the host's whole
# range; override with THREAD_COUNTS to sweep another set.
THREAD_COUNTS="${THREAD_COUNTS:-1 4 8 16}"

if [ ! -x "$BEND" ]; then
  printf 'Bend 2 compiler is missing or not executable: %s\n' "$BEND" >&2
  exit 1
fi
if [ "$("$BEND" version)" != 'bend 2.0.35' ]; then
  printf 'Native voxel probe requires Bend 2.0.35: %s\n' "$BEND" >&2
  exit 1
fi

mkdir -p "$SCRATCH"
TEST_BIN="$SCRATCH/voxel_probe_test"
PAR_TEST_BIN="$SCRATCH/voxel_probe_parallel_test"
BENCH_BIN="$SCRATCH/parallel_frame_bench"
RUN_OUTPUT="$SCRATCH/parallel-run-output.txt"
SAMPLES="$SCRATCH/parallel-phase-samples.txt"

printf 'compiler: '
"$BEND" version
printf 'target: native C executable; --gpu off; image forked with a bang\n'
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
printf 'C compiler: '
clang --version | sed -n '1p'

# A stale binary would let a failed check look green, so clear the binaries and
# treat any checker complaint as a hard failure.
rm -f "$TEST_BIN" "$PAR_TEST_BIN" "$BENCH_BIN"
"$BEND" lab/native/voxel/voxel_test.bend -o "$TEST_BIN"
"$BEND" lab/native/voxel/voxel_probe_parallel_test.bend -o "$PAR_TEST_BIN"
"$BEND" lab/native/voxel/parallel_frame_bench.bend -o "$BENCH_BIN"

# Collect no timing until the pinned goldens, the camera tests and the
# parallel-equals-single-thread test pass, and until the parallel test has passed
# at every measured thread count: a fork tree that changed the pixels at 16
# threads would be a different program, not a faster one.
"$TEST_BIN" --threads 1 --gpu off
for threads in $THREAD_COUNTS; do
  printf 'parallel test --threads %s: ' "$threads"
  "$PAR_TEST_BIN" --threads "$threads" --gpu off | tail -n 1
done

# Warm the executable and its code pages; every measured process re-runs every
# timed phase, and every timed phase prints its own forcing IO.print.
"$BENCH_BIN" --threads 1 --gpu off > /dev/null

: > "$SAMPLES"
for threads in $THREAD_COUNTS; do
  run=1
  while [ "$run" -le "$RUNS" ]; do
    "$BENCH_BIN" --threads "$threads" --gpu off > "$RUN_OUTPUT"
    # The benchmark's own contract: the forked frame and the single-thread frame
    # are the same pixels, so their digests must agree in the same process.
    awk -v threads="$threads" '
      /^phase=/ {
        phase = ""
        size = ""
        digest = ""
        for (i = 1; i <= NF; i++) {
          split($i, kv, "=")
          if (kv[1] == "phase") phase = kv[2]
          else if (kv[1] == "size") size = kv[2]
          else if (kv[1] == "digest") digest = kv[2]
        }
        seen[phase " " size] = digest
      }
      END {
        for (key in seen) {
          split(key, part, " ")
          if (part[1] == "frame") single[part[2]] = seen[key]
          if (part[1] == "frame_par") forked[part[2]] = seen[key]
        }
        for (size in single) {
          if (!(size in forked)) {
            printf "no forked frame digest at size %s threads %s\n", size, threads
            failed = 1
          } else if (single[size] != forked[size]) {
            printf "forked frame digest %s != single-thread digest %s at size %s threads %s\n",
              forked[size], single[size], size, threads
            failed = 1
          }
        }
        if (failed) exit 1
        printf "forked frame digest matches the single-thread frame at threads %s\n", threads
      }
    ' "$RUN_OUTPUT"
    grep '^phase=' "$RUN_OUTPUT" | sed "s/ digest=[0-9]*\$//" \
      | sed "s/^/threads=$threads /" >> "$SAMPLES"
    printf 'threads=%s sample=%d\n' "$threads" "$run"
    grep '^phase=' "$RUN_OUTPUT" | sed 's/^/  /'
    run=$((run + 1))
  done
done

# Median and range per phase and size, keyed by the phase, size, iteration count
# and thread count each sample carries.
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
      printf "%s median_ms=%.0f range_ms=[%.0f,%.0f] samples=%d\n",
        key, median, value[key, 1], value[key, count], count
    }
  }
' "$SAMPLES" | sort
