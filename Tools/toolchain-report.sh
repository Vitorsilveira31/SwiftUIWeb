#!/usr/bin/env bash
# Lists, in one report, every tool the Embedded browser build needs and does not find, each with the command that
# installs it. Without this the build stops at the first missing tool, the developer fixes it, and the next one stops
# the build again.
#
# It is plain bash on purpose: it has to run when bun is exactly what is missing.
#
# Command:  Tools/toolchain-report.sh [--quiet]       (make doctor)   exit 0 when the build can start, 1 otherwise
# Sourced:  swiftuiweb_toolchain_report               (run-browser-embedded.sh calls it before it builds anything)
# The command prints what it found; the sourced call is quiet unless something required is missing (pass --verbose
# to get the full list there too).
# SWIFTUIWEB_SKIP_TOOLCHAIN_REPORT=1 turns the check off.
#
# Reads only: it never installs, downloads or edits anything. Finding a tool is not a successful build.

swiftuiweb_toolchain_report() {
  local verbose=0
  [[ "${1:-}" != "--verbose" ]] || verbose=1
  [[ "${SWIFTUIWEB_SKIP_TOOLCHAIN_REPORT:-0}" != 1 ]] || return 0
  local root report="" missing=0 optional_missing=0
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

  found()   { report="${report}  ok        $1  $2"$'\n'; }
  absent()  { missing=$((missing + 1)); report="${report}  MISSING   $1  $2"$'\n'"            fix: $3"$'\n'; }
  absent_optional() { optional_missing=$((optional_missing + 1)); report="${report}  optional  $1  $2"$'\n'"            fix: $3"$'\n'; }

  local bun_hint="brew install oven-sh/bun/bun   (or: curl -fsSL https://bun.sh/install | bash)"

  # --- Swift: a 6.4+ compiler and the Embedded WebAssembly SDK built for that exact toolchain.
  declare -F swiftuiweb_resolve_swift_executable >/dev/null 2>&1 || source "$root/Tools/wasm-sdk-selection.sh"
  # The development profile `fast` (SWIFTUIWEB_DEV_PROFILE=fast) builds with the regular WebAssembly SDK instead.
  local swift_bin swift_version swift_major swift_minor embedded_sdk=true sdk_kind="Embedded WebAssembly SDK"
  [[ "${SWIFTUIWEB_DEV_PROFILE:-embedded}" != fast ]] || { embedded_sdk=false; sdk_kind="WebAssembly SDK (the regular one, for SWIFTUIWEB_DEV_PROFILE=fast)"; }
  swift_bin="$(swiftuiweb_resolve_swift_executable "$embedded_sdk" "${WASM_SDK:-}" 2>/dev/null || true)"
  if [[ -z "$swift_bin" ]]; then
    absent "swift      " "no Swift compiler on PATH (SWIFTUIWEB_SWIFT is unset)" \
      "install a Swift 6.4+ toolchain (https://www.swift.org/install/ or swiftly), then rerun"
  else
    swift_version="$("$swift_bin" --version 2>/dev/null | head -n 1 || true)"
    if [[ "$swift_version" =~ [Ss]wift\ version\ ([0-9]+)\.([0-9]+) ]]; then
      swift_major="${BASH_REMATCH[1]}"; swift_minor="${BASH_REMATCH[2]}"
      if (( swift_major > 6 || (swift_major == 6 && swift_minor >= 4) )); then
        found "swift      " "$swift_version ($swift_bin)"
      else
        absent "swift      " "$swift_version is older than 6.4" \
          "install a Swift 6.4+ toolchain, or point SWIFTUIWEB_SWIFT at one"
      fi
    else
      absent "swift      " "$swift_bin did not report a version ('$swift_version')" \
        "check that $swift_bin runs; set SWIFTUIWEB_SWIFT to a working Swift 6.4+ compiler"
    fi
    local sdks sdk
    sdks="$("$swift_bin" sdk list 2>/dev/null || true)"
    sdk="$(swiftuiweb_select_wasm_sdk "$sdks" "$embedded_sdk" "${WASM_SDK:-}" 0 "$swift_bin" 2>/dev/null || true)"
    if [[ -n "$sdk" ]]; then
      found "wasm sdk   " "$sdk"
      # The development loop builds the profile `fast` with the regular SDK of the same toolchain; without it the loop
      # builds the Embedded profile, which is slower to save in.
      if [[ "$embedded_sdk" == true ]]; then
        local regular_sdk
        regular_sdk="$(swiftuiweb_select_wasm_sdk "$sdks" false "" 0 "$swift_bin" 2>/dev/null || true)"
        if [[ -n "$regular_sdk" ]]; then found "wasm sdk   " "$regular_sdk (the development loop's profile fast)"
        else absent_optional "wasm sdk   " "the regular WebAssembly SDK: without it the development loop builds the Embedded profile, with slower saves" "swift sdk install <the WebAssembly SDK for this exact toolchain>; the bundle that holds the Embedded SDK holds it too"; fi
      fi
    else
      absent "wasm sdk   " "no $sdk_kind matches this toolchain ($(swiftuiweb_swift_toolchain_id "$swift_bin" 2>/dev/null || echo "unknown toolchain"))" \
        "swift sdk install <the $sdk_kind for this exact toolchain, from https://www.swift.org/install/>, or set SWIFTUIWEB_SWIFT and WASM_SDK to a matching pair"
    fi
  fi

  # --- JavaScript runtime.
  if command -v bun >/dev/null 2>&1; then found "bun        " "$(bun --version 2>/dev/null) ($(command -v bun))"
  else absent "bun        " "runs the host scripts, the dev server and the tests" "$bun_hint"; fi

  # --- Optional.
  if command -v wasm-opt >/dev/null 2>&1; then found "wasm-opt   " "Binaryen $(wasm-opt --version 2>/dev/null | head -n 1)"
  else absent_optional "wasm-opt   " "Binaryen shrinks release app.wasm (about a third); debug builds do not need it" "brew install binaryen   (or: sudo apt-get install binaryen)"; fi

  if (( missing > 0 )); then
    {
      echo "SwiftUIWeb cannot build yet: $missing required tool(s) are missing."
      printf '%s' "$report"
      echo "Install them, then run the same command again. \`make doctor\` shows this report without building."
    } >&2
    return 1
  fi
  if (( verbose )); then
    echo "SwiftUIWeb toolchain: everything required is installed."
    printf '%s' "$report"
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -u
  swiftuiweb_toolchain_report "${1:---verbose}"
fi
