#!/bin/bash
# tools/cfn.sh NAME [lines]: show an emitted-C function (spin_N or WL_FID_X)
# from park.c with its reference-count operations highlighted
cd "$(dirname "$0")/.."
[ -f park.c ] || { PATH="$HOME/.bend/bin:$PATH" bend main.bend -o park.c >/dev/null 2>&1; }
n=$(grep -n -E "^(INLINE|static|OUTLINE)?[^(]* $1\(" park.c | head -1 | cut -d: -f1)
[ -z "$n" ] && { echo "no $1"; exit 1; }
sed -n "${n},$((n + ${2:-80}))p" park.c
echo "--- counts in this range:"
sed -n "${n},$((n + ${2:-80}))p" park.c | grep -o -E "term_drop|term_keep|term_peek|ctr_take|rfc_seal|rfc_wrap|term_sink" | sort | uniq -c
