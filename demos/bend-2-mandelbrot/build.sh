#!/bin/zsh
set -eu
cd "${0:A:h}"
command -v bend >/dev/null
bend --version
bend PROOF.bend
mkdir -p Mandelbrot.app/Contents/MacOS Mandelbrot.app/Contents/Resources
cp camera.py Mandelbrot.app/Contents/Resources/camera.py
python3 - <<'PY'
import json
from pathlib import Path
Path("worker-source.c").write_text("static const char* PRECISION_SOURCE = "+json.dumps(Path("precision.metal").read_text())+";\n"+Path("worker.c").read_text())
PY
bend main.bend -o Mandelbrot.app/Contents/MacOS/worker
clang -O2 -fobjc-arc -fblocks host.m -framework AppKit -framework QuartzCore -o Mandelbrot.app/Contents/MacOS/mandelbrot
