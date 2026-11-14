#!/usr/bin/env bash

# Shared Swift SDK discovery for the Embedded browser entry point. This
# file is sourced by the build scripts; it intentionally does not enable shell
# options so it can inherit the caller's error policy.

# Resolve a compiler which can actually consume the selected WebAssembly SDK.
# Swiftly's command shim is convenient interactively, but it may block while
# acquiring its toolchain lock (and it can hide a compiler/SDK mismatch). When
# the Swiftly environment exposes its toolchain directory, invoke the matching
# executable directly instead. The caller can always override this with
# SWIFTUIWEB_SWIFT=/absolute/path/to/swift.
swiftuiweb_resolve_swift_executable() {
  local embedded="$1"
  local pinned_sdk="${2:-}"
  local candidate
  local candidate_sdks
  local candidate_sdk
  local toolchains_dir="${SWIFTLY_TOOLCHAINS_DIR:-}"

  if [[ -n "${SWIFTUIWEB_SWIFT:-}" ]]; then
    printf '%s\n' "$SWIFTUIWEB_SWIFT"
    return 0
  fi

  if [[ -n "$toolchains_dir" && -d "$toolchains_dir" ]]; then
    for candidate in "$toolchains_dir"/swift-*.xctoolchain/usr/bin/swift; do
      [[ -x "$candidate" ]] || continue
      candidate_sdks="$("$candidate" sdk list 2>/dev/null || true)"
      [[ -n "$candidate_sdks" ]] || continue
      if [[ -n "$pinned_sdk" ]]; then
        if ! printf '%s\n' "$candidate_sdks" | grep -F -q -- "$pinned_sdk"; then
          continue
        fi
        candidate_sdk="$pinned_sdk"
      else
        candidate_sdk="$(swiftuiweb_wasm_sdk_candidates "$candidate_sdks" "$embedded" | while IFS= read -r sdk_id; do
          if swiftuiweb_sdk_matches_swift_toolchain "$sdk_id" "$candidate"; then
            printf '%s\n' "$sdk_id"
            break
          fi
        done)"
      fi
      [[ -n "$candidate_sdk" ]] || continue
      swiftuiweb_sdk_matches_swift_toolchain "$candidate_sdk" "$candidate" || continue
      printf '%s\n' "$candidate"
      return 0
    done
  fi

  # A normal `swift` is the correct fallback when no managed toolchain is
  # configured. Do not invoke `swiftly run swift` implicitly: that proxy can
  # wait indefinitely in locked-down CI and gives no useful error to callers.
  command -v swift 2>/dev/null || return 1
}

swiftuiweb_wasm_sdk_candidates() {
  local sdk_list="$1"
  local embedded="$2"

  printf '%s\n' "$sdk_list" | awk -v embedded="$embedded" '
    {
      name = tolower($0)
      if (name !~ /wasm/) next
      has_embedded = name ~ /embedded/
      if ((embedded == "true" && has_embedded) || (embedded != "true" && !has_embedded)) print $0
    }
  '
}

# Swift SDK bundles are installed outside individual toolchains, so every
# compiler can list them even when their runtime libraries were built by a
# different compiler. Derive the toolchain identity from the selected
# compiler path where possible, or from the version string for release builds.
swiftuiweb_swift_toolchain_id() {
  local swift_bin="$1"
  local toolchain_root
  local toolchain_name
  local version_line
  local release_version

  toolchain_root="$(cd "$(dirname "$swift_bin")/../.." 2>/dev/null && pwd -P)" || true
  toolchain_name="${toolchain_root##*/}"
  toolchain_name="${toolchain_name%.xctoolchain}"
  if [[ "$toolchain_name" == swift-* && "$toolchain_root" == *.xctoolchain ]]; then
    printf '%s\n' "$toolchain_name"
    return 0
  fi

  version_line="$("$swift_bin" --version 2>/dev/null | head -n 1 || true)"
  if [[ "$version_line" =~ \(swift-([0-9]+\.[0-9]+(\.[0-9]+)?)-RELEASE\) ]]; then
    release_version="${BASH_REMATCH[1]}"
    [[ "$release_version" == *.*.* ]] || release_version="${release_version}.0"
    printf 'swift-%s-RELEASE\n' "$release_version"
    return 0
  fi

  return 1
}

