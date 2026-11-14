#!/usr/bin/env bash
# Apple SwiftUI frames of the extra fixtures CSS layout (Tools/css-layout-oracle.mjs) is checked against
# (Tests/LayoutConformance/apple-macos-css-extra.json; the conformance fixtures' frames come from run-apple.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/Tests/LayoutConformance/apple-macos-css-extra.json}"
mkdir -p "$(dirname "$OUT")" "$ROOT/.build/layout-conformance"
BIN="$ROOT/.build/layout-conformance/css-layout-oracle"
xcrun swiftc -parse-as-library "$ROOT/Tools/LayoutConformance/CssLayoutOracle.swift" -framework SwiftUI -framework AppKit -o "$BIN"
"$BIN" > "$OUT"
echo "Apple SwiftUI geometry (CSS layout fixtures): $OUT"
