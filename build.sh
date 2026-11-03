#!/bin/zsh
# Builds Notch and assembles build/Notch.app, ad-hoc signed. Local use only.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Notch"

APP=build/Notch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Notch"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"
codesign --verify --verbose "$APP"
echo "Built $APP"
