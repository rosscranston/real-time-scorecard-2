#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  echo "Commit the intended source changes before packaging." >&2
  exit 1
fi
bash scripts/build-app.sh release
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
ARCH="$(lipo -archs 'dist/Live Scorecard 2.app/Contents/MacOS/LiveScorecard2')"
if [ "$ARCH" != "arm64" ]; then
  echo "This release recipe expects an Apple Silicon arm64 build; found $ARCH." >&2
  exit 1
fi
APP_ZIP="dist/LiveScorecard2-$VERSION-macos-arm64.zip"
SOURCE_ZIP="dist/LiveScorecard2-$VERSION-source.zip"
ditto -c -k --keepParent --norsrc "dist/Live Scorecard 2.app" "$APP_ZIP"
git archive --format=zip --prefix="RealTimeScorecard2-$VERSION/" -o "$SOURCE_ZIP" HEAD
python3 scripts/verify-release.py "$APP_ZIP" "$SOURCE_ZIP"
(cd dist && shasum -a 256 "$(basename "$APP_ZIP")" "$(basename "$SOURCE_ZIP")" > SHA256SUMS.txt)
git rev-parse HEAD > dist/SOURCE_COMMIT.txt
echo "Release archives and checksums are in dist/. This build is not notarized."
