#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BEND="${BEND_BIN:-$ROOT/.tools/bend-local/bin/bend}"
SCRATCH="$ROOT/scratchpad/player-probe"
TEST_BIN="$SCRATCH/player_probe_test"
BENCH_BIN="$SCRATCH/player_probe_bench"
LOG="$SCRATCH/player_probe_bench.log"
RUNS=7
# `one_chunk_every_tick` is the baseline the native client plan recorded as
# `world_state_chunk_to_player_step`: one bulk chunk and its one-chunk region
# rebuilt on every tick, 32 ticks total. The other phases separate the streaming
# cost from the tick cost and measure the multi-chunk contract.
PHASES='one_chunk_every_tick one_chunk_cached four_chunk_frame four_chunk_materialize'

if [ ! -x "$BEND" ]; then
  printf 'Pinned Bend compiler is missing or not executable: %s\n' "$BEND" >&2
  exit 1
fi
if [ "$("$BEND" version)" != 'bend 2.0.35' ]; then
  printf 'Native player probe requires Bend 2.0.35: %s\n' "$("$BEND" version)" >&2
  exit 1
fi

mkdir -p "$SCRATCH"
printf 'compiler: '
"$BEND" version
printf 'target: native C executable; --threads 1 --gpu off\n'
printf 'platform: '
uname -a
printf 'workload: one Player.step is 1/60 s of held input; a phase is the\n'
printf '  materialization of its collision region from bulk chunk exports plus\n'
printf '  the ticks named in its repetitions field; the player state is consumed\n'
printf '  by the phase and its final x/y/vy are printed with every sample.\n'

"$BEND" lab/native/player/player_test.bend -o "$TEST_BIN"
"$BEND" lab/native/player/player_probe_bench.bend -o "$BENCH_BIN"
"$TEST_BIN" --threads 1 --gpu off

: > "$LOG"
run=1
while [ "$run" -le "$RUNS" ]; do
  output=$("$BENCH_BIN" --threads 1 --gpu off)
  printf 'sample=%s\n%s\n' "$run" "$(printf '%s\n' "$output" | grep '^phase=')"
  printf '%s\n' "$output" | grep '^phase=' >> "$LOG"
  run=$((run + 1))
done

for phase in $PHASES; do
  results="$SCRATCH/player_probe_${phase}_ms.txt"
  sed -n "s/^phase=$phase .*elapsed_ms=\([0-9][0-9]*\).*/\1/p" "$LOG" > "$results"
  count=$(wc -l < "$results" | tr -d ' ')
  if [ "$count" -ne "$RUNS" ]; then
    printf 'Benchmark reported %s of %s samples for phase %s.\n' "$count" "$RUNS" "$phase" >&2
    exit 1
  fi
  sorted=$(sort -n "$results")
  median=$(printf '%s\n' "$sorted" | awk '
    { values[NR] = $1 }
    END {
      if (NR % 2) print values[(NR + 1) / 2]
      else printf "%.1f", (values[NR / 2] + values[NR / 2 + 1]) / 2
    }
  ')
  minimum=$(printf '%s\n' "$sorted" | sed -n '1p')
  maximum=$(printf '%s\n' "$sorted" | sed -n '$p')
  printf '%s runs=%s median_ms=%s range_ms=[%s,%s]\n' \
    "$phase" "$count" "$median" "$minimum" "$maximum"
done
