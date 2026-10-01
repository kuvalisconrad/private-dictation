#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Private Dictation.app"
BUILD_PYTHON="${BUILD_PYTHON:-$ROOT/.build-env/bin/python}"
INSTALL=0
for ARG in "$@"; do
  case "$ARG" in
    --install) INSTALL=1 ;;
    --no-install) INSTALL=0 ;;
    *) printf 'Usage: scripts/build.sh [--install]\n' >&2; exit 2 ;;
  esac
done
if [ ! -x "$BUILD_PYTHON" ]; then
  printf 'Build environment missing. Run scripts/setup.sh first.\n' >&2
  exit 1
fi
mkdir -p "$BUILD"
export PYINSTALLER_CONFIG_DIR="$BUILD/pyinstaller-cache"
"$BUILD_PYTHON" "$ROOT/scripts/collect-notices.py"
"$BUILD_PYTHON" -m PyInstaller --noconfirm --clean \
  --distpath "$BUILD/engine-dist" --workpath "$BUILD/engine-work" "$ROOT/engine.spec"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
MACOSX_DEPLOYMENT_TARGET=14.0 xcrun swiftc -target arm64-apple-macos14.0 \
  -module-cache-path "$BUILD/module-cache" "$ROOT/scripts/generate-icon.swift" -framework AppKit -o "$BUILD/icon-renderer"
"$BUILD/icon-renderer" "$BUILD/PrivateDictation.iconset"
iconutil -c icns "$BUILD/PrivateDictation.iconset" -o "$APP/Contents/Resources/PrivateDictation.icns"
MACOSX_DEPLOYMENT_TARGET=14.0 xcrun clang -target arm64-apple-macos14.0 \
  -Wno-deprecated-declarations -c "$ROOT/Sources/Privacy.c" -o "$BUILD/Privacy.o"
MACOSX_DEPLOYMENT_TARGET=14.0 xcrun swiftc -target arm64-apple-macos14.0 \
  -swift-version 5 -O -import-objc-header "$ROOT/Sources/Privacy.h" \
  "$ROOT"/Sources/*.swift "$BUILD/Privacy.o" \
  -framework AppKit -framework AVFoundation -framework ApplicationServices -framework Carbon \
  -o "$APP/Contents/MacOS/LocalDictation"
if [ -d "$APP/Contents/Resources/Engine" ]; then
  rm -rf "$APP/Contents/Resources/Engine"
fi
ditto "$BUILD/engine-dist/Engine" "$APP/Contents/Resources/Engine"
cp "$ROOT/Sources/worker.py" "$ROOT/model.json" "$ROOT/model-manifest.json" \
  "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"
ditto "$ROOT/licenses" "$APP/Contents/Resources/licenses"
cp "$ROOT/Sources/Info.plist" "$APP/Contents/Info.plist"
if [ -n "${DEVELOPER_ID_IDENTITY:-}" ]; then
  "$BUILD_PYTHON" "$ROOT/scripts/sign-release.py" "$APP" "$DEVELOPER_ID_IDENTITY"
else
  codesign --force --deep --sign - --identifier local.mike.dictation "$APP"
fi
codesign --verify --deep --strict "$APP"
printf '\nBuilt: %s\n' "$APP"
if [ "$INSTALL" = 1 ]; then
  mkdir -p "$HOME/Applications"
  ditto "$APP" "$HOME/Applications/Private Dictation.app"
  printf 'Installed: %s/Applications/Private Dictation.app\n' "$HOME"
fi
