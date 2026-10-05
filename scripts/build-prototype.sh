#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/Prototype.noindex"
APP="$BUILD/Private Dictation.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun clang -target arm64-apple-macos14.0 -Wno-deprecated-declarations \
  -c "$ROOT/Sources/Privacy.c" -o "$BUILD/Privacy.o"
xcrun swiftc -target arm64-apple-macos14.0 -swift-version 5 -O \
  -import-objc-header "$ROOT/Sources/Privacy.h" \
  "$ROOT/Sources/ModifierShortcut.swift" "$ROOT/Sources/RecordingOutputMute.swift" \
  "$ROOT/Prototype/main.swift" "$BUILD/Privacy.o" \
  -framework AppKit -framework AVFoundation -framework ApplicationServices -framework CoreAudio \
  -o "$APP/Contents/MacOS/LocalDictation"
cp "$ROOT/Prototype/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Prototype/worker.py" "$ROOT/model.json" "$ROOT/LICENSE" "$APP/Contents/Resources/"
ICON="/Applications/Private Dictation.app/Contents/Resources/PrivateDictation.icns"
if [ -f "$ICON" ]; then cp "$ICON" "$APP/Contents/Resources/PrivateDictation.icns"; fi
python3 "$ROOT/scripts/sign-local.py" "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built personal prototype: %s\n' "$APP"
# This is a personal build using the original external Python runtime and
# temporary clipboard paste/restore. It is not the portable commercial app.
