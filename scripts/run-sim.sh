#!/bin/bash
# Build, install and launch on the simulator.
#
# SYMROOT is pinned so output always lands in ./build. Without it, xcodebuild
# -scheme writes to DerivedData while -target writes to ./build, which makes it
# very easy to install a stale binary and "verify" a change that was never
# installed. Don't remove the pin.
set -euo pipefail
cd "$(dirname "$0")/.."

DEV="${SIM_UDID:-1C200CE7-7173-49B3-AFA5-A315FE80B892}"
APP="build/Debug-iphonesimulator/Plainfeed.app"

xcodebuild -project Plainfeed.xcodeproj -scheme Plainfeed \
  -sdk iphonesimulator -configuration Debug \
  SYMROOT="$PWD/build" CODE_SIGNING_ALLOWED=NO build \
  2>&1 | grep -E '^\*\*|error:' || true

[ -d "$APP" ] || { echo "no app at $APP"; exit 1; }
echo "built: $(stat -f '%Sm' "$APP/Plainfeed")"

xcrun simctl boot "$DEV" 2>/dev/null || true
xcrun simctl terminate "$DEV" com.barryyang.plainfeed 2>/dev/null || true
xcrun simctl install "$DEV" "$APP"
xcrun simctl launch "$DEV" com.barryyang.plainfeed
