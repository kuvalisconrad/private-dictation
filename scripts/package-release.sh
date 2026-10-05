#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${PRIVATE_DICTATION_APP:-$ROOT/build/Products.noindex/Private Dictation.app}"
RELEASE="$ROOT/release"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
mkdir -p "$RELEASE"
codesign --verify --deep --strict "$APP"
ZIP="$RELEASE/Private-Dictation-$VERSION-apple-silicon.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
if [ "${1:-}" = --notarize ]; then
  if [ -z "${NOTARY_PROFILE:-}" ] || [ -z "${DEVELOPER_ID_IDENTITY:-}" ]; then
    printf 'Set NOTARY_PROFILE and DEVELOPER_ID_IDENTITY before requesting notarization.\n' >&2; exit 1
  fi
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
elif [ -n "${1:-}" ]; then
  printf 'Usage: scripts/package-release.sh [--notarize]\n' >&2; exit 2
fi
pushd "$RELEASE" >/dev/null
shasum -a 256 "$(basename "$ZIP")" > SHA256SUMS.txt
popd >/dev/null
printf 'Release archive: %s\n' "$ZIP"
