#!/usr/bin/env bash
# Runs a subcommand of Tools/swiftuiweb-tools.mjs: strip-wasm, apply-translations, feature-matrix, browser-io-protocol.
set -euo pipefail
export PATH="${BUN_INSTALL:-$HOME/.bun}/bin:$PATH"
exec bun "$(dirname "${BASH_SOURCE[0]}")/swiftuiweb-tools.mjs" "$@"
