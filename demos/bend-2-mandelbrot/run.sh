#!/bin/zsh
set -eu
cd "${0:A:h}"
if [[ ! -x Mandelbrot.app/Contents/MacOS/worker || ! -x Mandelbrot.app/Contents/MacOS/mandelbrot ]]; then ./build.sh; fi
exec ./Mandelbrot.app/Contents/MacOS/mandelbrot "$@"
