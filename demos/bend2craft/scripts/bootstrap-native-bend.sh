#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL="${BEND_LOCAL_DIR:-$ROOT/.tools/bend-local}"
PIN=79df8d9c40722ee9507a1e253f283b51025f9d6c

if [[ "$(git -C "$ROOT/vendor/bend" rev-parse HEAD)" != "$PIN" ]]; then
  printf '%s\n' 'vendor/bend is not at the pinned Bend 2.0.35 commit.' >&2
  exit 1
fi

if [[ -e "$LOCAL/bin/bend" ]]; then
  if [[ -x "$LOCAL/bin/bend" && -f "$LOCAL/bend2/base.bend" \
    && -d "$LOCAL/bend2/effs" && -d "$LOCAL/guide" \
    && "$("$LOCAL/bin/bend" version)" == 'bend 2.0.35' ]]; then
    printf 'Bend 2.0.35 already available at %s\n' "$LOCAL/bin/bend"
    exit 0
  fi
  printf 'Refusing to overwrite an existing compiler: %s\n' "$LOCAL/bin/bend" >&2
  exit 1
fi

mkdir -p "$LOCAL/bin" "$LOCAL/bend2/effs" "$LOCAL/guide"
cp "$ROOT/vendor/bend/bend2/base.bend" "$LOCAL/bend2/base.bend"
cp -R "$ROOT/vendor/bend/bend2/effs/." "$LOCAL/bend2/effs/"
cp -R "$ROOT/vendor/bend/guide/." "$LOCAL/guide/"
(
  cd "$ROOT"
  bash scripts/run-bun.sh build --compile \
    --no-compile-autoload-bunfig --no-compile-autoload-dotenv \
    vendor/bend/bend2/main.ts --outfile="$LOCAL/bin/bend"
)
"$LOCAL/bin/bend" version
