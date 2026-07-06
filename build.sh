#!/bin/bash
# Builds BetterCheatsheet and assembles it into a double-clickable .app bundle.
# Usage: ./build.sh [--release]
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="debug"
if [[ "${1:-}" == "--release" ]]; then
    CONFIG="release"
fi

if [[ "$CONFIG" == "release" ]]; then
    swift build -c release
    BIN_PATH=$(swift build -c release --show-bin-path)
else
    swift build
    BIN_PATH=$(swift build --show-bin-path)
fi
APP_NAME="BetterCheatsheet.app"
APP_DIR="$BIN_PATH/$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH/BetterCheatsheet" "$APP_DIR/Contents/MacOS/BetterCheatsheet"
cp "Info.plist" "$APP_DIR/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP_DIR"

echo "Built: $APP_DIR"
