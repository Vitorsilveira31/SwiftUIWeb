#!/usr/bin/env bash
set -euo pipefail

example_root="$(cd "$(dirname "$0")" && pwd)"
repository_root="$(cd "$example_root/../.." && pwd)"
cd "$example_root"

command -v bun >/dev/null 2>&1 || { echo "Bun is required." >&2; exit 2; }
bun install --frozen-lockfile
bun run build:blockly

SWIFTUIWEB_PACKAGE_ROOT="$example_root" \
SWIFTUIWEB_PRODUCT=BlocklyInteropApp \
SWIFTUIWEB_BUNDLE_ROOT="$example_root/.build/browser" \
BUILD_ONLY=1 \
  "$repository_root/Tools/run-browser-embedded.sh" BlocklyInteropApp

bun run scripts/copy-media.ts
port="${PORT:-8080}"
exec bun "$repository_root/Tools/bun-server.ts" "$example_root/.build/browser/BlocklyInteropApp" "$port"
