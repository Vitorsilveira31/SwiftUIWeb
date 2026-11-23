#!/usr/bin/env bash
set -euo pipefail

# Remove non-runtime metadata from a release Wasm module. This is intentionally
# separate from compilation: debug symbols are useful while developing, while
# production transfer should not pay for DWARF or the Wasm name section.
if [[ $# -lt 1 || $# -gt 2 || ! -f "$1" ]]; then
  echo "usage: $0 input.wasm [output.wasm]" >&2
  exit 64
fi

input="$1"
output="${2:-$1}"
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# How many times Binaryen runs its level (see below).
rounds="${WASM_OPT_ROUNDS:-2}"
[[ "$rounds" =~ ^[1-9]$ ]] || { echo "WASM_OPT_ROUNDS is 1 to 9, not $rounds" >&2; exit 64; }

# WASM_STRIP_CACHE_DIR names a folder that lives between builds. The result for a given input is the same every time
# (the Swift build is deterministic), so an unchanged module skips the strip and Binaryen (2 to 4 s on the Showcase) and
# gets the earlier result. The key covers the input bytes, every option below, this script and Binaryen's version.
# Printed on every path that leaves the module unoptimized, a cache hit included: a release shipped without Binaryen is a
# silent regression otherwise. It never fails the build (CI may not have Binaryen); WASM_OPT=0 says it is on purpose.
warn_without_binaryen() {
  [[ "${WASM_OPT:-1}" == "1" ]] && ! command -v wasm-opt >/dev/null 2>&1 || return 0
  echo "warning: wasm-opt (Binaryen) is not installed: this release app.wasm is NOT optimized, about a quarter larger raw and about 5% larger over the wire (Board: 1,726,911 B against 1,319,023 B with -Oz). Install it: brew install binaryen (or sudo apt-get install binaryen). WASM_OPT=0 builds without it on purpose." >&2
}

cache_file=""
if [[ -n "${WASM_STRIP_CACHE_DIR:-}" ]]; then
  hasher=(shasum -a 256); command -v shasum >/dev/null 2>&1 || hasher=(sha256sum)
  key="$({
    "${hasher[@]}" < "$input"
    "${hasher[@]}" < "${BASH_SOURCE[0]}"
    "${hasher[@]}" < "$root_dir/Tools/swiftuiweb-tools.mjs"
    printf '%s\n' "${WASM_OPT:-1}" "${WASM_OPT_LEVEL:-Oz}" "$rounds" "${WASM_OPT_ONE_CALLER_INLINE_MAX_SIZE:-}" "${WASM_KEEP_NAMES:-0}"
    if command -v wasm-opt >/dev/null 2>&1; then wasm-opt --version; fi
  } | "${hasher[@]}" | cut -d' ' -f1)"
  cache_file="$WASM_STRIP_CACHE_DIR/$key.wasm"
  if [[ -f "$cache_file" ]]; then
    cp "$cache_file" "$output"
    echo "strip-wasm-release: reused the earlier result for this module ($key)" >&2
    warn_without_binaryen
    if [[ "${WASM_SIZE_REPORT:-1}" == "1" && -f "$root_dir/Tools/analyze-wasm-size.js" ]] && command -v bun >/dev/null 2>&1; then
      bun "$root_dir/Tools/analyze-wasm-size.js" --wasm "$output" --output "$output.size.json" >/dev/null
    fi
    exit 0
  fi
fi

# This parser removes ONLY name/DWARF custom sections, on every host. The old
# path silently kept all debug info whenever llvm-objcopy was unavailable.
#
# WASM_KEEP_NAMES=1 keeps the `name` section through the same optimization instead: the module as it ships, with the
# names a size attribution reads (Tools/wasm-size-attribution.mjs). Never for a module that is served.
keep_names="${WASM_KEEP_NAMES:-0}"
if [[ "$keep_names" == 1 ]]; then
  [[ "$input" -ef "$output" ]] || cp "$input" "$output"
else
  "$root_dir/Tools/swiftuiweb-tools.sh" strip-wasm "$input" "$output"
fi

# Binaryen runs when `wasm-opt` is installed (WASM_OPT=0 turns it off). `-Oz`
# takes a large production app's release bundle from 6.7 MB to 4.5 MB raw, which is what the
# browser compiles, and it passed the studio E2E; transferred size shrinks less
# (brotli about 3%). Do not pass `--all-features`: it enables compact imports,
# which Chromium rejects.
#
# WASM_OPT_ONE_CALLER_INLINE_MAX_SIZE caps the size of a function Binaryen
# inlines into its only caller (by default it inlines every one of them). The
# Swift app sets it: a renderer reached once from `AnyView._render` was being
# inlined into it, and every nested view level then held that frame on a stack
# WebKit keeps small for a Worker's WebAssembly.
#
# The level runs WASM_OPT_ROUNDS times in one call (2 by default): what the first round inlines and removes leaves
# duplicates and constants that the second folds (Documentation/Performance/WASM_SIZE.md). WASM_OPT_ROUNDS=1 runs it once.
if [[ "${WASM_OPT:-1}" == "1" ]] && command -v wasm-opt >/dev/null 2>&1; then
  optimized="$output.opt.$$"
  level_flags=()
  for ((round = 0; round < rounds; round++)); do level_flags+=("-${WASM_OPT_LEVEL:-Oz}"); done
  inline_flags=()
  [[ -z "${WASM_OPT_ONE_CALLER_INLINE_MAX_SIZE:-}" ]] || inline_flags=(--one-caller-inline-max-function-size "$WASM_OPT_ONE_CALLER_INLINE_MAX_SIZE")
  # `-g` keeps the names (see WASM_KEEP_NAMES above).
  [[ "$keep_names" != 1 ]] || inline_flags+=(-g)
  wasm-opt "${level_flags[@]}" ${inline_flags[@]+"${inline_flags[@]}"} "$output" -o "$optimized"
  mv "$optimized" "$output"
else
  warn_without_binaryen
fi

if [[ -n "$cache_file" ]]; then
  mkdir -p "$WASM_STRIP_CACHE_DIR"
  cp "$output" "$cache_file.$$" && mv "$cache_file.$$" "$cache_file"
  # Keep the eight most recent results.
  find "$WASM_STRIP_CACHE_DIR" -maxdepth 1 -name '*.wasm' -print0 | xargs -0 ls -t 2>/dev/null | tail -n +9 | while IFS= read -r stale; do rm -f "$stale"; done
fi

if [[ "${WASM_SIZE_REPORT:-1}" == "1" && -f "$root_dir/Tools/analyze-wasm-size.js" ]] && command -v bun >/dev/null 2>&1; then
  bun "$root_dir/Tools/analyze-wasm-size.js" --wasm "$output" --output "$output.size.json" >/dev/null
fi
