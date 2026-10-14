#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
SCRATCH="$ROOT/scratchpad/bench-probe"
BEND="${BEND_BIN:-$ROOT/.tools/bend-local/bin/bend}"
RUNS=7

if [ ! -x "$BEND" ]; then
  printf 'Local Bend 2 compiler is missing or not executable: %s\n' "$BEND" >&2
  exit 1
fi
if [ "$("$BEND" version)" != 'bend 2.0.35' ]; then
  printf 'Native benchmark requires Bend 2.0.35: %s\n' "$BEND" >&2
  exit 1
fi

mkdir -p "$SCRATCH"
TEST_BIN="$SCRATCH/bench_probe_test"
BENCH_BIN="$SCRATCH/bench_probe"
STARTUP_BIN="$SCRATCH/startup_probe"

printf 'compiler: '
"$BEND" version
printf 'target: native C executable; --threads 1 --gpu off; no parallel ! calls\n'
printf 'platform: '
uname -a
if [ -r /proc/cpuinfo ]; then
  printf 'cpu: '
  awk -F: '/^model name[[:space:]]*:/ { sub(/^[[:space:]]*/, "", $2); print $2; exit }' /proc/cpuinfo
elif command -v sysctl >/dev/null 2>&1; then
  printf 'cpu: '
  sysctl -n machdep.cpu.brand_string
else
  printf 'cpu: unavailable\n'
fi
printf 'C compiler: '
clang --version | sed -n '1p'

"$BEND" lab/native/bench-probe/bench_probe_test.bend -o "$TEST_BIN"
"$BEND" lab/native/bench-probe/bench_probe.bend -o "$BENCH_BIN"
"$BEND" lab/native/bench-probe/startup_probe.bend -o "$STARTUP_BIN"

# Refuse to collect timings unless the seed/chunk and native image pins pass.
"$TEST_BIN" --threads 1 --gpu off

RESULTS="$SCRATCH/results.tsv"
RUN_OUTPUT="$SCRATCH/run-output.txt"
TIME_OUTPUT="$SCRATCH/time-output.txt"
: > "$RESULTS"
TIMEFORMAT='%3R'

run=1
while [ "$run" -le "$RUNS" ]; do
  { time "$STARTUP_BIN" --threads 1 --gpu off >/dev/null; } 2> "$TIME_OUTPUT"
  startup_seconds=$(sed -n '1p' "$TIME_OUTPUT")

  { time "$BENCH_BIN" --threads 1 --gpu off > "$RUN_OUTPUT"; } 2> "$TIME_OUTPUT"
  process_seconds=$(sed -n '1p' "$TIME_OUTPUT")
  chunk_ms=$(awk -F '[ =]' '/^phase=chunk / { print $6; exit }' "$RUN_OUTPUT")
  image_ms=$(awk -F '[ =]' '/^phase=image / { print $6; exit }' "$RUN_OUTPUT")
  chunk_repetitions=$(awk -F '[ =]' '/^phase=chunk / { print $4; exit }' "$RUN_OUTPUT")
  image_repetitions=$(awk -F '[ =]' '/^phase=image / { print $4; exit }' "$RUN_OUTPUT")
  if [ -z "$chunk_ms" ] || [ -z "$image_ms" ] \
    || [ -z "$chunk_repetitions" ] || [ -z "$image_repetitions" ]; then
    printf 'Benchmark output did not include both phase timings.\n' >&2
    cat "$RUN_OUTPUT" >&2
    exit 1
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$chunk_ms" "$image_ms" \
    "$startup_seconds" "$process_seconds" "$chunk_repetitions" \
    "$image_repetitions" >> "$RESULTS"
  printf 'sample=%s chunk_ms=%s image_ms=%s startup_control_s=%s process_wall_s=%s\n' \
    "$run" "$chunk_ms" "$image_ms" "$startup_seconds" "$process_seconds"
  if [ "$run" -eq 1 ]; then
    cat "$RUN_OUTPUT"
  fi
  run=$((run + 1))
done

awk -F '\t' '
  {
    n++
    chunk[n] = $1 + 0
    image[n] = $2 + 0
    startup[n] = $3 + 0
    process[n] = $4 + 0
    chunk_reps = $5 + 0
    image_reps = $6 + 0
  }
  function report(label, column, divisor, unit,   i, j, value, temp, median) {
    for (i = 1; i <= n; i++) {
      if (column == 1) value[i] = chunk[i]
      if (column == 2) value[i] = image[i]
      if (column == 3) value[i] = startup[i]
      if (column == 4) value[i] = process[i]
    }
    for (i = 2; i <= n; i++) {
      temp = value[i]
      j = i - 1
      while (j >= 1 && value[j] > temp) {
        value[j + 1] = value[j]
        j--
      }
      value[j + 1] = temp
    }
    if (n % 2) median = value[(n + 1) / 2]
    else median = (value[n / 2] + value[n / 2 + 1]) / 2
    if (column <= 2) {
      printf "%s median=%.0f range=[%.0f,%.0f] %s", label, median, value[1], value[n], unit
      if (divisor > 0) printf " median_per_op_ms=%.3f", median / divisor
      printf "\n"
    } else {
      printf "%s median=%.3f range=[%.3f,%.3f] %s\n", label, median, value[1], value[n], unit
    }
  }
  END {
    report("chunk_build_plus_fingerprint", 1, chunk_reps, "ms_total")
    report("native_image_plus_fingerprint", 2, image_reps, "ms_total")
    report("startup_control_process_wall", 3, 0, "seconds")
    report("full_benchmark_process_wall", 4, 0, "seconds")
  }
' "$RESULTS"
