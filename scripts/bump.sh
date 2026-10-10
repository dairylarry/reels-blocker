#!/bin/bash
# Bump MARKETING_VERSION. One changelog entry = one version (see CLAUDE.md).
set -euo pipefail
cd "$(dirname "$0")/.."

NEW="${1:?usage: scripts/bump.sh <version>   e.g. scripts/bump.sh 1.1}"
PBX=Plainfeed.xcodeproj/project.pbxproj

CUR=$(grep -m1 -o 'MARKETING_VERSION = [^;]*' "$PBX" | sed 's/.*= //')
COUNT=$(grep -c 'MARKETING_VERSION' "$PBX")
[ "$COUNT" -eq 2 ] || { echo "expected 2 MARKETING_VERSION entries, found $COUNT"; exit 1; }

sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = $NEW;/" "$PBX"
echo "MARKETING_VERSION: $CUR -> $NEW"
echo "now add the v$NEW entry to docs/CHANGELOG.md"
