#!/usr/bin/env bash
set -euo pipefail

# Build only the internal, Foundation-free Embedded Swift Core compatibility
# slice. The full SwiftUIWebCore target is intentionally not used here: SwiftPM
# compiles that module as one unit and currently reports source blockers in
# optional reflection/weak/protocol-cast paths. The probe targets the Embedded
# Swift wasm32-unknown-none-wasm runtime directly and is therefore a reliable
# lower-bound measurement, not a claim of full Embedded browser support.
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

iterations="${EMBEDDED_CORE_ITERATIONS:-25}"
string_probe=false
for argument in "$@"; do
  case "$argument" in
    --release) ;;
    --string) string_probe=true ;;
    --debug)
      echo "The direct Embedded probe is intentionally release-only; use swiftc directly for debug diagnostics." >&2
      exit 64
      ;;
    *) echo "usage: $0 [--release] [--string]" >&2; exit 64 ;;
  esac
done

source "$root_dir/Tools/wasm-sdk-selection.sh"
swift_executable="$(swiftuiweb_resolve_swift_executable true "${WASM_SDK:-}" || true)"
if [[ -z "$swift_executable" ]]; then
  echo "Unable to locate a Swift compiler for Embedded Swift." >&2
  exit 2
fi
swiftc="${SWIFTUIWEB_SWIFTC:-$(dirname "$swift_executable")/swiftc}"
if [[ ! -x "$swiftc" ]]; then
  echo "Embedded Swift compiler not found: $swiftc" >&2
  exit 2
fi

llvm_bin="$(dirname "$swiftc")"
wasm_ld="${WASM_LD:-$llvm_bin/wasm-ld}"
if [[ ! -x "$wasm_ld" ]]; then
  echo "wasm-ld not found beside the selected Swift compiler: $wasm_ld" >&2
  exit 2
fi

build_dir="${EMBEDDED_CORE_BUILD_DIR:-$root_dir/.build/embedded-core}"
# `rm -rf` runs on this path, so it must be a folder under the repository's .build (no `..` that could leave it).
case "$build_dir" in
  "$root_dir/.build/"*) ;;
  *) echo "EMBEDDED_CORE_BUILD_DIR must be a folder under $root_dir/.build: $build_dir" >&2; exit 2 ;;
esac
case "$build_dir" in
  */..|*/../*) echo "EMBEDDED_CORE_BUILD_DIR must not contain '..': $build_dir" >&2; exit 2 ;;
esac
# No trailing slash (`rm -rf dir/` follows a link named dir), and not a link itself.
build_dir="${build_dir%/}"
while [ "${build_dir%/}" != "$build_dir" ]; do build_dir="${build_dir%/}"; done
if [ -L "$build_dir" ]; then echo "EMBEDDED_CORE_BUILD_DIR must not be a symbolic link: $build_dir" >&2; exit 2; fi
rm -rf "$build_dir"
mkdir -p "$build_dir/clang" "$build_dir/swift" "$build_dir/out"

source_files=("$root_dir"/Sources/SwiftUIWebEmbeddedCoreProbe/*.swift)
object="$build_dir/out/EmbeddedCoreProbe.o"
artifact="$build_dir/out/SwiftUIWebEmbeddedCore.wasm"

echo "Building Embedded Core probe (release, wasm32-unknown-none-wasm)"
swift_flags=(
  -target wasm32-unknown-none-wasm
  -enable-experimental-feature Embedded
  -Osize -wmo -parse-as-library
)
if [[ "$string_probe" == true ]]; then
  swift_flags+=(-D SWIFTUIWEB_EMBEDDED_STRING_PROBE)
fi
SWIFT_MODULECACHE_PATH="$build_dir/swift" \
CLANG_MODULE_CACHE_PATH="$build_dir/clang" \
  "$swiftc" "${swift_flags[@]}" \
    -emit-object "${source_files[@]}" -o "$object"

link_exports=(--export=embedded_core_start)
if [[ "$string_probe" == true ]]; then link_exports+=(--export=embedded_string_length); fi
"$wasm_ld" --no-entry "${link_exports[@]}" --gc-sections "$object" -o "$artifact"

# Remove debug/name metadata from the transfer artifact. Debug diagnostics can
# still be obtained from the object emitted by invoking the compiler directly.
SWIFTUIWEB_SWIFT="$swift_executable" WASM_SIZE_REPORT=0 \
  Tools/strip-wasm-release.sh "$artifact" "$artifact"

bun Tools/analyze-wasm-size.js --wasm "$artifact" --output "$artifact.size.json"
bun Tools/benchmark-embedded-core.js --wasm "$artifact" --iterations "$iterations" \
  --output "$artifact.startup.json"
echo "Embedded Core artifact: $artifact"
