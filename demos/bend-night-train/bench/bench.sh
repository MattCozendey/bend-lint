#!/usr/bin/env bash
# Benchmark driver for the night-train renderer.
#
# Times one rasterised frame at several depths and thread counts and records
# wall and user time plus the frame checksum.  The checksum is the correctness
# check: it must be the same at every thread count, because the render is pure.
#
#   ./bench/bench.sh [binary] [csv]
#   ./bench/bench.sh --depth 9 --threads 8 --reps 5
#
# The renderer has no `!` call -- the device lane was measured and dropped, see
# docs/journal.md -- so there is no backend to select: every row is the CPU
# build, and `--gpu` would be inert.
#
# Configuration (flags override the env defaults):
#   DEPTHS="8 9 10"   THREADS="1 2 4 8 16 32"   REPS=3
#
# A single cell is just one depth and one thread count, e.g. re-measure depth
# 10 with 8 threads, five reps, into its own file:
#
#   ./bench/bench.sh --depth 10 --threads 8 --reps 5 --out bench/results-d10.csv
#
# Columns: depth,threads,rep,wall_s,user_s,checksum

set -uo pipefail

BIN=${BIN:-out/night-train}
OUT=${OUT:-bench/results.csv}
REPS=${REPS:-3}
DEPTHS=${DEPTHS:-"8 9 10"}
THREADS=${THREADS:-"1 2 4 8 16 32"}

usage() { sed -n '2,32p' "$0"; }

positional=()
while [ $# -gt 0 ]; do
  case "$1" in
    --depth)     DEPTHS=$2; shift 2 ;;
    --depth=*)   DEPTHS=${1#*=}; shift ;;
    --threads)   THREADS=$2; shift 2 ;;
    --threads=*) THREADS=${1#*=}; shift ;;
    --reps)      REPS=$2; shift 2 ;;
    --reps=*)    REPS=${1#*=}; shift ;;
    --out)       OUT=$2; shift 2 ;;
    --out=*)     OUT=${1#*=}; shift ;;
    -h|--help)   usage; exit 0 ;;
    -*)          echo "bench.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
    *)           positional+=("$1"); shift ;;
  esac
done

if [ "${#positional[@]}" -ge 1 ]; then BIN=${positional[0]}; fi
if [ "${#positional[@]}" -ge 2 ]; then OUT=${positional[1]}; fi

# `run()` prefixes a relative binary with ./; keep an absolute path as-is.
case "$BIN" in /*) ;; *) BIN="./$BIN" ;; esac

mkdir -p "$(dirname "$OUT")"
echo "depth,threads,rep,wall_s,user_s,checksum" > "$OUT"

run() {
  local d=$1 t=$2 rep=$3
  local tmp
  tmp=$(mktemp)
  NT_DEPTH="$d" NT_PPM=0 \
    /usr/bin/time -f "%e %U" -o "$tmp" "$BIN" --threads "$t" > "$tmp.out" 2>/dev/null
  local chk wall user
  chk=$(tr -d '[:space:]' < "$tmp.out")
  read -r wall user < "$tmp"
  echo "$d,$t,$rep,$wall,$user,$chk" >> "$OUT"
  rm -f "$tmp" "$tmp.out"
}

# One warm-up pass so the first measurement is not the one that pays for
# parsing the binary or faulting in the heap.
warm_depth=${DEPTHS%% *}
NT_DEPTH="$warm_depth" NT_PPM=0 "$BIN" --threads 4 >/dev/null 2>&1

for d in $DEPTHS; do
  for t in $THREADS; do
    for rep in $(seq 1 "$REPS"); do
      run "$d" "$t" "$rep"
      printf '.' >&2
    done
  done
done
printf '\n' >&2
echo "wrote $OUT"