swiftuiweb_wasm_sdk_toolchain_id() {
  case "$1" in
    *_wasm-embedded) printf '%s\n' "${1%_wasm-embedded}" ;;
    *_wasm) printf '%s\n' "${1%_wasm}" ;;
    *) return 1 ;;
  esac
}

swiftuiweb_sdk_matches_swift_toolchain() {
  local sdk_id="$1"
  local swift_bin="$2"
  local sdk_toolchain_id
  local swift_toolchain_id

  sdk_toolchain_id="$(swiftuiweb_wasm_sdk_toolchain_id "$sdk_id")" || return 1
  swift_toolchain_id="$(swiftuiweb_swift_toolchain_id "$swift_bin")" || return 1
  [[ "$sdk_toolchain_id" == "$swift_toolchain_id" ]]
}

swiftuiweb_wasm_sdk_supports_c_target() {
  local sdk_id="$1"
  shift
  local probe_root
  probe_root="$(mktemp -d "${TMPDIR:-/tmp}/swiftuiweb-wasm-sdk.XXXXXX")" || return 1

  # SwiftPM treats a target containing C sources as a C target and expects its
  # conventional public-header directory to exist, even when the probe only
  # needs a private translation unit.
  mkdir -p "$probe_root/Sources/WasmCSDKProbe/include"
  cat > "$probe_root/Package.swift" <<'EOF'
// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "WasmCSDKProbe",
  targets: [
    .target(name: "WasmCSDKProbe", path: "Sources/WasmCSDKProbe")
  ]
)
EOF
  cat > "$probe_root/Sources/WasmCSDKProbe/probe.c" <<'EOF'
#include <stdlib.h>

int swiftuiweb_wasm_sdk_probe(void) {
  return EXIT_SUCCESS;
}
EOF

  # Building a C target (rather than only asking `swift sdk list`) verifies
  # both the wasm32 target triple and the SDK's C standard-library headers.
  # Use an isolated scratch path so the probe does not mutate this package's
  # dependency graph or reuse stale target metadata.
  local -a probe_args=(build --disable-sandbox
    --package-path "$probe_root"
    --scratch-path "$probe_root/.build"
    --swift-sdk "$sdk_id"
    --target WasmCSDKProbe)
  if [[ "${SWIFTUIWEB_SDK_PROBE_VERBOSE:-0}" == "1" ]]; then
    if "$@" "${probe_args[@]}"; then
      rm -rf "$probe_root"
      return 0
    fi
  elif "$@" "${probe_args[@]}" >/dev/null 2>&1; then
    rm -rf "$probe_root"
    return 0
  fi

  rm -rf "$probe_root"
  return 1
}

swiftuiweb_select_wasm_sdk() {
  local sdk_list="$1"
  local embedded="$2"
  local pinned_sdk="$3"
  local probe_c_target="$4"
  shift 4
  local -a swift_command=("$@")
  local candidates
  local candidate
  local swift_bin="${swift_command[0]}"
  local swift_toolchain_id

  swift_toolchain_id="$(swiftuiweb_swift_toolchain_id "$swift_bin")" || true

  if [[ -n "$pinned_sdk" ]]; then
    candidates="$pinned_sdk"
  else
    candidates="$(swiftuiweb_wasm_sdk_candidates "$sdk_list" "$embedded")"
  fi

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    swiftuiweb_sdk_matches_swift_toolchain "$candidate" "$swift_bin" || continue
    if [[ "$probe_c_target" != "1" ]] || swiftuiweb_wasm_sdk_supports_c_target "$candidate" "${swift_command[@]}"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done <<< "$candidates"

  if [[ -n "$pinned_sdk" ]]; then
    echo "Pinned WebAssembly SDK '$pinned_sdk' does not match the selected Swift compiler (${swift_toolchain_id:-unknown toolchain})." >&2
  else
    local kind="Embedded WebAssembly SDK"; [[ "$embedded" == true ]] || kind="regular WebAssembly SDK (SWIFTUIWEB_DEV_PROFILE=fast)"
    echo "No $kind matching the selected Swift compiler (${swift_toolchain_id:-unknown toolchain}) is installed." >&2
  fi
  echo "Install the SDK built for this exact toolchain, or set SWIFTUIWEB_SWIFT and WASM_SDK to a matching pair." >&2

  return 1
}
