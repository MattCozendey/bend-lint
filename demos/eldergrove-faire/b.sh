#!/bin/bash
# usage: b.sh check <file> [lines] | b.sh build <file> <out> | b.sh try <secs> <exe> [args]
export PATH="$HOME/.bend/bin:$PATH"
export BEND_NO_TELEMETRY=1
cd "$(dirname "$0")"
case "$1" in
  check) bend "$2" --check-only 2>&1 | head -${3:-60} ;;
  build) s=$(date +%s); rm -f "$3"; bend "$2" -o "$3" 2>&1 | head -60; echo "[build ${3}: $(( $(date +%s) - s ))s]"; test -x "$3" ;;
  try) secs=$2; shift 2; timeout "$secs" "$@" 2>&1 | tail -20 ;;
  *) shift; "$@" ;;
esac
