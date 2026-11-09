#!/bin/zsh
# Builds Mantel and assembles build/Mantel.app, ad-hoc signed.
# Optional, used by the release workflow:
#   MANTEL_UNIVERSAL=1      build for both Apple Silicon and Intel
#   MANTEL_VERSION=1.2.3    version shown in Finder and About
#   MANTEL_BUILD=42         build number
#   MANTEL_SIGN_IDENTITY    certificate to sign with (default "-": ad-hoc, for local builds)
#   MANTEL_KEYCHAIN         keychain holding that certificate
set -euo pipefail
cd "$(dirname "$0")"

ARCHS=()
if [[ "${MANTEL_UNIVERSAL:-}" == 1 ]]; then ARCHS=(--arch arm64 --arch x86_64); fi
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Mantel"

APP=build/Mantel.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Mantel"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "${MANTEL_VERSION:-}" ]]; then
  plutil -replace CFBundleShortVersionString -string "$MANTEL_VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${MANTEL_BUILD:-}" ]]; then
  plutil -replace CFBundleVersion -string "$MANTEL_BUILD" "$APP/Contents/Info.plist"
fi

SIGN_ARGS=(--force --sign "${MANTEL_SIGN_IDENTITY:--}")
if [[ -n "${MANTEL_KEYCHAIN:-}" ]]; then SIGN_ARGS+=(--keychain "$MANTEL_KEYCHAIN"); fi
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --verbose "$APP"
echo "Built $APP"
