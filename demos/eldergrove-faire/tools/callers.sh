#!/bin/bash
# tools/callers.sh SYMBOL: who calls SYMBOL in the last tools/prof.sh run
PERF=$(ls /usr/lib/linux-tools/*/perf | head -1)
$PERF report -i /tmp/park.perf --no-children --symbols "$1" -g caller,0.5,callee --stdio 2>&1 | grep -v "^#" | grep -v "^$" | head -${2:-50}
