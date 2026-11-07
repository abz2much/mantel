#!/bin/zsh
# Builds Notch and assembles build/Notch.app, ad-hoc signed.
# Optional, used by the release workflow:
#   NOTCH_UNIVERSAL=1      build for both Apple Silicon and Intel
#   NOTCH_VERSION=1.2.3    version shown in Finder and About
#   NOTCH_BUILD=42         build number
#   NOTCH_SIGN_IDENTITY    certificate to sign with (default "-": ad-hoc, for local builds)
#   NOTCH_KEYCHAIN         keychain holding that certificate
set -euo pipefail
cd "$(dirname "$0")"

ARCHS=()
if [[ "${NOTCH_UNIVERSAL:-}" == 1 ]]; then ARCHS=(--arch arm64 --arch x86_64); fi
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Notch"

APP=build/Notch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Notch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${NOTCH_VERSION:-}" ]]; then
  plutil -replace CFBundleShortVersionString -string "$NOTCH_VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${NOTCH_BUILD:-}" ]]; then
  plutil -replace CFBundleVersion -string "$NOTCH_BUILD" "$APP/Contents/Info.plist"
fi

SIGN_ARGS=(--force --sign "${NOTCH_SIGN_IDENTITY:--}")
if [[ -n "${NOTCH_KEYCHAIN:-}" ]]; then SIGN_ARGS+=(--keychain "$NOTCH_KEYCHAIN"); fi
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --verbose "$APP"
echo "Built $APP"
