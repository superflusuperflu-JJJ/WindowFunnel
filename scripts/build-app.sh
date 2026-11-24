#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
SIGNER="${WINDOW_FUNNEL_SIGNING_IDENTITY:--}"
if [[ "$SIGNER" != "-" ]]; then
    # Check the requested identity before replacing an installed executable.
    PROBE_DIR="$(mktemp -d)"
    trap 'rm -rf "$PROBE_DIR"' EXIT
    cp /usr/bin/true "$PROBE_DIR/signing-check"
    codesign --force --sign "$SIGNER" "$PROBE_DIR/signing-check"
    rm -rf "$PROBE_DIR"
    trap - EXIT
fi
swift build -c release --product WindowFunnel
BINARY_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="${WINDOW_FUNNEL_OUTPUT_DIR:-$PROJECT_DIR/dist}/WindowFunnel.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
# Replace the executable with a new inode; never overwrite signed executable pages in place.
TEMP_EXECUTABLE="$(mktemp "$APP_DIR/Contents/MacOS/.WindowFunnel.XXXXXX")"
trap 'rm -f "$TEMP_EXECUTABLE"' EXIT
cp "$BINARY_DIR/WindowFunnel" "$TEMP_EXECUTABLE"
chmod 755 "$TEMP_EXECUTABLE"
mv -f "$TEMP_EXECUTABLE" "$APP_DIR/Contents/MacOS/WindowFunnel"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --sign "$SIGNER" --identifier local.windowfunnel.spike "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
printf 'Built: %s\n' "$APP_DIR"
