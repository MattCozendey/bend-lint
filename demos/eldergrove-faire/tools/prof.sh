#!/bin/bash
# tools/prof.sh <exe> [args...]: perf profile of a headless run, top symbols
cd "$(dirname "$0")/.."
export PATH="$HOME/.bend/bin:$PATH" BEND_NO_TELEMETRY=1
PERF=$(ls /usr/lib/linux-tools/*/perf | head -1)
$PERF record -g -o /tmp/park.perf -- "$@" >/tmp/prof.out 2>&1
cat /tmp/prof.out | tail -3
$PERF report -i /tmp/park.perf --no-children --sort symbol --stdio 2>/dev/null | grep -v "^#" | grep "%" | head -40
