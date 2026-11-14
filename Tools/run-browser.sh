#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# SwiftUIWeb has one browser runtime: Embedded Swift + BrowserIO.
exec bash "$ROOT/Tools/run-browser-embedded.sh" "$@"
