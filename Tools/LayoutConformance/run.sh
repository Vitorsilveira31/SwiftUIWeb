#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
OUT="$ROOT/.build/layout-conformance"; mkdir -p "$OUT"
Tools/LayoutConformance/run-apple.sh "$OUT/apple.json"
BUILD_ONLY=1 CONFIGURATION="${SUITE_CONFIGURATION:-release}" Tools/run-browser.sh conformance
BUNDLE="$ROOT/.build/browser/LayoutConformanceApp"
PORT="${CONFORMANCE_PORT:-8099}"
bun Tools/bun-server.ts "$BUNDLE" "$PORT" >"$OUT/server.log" 2>&1 & SERVER=$!
trap 'kill "$SERVER" >/dev/null 2>&1 || true' EXIT
for _ in {1..50}; do curl -fsS "http://127.0.0.1:$PORT/" >/dev/null 2>&1 && break; sleep .1; done
bun Tools/LayoutConformance/capture-web.mjs --url "http://127.0.0.1:$PORT/" --output "$OUT/web.json"
bun Tools/LayoutConformance/compare.mjs --apple "$OUT/apple.json" --web "$OUT/web.json" --fixtures Tools/LayoutConformance/fixtures.json --report "$OUT/report.md"
echo "Conformance report: $OUT/report.md"
