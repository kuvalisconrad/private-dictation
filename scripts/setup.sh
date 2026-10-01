#!/bin/bash
# Contributor build setup only. Downloaded releases already include the engine.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ENV="${BUILD_ENV:-$ROOT/.build-env}"
PYTHON="${PYTHON:-}"
if [ -z "$PYTHON" ]; then PYTHON="$(bash "$ROOT/scripts/bootstrap-python.sh")"; fi
"$PYTHON" -c 'import sys; assert sys.version_info[:2] == (3, 12), "Builds currently require Python 3.12"'
if [ "$(uname -m)" != arm64 ]; then printf 'Apple Silicon is required.\n' >&2; exit 1; fi
mkdir -p "$ROOT/build/wheels"
if [ ! -x "$BUILD_ENV/bin/python" ]; then "$PYTHON" -m venv "$BUILD_ENV"; fi
"$BUILD_ENV/bin/python" -m pip install --disable-pip-version-check \
  -r "$ROOT/requirements.txt" -r "$ROOT/requirements-build.txt"
# Pip running on macOS26 normally selects the 26-only wheel. Pin the official
# 14-compatible binaries of the SAME MLX version to keep this release portable.
"$BUILD_ENV/bin/python" -m pip download --no-deps --only-binary=:all: \
  --platform macosx_14_0_arm64 --python-version 3.12 --implementation cp --abi cp312 \
  --dest "$ROOT/build/wheels" mlx==0.32.3 mlx-metal==0.32.3
"$BUILD_ENV/bin/python" -m pip install --no-deps --force-reinstall \
  "$ROOT/build/wheels/mlx-0.32.3-cp312-cp312-macosx_14_0_arm64.whl" \
  "$ROOT/build/wheels/mlx_metal-0.32.3-py3-none-macosx_14_0_arm64.whl"
printf '\nBuild dependencies ready. Run scripts/build.sh; installation is explicit (--install).\n'
