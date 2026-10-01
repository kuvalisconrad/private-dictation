#!/bin/bash
# Fixed current Python runtime for reproducible release builds; no system changes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="$ROOT/build/python-standalone"
ARCHIVE="$ROOT/build/cpython-3.12.14-20260929-macos-arm64.tar.gz"
EXPECTED=de6b8f94fa765639b423ea353ab340669704c7186f96ee3cab389dcfde770c3c
mkdir -p "$ROOT/build" "$BASE"
if [ ! -f "$ARCHIVE" ]; then
  curl --fail --location --retry 3 \
    'https://github.com/astral-sh/python-build-standalone/releases/download/20260929/cpython-3.12.14%2B20260929-aarch64-apple-darwin-install_only.tar.gz' \
    -o "$ARCHIVE.partial" >&2
  mv "$ARCHIVE.partial" "$ARCHIVE"
fi
ACTUAL="$(shasum -a 256 "$ARCHIVE" | cut -d ' ' -f 1)"
if [ "$ACTUAL" != "$EXPECTED" ]; then
  printf 'Python archive checksum mismatch; remove it and retry.\n' >&2; exit 1
fi
if [ ! -x "$BASE/python/bin/python3.12" ]; then
  tar -xzf "$ARCHIVE" -C "$BASE"
fi
printf '%s\n' "$BASE/python/bin/python3.12"
