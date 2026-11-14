#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/.build/layout-conformance/apple.json}"
mkdir -p "$(dirname "$OUT")" "$ROOT/.build/layout-conformance"
BIN="$ROOT/.build/layout-conformance/apple-oracle"
xcrun swiftc -parse-as-library "$ROOT/Tools/LayoutConformance/AppleOracle.swift" -framework SwiftUI -framework AppKit -o "$BIN"
"$BIN" > "$OUT"
echo "Apple SwiftUI geometry: $OUT"
