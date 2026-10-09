#!/usr/bin/env bash
# Builds Yewclic and wraps the binary in a proper .app bundle.
# macOS only grants microphone / speech / screen-recording permissions to
# bundled apps with usage descriptions, so `swift run` alone is not enough.
#
# Usage:
#   scripts/build-app.sh            # release build, ad-hoc signed
#   SIGN_IDENTITY="Apple Development: you@example.com" scripts/build-app.sh
#
# Tip: ad-hoc signatures change on every build, which makes macOS forget the
# permissions you granted. Signing with a stable identity avoids that.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIGURATION="${CONFIGURATION:-release}"
APP_DIR="build/Yewclic.app"
# ".nosync" stops iCloud Drive from syncing build products.
SCRATCH_PATH=".build.nosync"

swift build -c "$CONFIGURATION" --scratch-path "$SCRATCH_PATH"
BIN_PATH="$(swift build -c "$CONFIGURATION" --scratch-path "$SCRATCH_PATH" --show-bin-path)/Yewclic"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/Yewclic"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"

codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP_DIR"
echo "Built $APP_DIR"
echo "Run it with: open $APP_DIR"
