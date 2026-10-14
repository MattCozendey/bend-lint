#!/bin/sh
set -eu

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) system=x86_64-linux ;;
  Linux-aarch64|Linux-arm64) system=aarch64-linux ;;
  Darwin-arm64) system=aarch64-darwin ;;
  *) echo 'Supported: Linux x86-64/ARM64 and Apple Silicon macOS.' >&2; exit 1 ;;
esac
variant=shareware
if [ "${1-}" = --freedoom ]; then
  variant=freedoom
  shift
fi
release=${BENDOOM_RELEASE:-latest}
base=https://github.com/eliesgalvira/bendoom/releases
if [ "$release" = latest ]; then
  base=$base/latest/download
else
  base=$base/download/$release
fi
asset=bendoom-$variant-$system.tar.gz
scratch=$(mktemp -d)
unpack=
cleanup() {
  [ ! -d "$scratch" ] || rm -r -- "$scratch"
  [ ! -d "$unpack" ] ||
    [ "$(readlink "${dest-}" 2>/dev/null)" = "$(basename "$unpack")" ] ||
    rm -r -- "$unpack"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
curl -fsSL --retry 3 "$base/SHA256SUMS" -o "$scratch/SHA256SUMS"
digest=$(awk -v file="$asset" '$2 == file { print $1 }' "$scratch/SHA256SUMS")
case "$digest" in ''|*[!0-9a-f]*) echo 'Missing release checksum.' >&2; exit 1 ;; esac
[ "${#digest}" -eq 64 ] || exit 1
cache=${XDG_CACHE_HOME:-$HOME/.cache}/bendoom
dest=$cache/$digest
if [ ! -x "$dest/bendoom" ]; then
  echo "Downloading $asset" >&2
  curl -fL --retry 3 "$base/$asset" -o "$scratch/$asset"
  if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$scratch/$asset")
  else
    actual=$(shasum -a 256 "$scratch/$asset")
  fi
  [ "${actual%% *}" = "$digest" ] || { echo 'Release checksum mismatch.' >&2; exit 1; }
  mkdir -p "$cache"
  unpack=$(mktemp -d "$cache/.bundle.XXXXXX")
  tar -xzf "$scratch/$asset" -C "$unpack"
  test -x "$unpack/bendoom"
  ln -sn "$(basename "$unpack")" "$dest" 2>/dev/null || test -x "$dest/bendoom"
fi
cleanup
trap - EXIT HUP INT TERM
exec "$dest/bendoom" "$@"
