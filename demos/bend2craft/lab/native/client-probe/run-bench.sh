#!/usr/bin/env bash
# The native client's frame cost. Correctness first, then timings, in the same shape
# as lab/native/face/run.sh: clear stale binaries, compile the benchmark to a
# native C executable, then take seven samples and report per-call medians.
#
# The phases are the client's own stages at the size and tile edge the client ships:
# the tick, the render, and the two together. The two together is the number the
# 60 Hz budget is judged on, and the script says whether it fits.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# Three levels up, like run-fps.sh beside it: this file is lab/native/client-probe,
# so `../..` is `lab`, which holds neither the compiler nor the scratch folder, and
# the script refused to run at all.
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)
SCRATCH="$ROOT/scratchpad/client-probe"
BEND="${BEND_BIN:-$ROOT/.tools/bend-local/bin/bend}"
RUNS="${RUNS:-7}"
THREAD_COUNTS="${THREAD_COUNTS:-1 8}"

if [ ! -x "$BEND" ]; then
  printf 'Bend 2 compiler is missing or not executable: %s\n' "$BEND" >&2
  exit 1
fi
if [ "$("$BEND" version)" != 'bend 2.0.35' ]; then
  printf 'Native client benchmark requires Bend 2.0.35: %s\n' "$BEND" >&2
  exit 1
fi

mkdir -p "$SCRATCH"
BINARY="$SCRATCH/frame_bench"
OUTPUT="$SCRATCH/run-output.txt"
SAMPLES="$SCRATCH/phase-samples.txt"

printf 'compiler: '
"$BEND" version
printf 'target: native C executable; --gpu off; the shipped client frame\n'
printf 'platform: '
uname -a
if [ -r /proc/cpuinfo ]; then
  printf 'cpu: '
  awk -F: '/^model name[[:space:]]*:/ { sub(/^[[:space:]]*/, "", $2); print $2; exit }' /proc/cpuinfo
fi

rm -f "$BINARY" "$OUTPUT" "$SAMPLES"
"$BEND" "$SCRIPT_DIR/frame_bench.bend" -o "$BINARY" >/dev/null

# The client writes its world next to its own relative path, so a benchmark run
# must not start from or write to the repository's world file.
rm -f "$ROOT/native/client-world.b2cw"

for threads in $THREAD_COUNTS; do
  printf '=== threads=%s ===\n' "$threads"
  : > "$SAMPLES"
  run=1
  while [ "$run" -le "$RUNS" ]; do
    "$BINARY" --threads "$threads" > "$OUTPUT" 2>&1 || {
      printf 'The benchmark failed; see %s\n' "$OUTPUT" >&2
      cat "$OUTPUT" >&2
      exit 1
    }
    grep -E '^phase=' "$OUTPUT" >> "$SAMPLES"
    run=$((run + 1))
  done
  # One line per phase per run: "phase=NAME size=N iterations=N elapsed_ms=NN digest=D".
  # The samples are grouped by phase and reduced to a median, because a single run's
  # millisecond resolution is coarse for the cheap phases, and each phase's total is
  # divided by its iteration count so the number is per frame.
  sed -E 's/^phase=([a-z_0-9]+)[[:space:]]+size=([0-9]+)[[:space:]]+iterations=([0-9]+)[[:space:]]+elapsed_ms=([0-9]+).*/\1 \3 \4 \2/' \
    "$SAMPLES" > "$SCRATCH/phase-numbers.txt"
  awk -v threads="$threads" '
    { key = $1
      values[key, ++counts[key]] = $3
      iterations[key] = $2
      size[key] = $4
    }
    END {
      for (key in counts) {
        n = counts[key]
        for (i = 1; i <= n; i++) ordered[key, i] = values[key, i]
        for (i = 1; i <= n; i++)
          for (j = i + 1; j <= n; j++)
            if (ordered[key, j] < ordered[key, i]) {
              swap = ordered[key, i]; ordered[key, i] = ordered[key, j]; ordered[key, j] = swap
            }
        median = (n % 2) ? ordered[key, (n + 1) / 2] \
          : (ordered[key, n / 2] + ordered[key, n / 2 + 1]) / 2
        printf "threads=%s phase=%-11s size=%-4s median_ms=%.2f min_ms=%.2f max_ms=%.2f samples=%d\n",
          threads, key, size[key], median / iterations[key], ordered[key, 1] / iterations[key],
          ordered[key, n] / iterations[key], n
      }
    }
  ' "$SCRATCH/phase-numbers.txt" | sort -k2,2 -k3,3
  grep -E '^client-bench=' "$OUTPUT" || true
done

printf 'full output: %s\n' "$OUTPUT"
