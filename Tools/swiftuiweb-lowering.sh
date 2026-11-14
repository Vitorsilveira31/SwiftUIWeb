#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Release by default: the lowerer runs on every browser build and a release binary lowers several times faster. Use dev
# while editing the lowerer itself (its incremental rebuild is shorter, but it lowers slowly).
PROFILE="${SWIFTUIWEB_LOWERING_PROFILE:-release}"
case "$PROFILE" in
  dev) CONFIGURATION=debug ;;
  release) CONFIGURATION=release ;;
  *) echo "SWIFTUIWEB_LOWERING_PROFILE is dev or release, not $PROFILE" >&2; exit 2 ;;
esac
# The build folder is cached like any other build product: it lives under the build root (SWIFTUIWEB_BUILD_ROOT, default
# .build), so a second lowering reuses the compiled swift-syntax and only a change to the lowerer's own sources rebuilds.
BUILD_DIR="${SWIFTUIWEB_LOWERING_BUILD_DIR:-${SWIFTUIWEB_BUILD_ROOT:-$ROOT/.build}/swiftuiweb-lowering-build}"
PACKAGE="$ROOT/Tools/SwiftUIWebLowering"

if [[ -n "${SWIFTUIWEB_LOWERING_TOOL:-}" ]]; then
  exec "$SWIFTUIWEB_LOWERING_TOOL" "$@"
fi

# The compiler that builds the browser bundle builds the lowerer too (SWIFTUIWEB_SWIFT, else the one on PATH).
SWIFT="${SWIFTUIWEB_SWIFT:-swift}"
command -v "$SWIFT" >/dev/null 2>&1 || {
  echo "SwiftUIWeb Embedded lowering requires the Swift toolchain ($SWIFT was not found; set SWIFTUIWEB_SWIFT)." >&2
  exit 2
}

BINARY="$BUILD_DIR/$CONFIGURATION/swiftuiweb-lowering"
# Every lowering call of a build comes through here, and asking SwiftPM whether anything changed costs about two seconds, so
# it is asked only when the binary is missing or a file of the package is newer than it.
stale() {
  [[ ! -x "$BINARY" ]] && return 0
  [[ -n "$(find "$PACKAGE/Sources" "$PACKAGE/Package.swift" "$PACKAGE/Package.resolved" -newer "$BINARY" -print -quit 2>/dev/null)" ]]
}
if stale; then
  if [[ ! -x "$BINARY" ]]; then
    # Nothing is printed while swift-syntax compiles, which takes about two minutes on a clean machine.
    echo "Building the Swift lowering tool for the first time (compiles swift-syntax, about 2 minutes; later builds reuse it)..." >&2
  fi
  # SwiftPM's output goes to standard error: standard output carries the lowerer's own summary.
  "$SWIFT" build --quiet --force-resolved-versions --package-path "$PACKAGE" --scratch-path "$BUILD_DIR" \
    --configuration "$CONFIGURATION" --product swiftuiweb-lowering >&2
  # SwiftPM leaves an unchanged binary alone (a comment-only edit); it is current now, so it is no longer stale.
  touch "$BINARY"
fi

exec "$BINARY" "$@"
