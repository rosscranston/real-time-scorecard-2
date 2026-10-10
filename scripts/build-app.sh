#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
CONFIGURATION="${1:-release}"
case "$CONFIGURATION" in release|debug) ;; *) echo "Use release or debug" >&2; exit 2 ;; esac
export CLANG_MODULE_CACHE_PATH=/tmp/scorecard2-clang
export SWIFT_MODULECACHE_PATH=/tmp/scorecard2-swift
swift build --disable-sandbox -c "$CONFIGURATION" --product LiveScorecard2
BIN_DIR="$(swift build --disable-sandbox -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$PROJECT_DIR/dist/Live Scorecard 2.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/LiveScorecard2" "$APP_DIR/Contents/MacOS/LiveScorecard2"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
ditto "$BIN_DIR/RealTimeScorecard2_ScorecardApp.bundle" "$APP_DIR/Contents/Resources/RealTimeScorecard2_ScorecardApp.bundle"
plutil -lint "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign "${SIGNING_IDENTITY:--}" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "Built $APP_DIR"
if [ -z "${SIGNING_IDENTITY:-}" ]; then
  echo "Ad-hoc development build; not Developer ID signed or notarized."
fi
