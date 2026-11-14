#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${BUN_INSTALL:-$HOME/.bun}/bin:$PATH"

say(){ printf '%s\n' "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

say "SwiftUIWeb setup"
say "================"

# First show everything that is missing at once (read-only); the steps below install what they can.
bash "$ROOT/Tools/toolchain-report.sh" --quiet 2>&1 || say "(setup continues and installs what it can)"

# A remote install script runs unverified code, so it needs an explicit opt-in;
# without it the script stops and says what to install by hand.
remote_installer() {
  local url="$1"; shift
  if [[ "${SWIFTUIWEB_ALLOW_REMOTE_INSTALLERS:-0}" != "1" ]]; then
    say "ERROR: installing from $url runs a remote script. Install it yourself, or rerun with SWIFTUIWEB_ALLOW_REMOTE_INSTALLERS=1." >&2
    exit 2
  fi
  local script; script="$(mktemp)"
  curl --proto '=https' --tlsv1.2 -fsSL "$url" -o "$script"
  local status=0
  bash "$script" "$@" || status=$?
  rm -f "$script"
  return $status
}

# Bun: preferred browser/build tooling.
if ! have bun; then
  say "Bun not found. Installing..."
  if have brew; then
    brew install oven-sh/bun/bun
  elif have curl; then
    remote_installer https://bun.sh/install
    export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
    export PATH="$BUN_INSTALL/bin:$PATH"
  else
    say "ERROR: install Bun first (Homebrew or curl is required for automatic setup)." >&2; exit 2
  fi
fi
have bun || { say "ERROR: Bun was installed but is not available in PATH. Add $HOME/.bun/bin to PATH." >&2; exit 2; }
say "✓ Bun $(bun --version)"

# The canonical Embedded Wasm benchmark is deterministic and requires all
# distribution encoders; never silently omit a result.
for compressor in gzip brotli zstd; do
  if ! have "$compressor"; then
    say "ERROR: $compressor is required by make wasm-size. Install it (Homebrew: brew install $compressor) and rerun make setup." >&2
    exit 2
  fi
  say "✓ $compressor $($compressor --version | head -1)"
done

# Optional, and never a failure: a release build without Binaryen still works, but ships an unoptimized app.wasm
# (Tools/strip-wasm-release.sh warns about it on every release build). make doctor reports the same.
if have wasm-opt; then
  say "✓ wasm-opt $(wasm-opt --version | head -1)"
else
  say "WARNING: wasm-opt (Binaryen) is not installed. Release builds will ship an unoptimized app.wasm (about a quarter larger raw). Install it (Homebrew: brew install binaryen; apt: sudo apt-get install binaryen) and rerun make setup." >&2
fi

say "Installing project tooling..."
if [[ -f bun.lock ]]; then bun install --frozen-lockfile; else bun install; fi

# Swift + WASM SDK are repository requirements. Do not silently install a
# random toolchain: report exactly what the repository can resolve.
have swift || { say "ERROR: Swift is required. Install the repository's Swift 6.4 toolchain first." >&2; exit 2; }
say "✓ $(swift --version | head -1)"

source "$ROOT/Tools/wasm-sdk-selection.sh"
swift_bin="$(swiftuiweb_resolve_swift_executable true "${WASM_SDK:-}" || true)"
if [[ -z "$swift_bin" ]]; then
  say "ERROR: no Embedded-capable Swift/WASM compiler could be resolved." >&2
  say "Install the Swift 6.4 WebAssembly SDK used by this repository, then rerun make setup." >&2
  exit 2
fi
sdks="$($swift_bin sdk list 2>/dev/null || true)"
sdk="$(swiftuiweb_select_wasm_sdk "$sdks" true "${WASM_SDK:-}" 0 "$swift_bin" || true)"
[[ -n "$sdk" ]] || { say "ERROR: no Embedded-compatible WebAssembly SDK found." >&2; exit 2; }
say "✓ Embedded Swift/WASM SDK: $sdk"

# Prepare the local build directory without building the app. The first browser build also compiles the source lowerer
# (Tools/SwiftUIWebLowering, which fetches and builds swift-syntax once, about two minutes).
mkdir -p .build

say ""
say "Setup complete."
say "Run: make run"
