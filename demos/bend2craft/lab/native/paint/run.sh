#!/usr/bin/env bash
# The painter's frame cost per window size, per thread count.
#
# Compiles lab/native/paint/paint_bench.bend to a native C executable, takes RUNS
# samples at each thread count, and reports the per-frame median of every phase. The
# digest of each phase must be the same at every thread count: a partitioned painter
# that drew a different picture on eight threads than on one would be a race, not a
# speedup.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)
SCRATCH="$ROOT/scratchpad/paint"
BEND="${BEND_BIN:-$ROOT/.tools/bend-local/bin/bend}"
RUNS="${RUNS:-7}"
THREAD_COUNTS="${THREAD_COUNTS:-1 2 4 8}"
# `on` asks the runtime for the device; the default is the CPU pool, which is what every number
# in the README was taken with unless its section says otherwise.
GPU="${GPU:-off}"

if [ ! -x "$BEND" ]; then
  printf 'Bend 2 compiler is missing or not executable: %s\n' "$BEND" >&2
  exit 1
fi

mkdir -p "$SCRATCH"
BINARY="$SCRATCH/paint_bench"
SAMPLES="$SCRATCH/samples.txt"

printf 'compiler: '
BEND_NO_TELEMETRY=1 "$BEND" version
printf 'target: native C executable; --gpu %s\n' "$GPU"
if [ -r /proc/cpuinfo ]; then
  printf 'cpu: '
  awk -F: '/^model name[[:space:]]*:/ { sub(/^[[:space:]]*/, "", $2); print $2; exit }' /proc/cpuinfo
fi

rm -f "$BINARY" "$SAMPLES"
BEND_NO_TELEMETRY=1 "$BEND" "$SCRIPT_DIR/paint_bench.bend" -o "$BINARY" >/dev/null

for threads in $THREAD_COUNTS; do
  run=1
  while [ "$run" -le "$RUNS" ]; do
    "$BINARY" --threads "$threads" --gpu "$GPU" | grep -E '^phase=' \
      | sed -E "s/^/threads=$threads /" >> "$SAMPLES"
    run=$((run + 1))
  done
done

# "threads=T phase=NAME size=N iterations=N elapsed_ms=NN digest=D"
sed -E 's/threads=([0-9]+) phase=([a-z_0-9]+) size=([0-9]+) iterations=([0-9]+) elapsed_ms=([0-9]+) digest=([0-9]+)/\1 \2 \3 \4 \5 \6/' \
  "$SAMPLES" | awk '
  { key = $2 " " $3 " " $1
    values[key, ++counts[key]] = $5 / $4
    name[key] = $2; size[key] = $3; threads[key] = $1
    # Every phase runs the same iteration count, so the digest is keyed by the size
    # alone: the two painters and every thread count have to agree on it.
    row = "size " $3
    # Only the one-tile and the tiled frame draw the same picture; every other phase is its
    # own scene and agrees with itself across thread counts.
    if ($2 != "whole" && $2 != "tiles") row = $2 " " $3
    if ($2 != "warm") {
      if (row in digest && digest[row] != $6) mismatch[row] = 1
      digest[row] = $6
    }
  }
  END {
    for (key in counts) {
      n = counts[key]
      for (i = 1; i <= n; i++) ordered[i] = values[key, i]
      for (i = 1; i <= n; i++)
        for (j = i + 1; j <= n; j++)
          if (ordered[j] < ordered[i]) { swap = ordered[i]; ordered[i] = ordered[j]; ordered[j] = swap }
      median = (n % 2) ? ordered[(n + 1) / 2] : (ordered[n / 2] + ordered[n / 2 + 1]) / 2
      printf "phase=%-8s size=%-5s threads=%s median_ms=%.2f min_ms=%.2f max_ms=%.2f samples=%d\n",
        name[key], size[key], threads[key], median, ordered[1], ordered[n], n
    }
    bad = 0
    for (row in mismatch) { printf "DIGEST MISMATCH between painters or thread counts: %s\n", row; bad = 1 }
    if (bad) exit 1
    print "digests=agree across painters and thread counts"
  }
' | sort -k1,1 -k2.6,2n -k3.9,3n
