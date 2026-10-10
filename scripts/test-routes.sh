#!/bin/bash
# Route-rule regression test. Compiles Rules.swift together with the cases in
# tests/RouteRules.swift and runs them. No Xcode test target needed.
#
# Rebuild tests/RouteRules.swift from source whenever Rules.swift changes:
#   { echo 'import Foundation'; sed '1d' Plainfeed/Blocking/Rules.swift; \
#     sed -n '/^func u(/,$p' tests/RouteRules.swift; } > /tmp/t.swift
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=$(mktemp -d)
{ echo 'import Foundation'
  sed '1d' Plainfeed/Blocking/Rules.swift
  sed -n '/^func u(/,$p' tests/RouteRules.swift
} > "$OUT/t.swift"

swiftc -O "$OUT/t.swift" -o "$OUT/t"
"$OUT/t"
