#!/usr/bin/env bash
# Native visible-face probe. Correctness first, then timings, in the same shape
# as lab/native/voxel/run.sh: clear stale binaries, compile the focused tests
# and benchmarks, run correctness checks at every measured thread count before
# any timing is collected, then take seven samples and report per-call medians.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
SCRATCH="$ROOT/scratchpad/face-probe"
BEND="${BEND_BIN:-$ROOT/.tools/bend-local/bin/bend}"
RUNS=7
THREAD_COUNTS="${THREAD_COUNTS:-1 8}"

if [ ! -x "$BEND" ]; then
  printf 'Bend 2 compiler is missing or not executable: %s\n' "$BEND" >&2
  exit 1
fi
if [ "$("$BEND" version)" != 'bend 2.0.35' ]; then
  printf 'Native face probe requires Bend 2.0.35: %s\n' "$BEND" >&2
  exit 1
fi

mkdir -p "$SCRATCH"
TEST_BIN="$SCRATCH/face_probe_test"
BENCH_BIN="$SCRATCH/frame_bench"
SPLIT_BIN="$SCRATCH/prep_split_bench"
SUMMARY_BIN="$SCRATCH/bucket_summary"
RUN_OUTPUT="$SCRATCH/run-output.txt"
SPLIT_OUTPUT="$SCRATCH/split-output.txt"
SAMPLES="$SCRATCH/phase-samples.txt"

printf 'compiler: '
"$BEND" version
printf 'target: native C executable; --gpu off; CPU visible-face renderer\n'
printf 'platform: '
uname -a
if [ -r /proc/cpuinfo ]; then
  printf 'cpu: '
  awk -F: '/^model name[[:space:]]*:/ { sub(/^[[:space:]]*/, "", $2); print $2; exit }' /proc/cpuinfo
else
  printf 'cpu: unavailable\n'
fi
printf 'C compiler: '
clang --version | sed -n '1p'

# A stale binary would let a failed check look green, so clear it first and treat
# any checker complaint as a hard failure.
rm -f "$TEST_BIN" "$BENCH_BIN" "$SPLIT_BIN" "$SUMMARY_BIN"
"$BEND" lab/native/face/face_test.bend -o "$TEST_BIN"
"$BEND" lab/native/face/frame_bench.bend -o "$BENCH_BIN"
"$BEND" lab/native/face/prep_split_bench.bend -o "$SPLIT_BIN"
"$BEND" lab/native/face/bucket_summary.bend -o "$SUMMARY_BIN"

# Collect no timing until the single-block fixture, the extraction pins and the
# extraction-vs-grid agreement all pass, at every thread count that will be timed.
for threads in $THREAD_COUNTS; do
  printf 'threads=%d ' "$threads"
  "$TEST_BIN" --threads "$threads" --gpu off | tail -1
done

# Show candidates and source-level list-cell counts for all tested tile edges.
# This summary is outside the timed samples and folds no lazy bucket values.
"$SUMMARY_BIN" --threads 1 --gpu off

# Warm the executables and their code pages; each measured process re-runs every
# timed phase, and every timed phase prints its own forcing IO.print.
"$BENCH_BIN" --threads 1 --gpu off > /dev/null
"$SPLIT_BIN" --threads 1 --gpu off > /dev/null

: > "$SAMPLES"
for threads in $THREAD_COUNTS; do
  run=1
  while [ "$run" -le "$RUNS" ]; do
    "$BENCH_BIN" --threads "$threads" --gpu off > "$RUN_OUTPUT"
    grep '^phase=' "$RUN_OUTPUT" | sed "s/^/threads=$threads /" >> "$SAMPLES"
    "$SPLIT_BIN" --threads "$threads" --gpu off > "$SPLIT_OUTPUT"
    grep '^phase=' "$SPLIT_OUTPUT" | sed "s/^/threads=$threads /" >> "$SAMPLES"
    run=$((run + 1))
  done
  printf 'sampled threads=%d runs=%d\n' "$threads" "$RUNS"
done

# Median and range per phase, keyed by thread count, phase name and size.
awk '
  /^threads=/ {
    threads = ""
    phase = ""
    size = ""
    edge = ""
    iters = ""
    for (i = 1; i <= NF; i++) {
      split($i, kv, "=")
      if (kv[1] == "threads") threads = kv[2]
      else if (kv[1] == "phase") phase = kv[2]
      else if (kv[1] == "size") size = kv[2]
      else if (kv[1] == "edge") edge = kv[2]
      else if (kv[1] == "iterations") iters = kv[2]
      else if (kv[1] == "elapsed_ms") {
        key = "threads=" threads " " phase " size=" size " edge=" edge
        n[key]++
        value[key, n[key]] = (kv[2] + 0) / (iters + 0)
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
      printf "%s median_ms=%.3f range_ms=[%.3f,%.3f] samples=%d\n",
        key, median, value[key, 1], value[key, count], count
    }
  }
' "$SAMPLES" | sort
