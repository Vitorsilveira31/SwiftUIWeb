#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
export PATH="${BUN_INSTALL:-$HOME/.bun}/bin:$PATH"
PACKAGE_ROOT="$(cd "${SWIFTUIWEB_PACKAGE_ROOT:-$ROOT}" && pwd)"
EXTERNAL_PACKAGE=$([[ "$PACKAGE_ROOT" != "$ROOT" ]] && echo 1 || echo 0)
# An external package is lowered in a disposable copy by default. Lowering rewrites sources, and an in-place run that
# is interrupted (Ctrl-C is handled, a killed launcher is not) leaves the consumer's checkout modified. The historical
# in-place behaviour remains available with SWIFTUIWEB_LOWER_IN_PLACE=1. The SwiftPM plugin always stages.
STAGED=0
[[ "$EXTERNAL_PACKAGE" == 1 && "${SWIFTUIWEB_LOWER_IN_PLACE:-0}" != 1 ]] && STAGED=1
[[ "${SWIFTUIWEB_PLUGIN_MODE:-0}" != 1 ]] || STAGED=1
BUILD_ROOT="${SWIFTUIWEB_BUILD_ROOT:-$PACKAGE_ROOT/.build}"
if [[ -n "${SWIFTUIWEB_BUNDLE_ROOT:-}" ]]; then
  BUNDLE_ROOT="$SWIFTUIWEB_BUNDLE_ROOT"
else
  BUNDLE_ROOT="$BUILD_ROOT/browser"
fi
mkdir -p "$BUILD_ROOT"
source "$ROOT/Tools/wasm-sdk-selection.sh"
# One report of everything missing (swift, the Embedded WASM SDK, bun)
# instead of stopping at the first tool that is not there. SWIFTUIWEB_SKIP_TOOLCHAIN_REPORT=1 turns it off.
source "$ROOT/Tools/toolchain-report.sh"
# The watcher asks for the development profile `fast` by default (SWIFTUIWEB_DEV_PROFILE_DEFAULTED=1). A toolchain without the
# regular WebAssembly SDK then builds the Embedded profile instead of failing; a profile someone chose is never replaced.
if [[ "${SWIFTUIWEB_DEV_PROFILE:-}" == fast && "${SWIFTUIWEB_DEV_PROFILE_DEFAULTED:-0}" == 1 && "${SWIFTUIWEB_TOOLCHAIN_RESOLVED:-0}" != 1 ]]; then
  regular_swift="$(swiftuiweb_resolve_swift_executable false "" 2>/dev/null || true)"
  regular_sdk=""
  [[ -z "$regular_swift" ]] || regular_sdk="$(swiftuiweb_select_wasm_sdk "$("$regular_swift" sdk list 2>/dev/null || true)" false "" 0 "$regular_swift" 2>/dev/null || true)"
  if [[ -z "$regular_sdk" ]]; then
    echo "note: the development profile fast needs the toolchain's regular WebAssembly SDK (swift-<version>-RELEASE_wasm), which is not installed; building the Embedded profile instead." >&2
    export SWIFTUIWEB_DEV_PROFILE=embedded
  fi
fi
swiftuiweb_toolchain_report || exit 2
LOWERER="$ROOT/Tools/swiftuiweb-lowering.sh"
example="${1:-showcase}"; configuration="${CONFIGURATION:-release}"
# Development profile (SWIFTUIWEB_DEV_PROFILE, debug only). `embedded` (the default) compiles what ships: Embedded Swift, whole
# modules. `fast` compiles the same lowered sources as full Swift for regular WebAssembly: the compiler then works per file,
# so a save recompiles the files it changed and links (Documentation/Performance/BUILD_TIME.md, "The development profile").
# The lowering makes every `hasFeature(Embedded)` condition true (`--full-swift`), so both profiles compile the same code
# paths; the module is larger and slower than the Embedded one and is never a shipping build.
dev_profile="${SWIFTUIWEB_DEV_PROFILE:-embedded}"
case "$dev_profile" in embedded|fast) ;; *) echo "SWIFTUIWEB_DEV_PROFILE is embedded or fast, not $dev_profile" >&2; exit 2 ;; esac
[[ "$dev_profile" == embedded || "$configuration" == debug ]] || { echo "SWIFTUIWEB_DEV_PROFILE=fast needs CONFIGURATION=debug: a release is always Embedded Swift" >&2; exit 2; }
# The entry points only the development loop calls (a debug build with a development cache): the page saves its state
# before a reload and the next module starts from it (Documentation/DEVELOPMENT_WORKFLOW.md). SWIFTUIWEB_STATE_RELOAD=0
# leaves them out.
development_exports=""
[[ -z "${SWIFTUIWEB_DEV_CACHE:-}" || "$configuration" != debug || "${SWIFTUIWEB_STATE_RELOAD:-1}" == 0 ]] || development_exports="--development-exports"
full_swift=""; embedded_sdk=true
if [[ "$dev_profile" == fast ]]; then
  full_swift="--full-swift"; embedded_sdk=false
  # Its own lowered tree, scratch folder and stamps: the two profiles never rewrite each other's.
  [[ -z "${SWIFTUIWEB_DEV_CACHE:-}" ]] || export SWIFTUIWEB_DEV_CACHE="$SWIFTUIWEB_DEV_CACHE/full-swift"
  # A pinned Embedded SDK names its toolchain; this profile uses that toolchain's regular SDK.
  [[ "${WASM_SDK:-}" != *_wasm-embedded ]] || WASM_SDK="${WASM_SDK%-embedded}"
fi
command -v bun >/dev/null 2>&1 || { echo "Bun is required. Run make setup, then make run." >&2; exit 2; }
if [[ -n "${SWIFTUIWEB_PRODUCT:-}" ]]; then
  product="$SWIFTUIWEB_PRODUCT"
else
  case "$example" in showcase) product=ShowcaseApp;; conformance|layout-conformance) product=LayoutConformanceApp;; lowering|embedded-lowering|embedded-lowering-conformance) product=EmbeddedLoweringConformanceApp;; lumio) product=Lumio;; quill) product=Quill;; seekr) product=Seekr;; neighborly) product=Neighborly;; stayly) product=Stayly;; mailo) product=Mailo;; web-mount|webmount) product=WebMountExample;; media|media-example) product=MediaExample;; photos-picker|photospicker) product=PhotosPickerExample;; map|mapkit) product=MapKitExample;; avkit|avkit-example) product=AVKitExample;; notifications|user-notifications) product=UserNotificationsExample;; site|showcase-site) product=ShowcaseSite;; board|board-benchmark) product=BoardBenchmarkApp;; view-transition|view-transitions) product=ViewTransitionApp;; lazy-cells|lazy-cell-state) product=LazyCellStateApp;; motion) product=MotionApp;; security) product=SecurityExample;; webkit|webkit-example) product=WebKitExample;; *)
    if [[ "$EXTERNAL_PACKAGE" == 1 ]]; then product="$example"; else echo "Unknown example: $example" >&2; exit 2; fi
  esac
fi
# A build-only run of one of the framework's own apps reuses the bundle an earlier build made from the same inputs
# (Tools/bundle-reuse.mjs: the sources, host files, settings and toolchain, and a bundle nobody changed since), so the
# browser suites do not compile the same application again. SWIFTUIWEB_REUSE_BUNDLE=0 always builds.
reuse_key=""
if [[ "${BUILD_ONLY:-0}" == 1 && "$EXTERNAL_PACKAGE" == 0 && "${SWIFTUIWEB_REUSE_BUNDLE:-1}" == 1 && -z "${SWIFTUIWEB_DEV_CACHE:-}" ]]; then
  reuse_key="$(bun "$ROOT/Tools/bundle-reuse.mjs" key "$example")"
  if bun "$ROOT/Tools/bundle-reuse.mjs" check "$BUNDLE_ROOT/$product" "$reuse_key"; then
    echo "Reusing the bundle built from the same inputs (SWIFTUIWEB_REUSE_BUNDLE=0 rebuilds it)."
    echo "Bundle ready: $BUNDLE_ROOT/$product"
    exit 0
  fi
fi
if [[ "${SWIFTUIWEB_TOOLCHAIN_RESOLVED:-0}" == 1 && -n "${SWIFTUIWEB_SWIFT:-}" && -n "${WASM_SDK:-}" ]]; then
  # The development loop (Tools/dev-watch.mjs) resolved and checked this pair on its first build, and the toolchain does
  # not change between saves: skip `swift sdk list` and the selection (about 0.6 s per build).
  swift="$SWIFTUIWEB_SWIFT"; sdk="$WASM_SDK"
else
  swift="$(swiftuiweb_resolve_swift_executable "$embedded_sdk" "${WASM_SDK:-}" || true)"; [[ -n "$swift" ]] || { echo 'No Swift compiler with a WebAssembly SDK found' >&2; exit 2; }
  sdks="$($swift sdk list 2>/dev/null || true)"; sdk="$(swiftuiweb_select_wasm_sdk "$sdks" "$embedded_sdk" "${WASM_SDK:-}" 0 "$swift")"
fi
# The watcher reads this line to pass the same pair to the next builds.
[[ -z "${SWIFTUIWEB_DEV_CACHE:-}" ]] || echo "Resolved toolchain: swift=$swift sdk=$sdk"
# Per-file lowering results live in the development cache (SWIFTUIWEB_LOWERING_CACHE=0 turns it off): an unchanged source is
# neither parsed nor lowered again. Each lowering call gets its own folder, because the lowerer prunes the entries a run did
# not use.
lowering_cache=""
[[ -z "${SWIFTUIWEB_DEV_CACHE:-}" || "${SWIFTUIWEB_LOWERING_CACHE:-1}" == 0 ]] || lowering_cache="$SWIFTUIWEB_DEV_CACHE/lowering-cache"
# Set below when the lowerer writes straight into the development tree; that tree is then neither synced nor removed.
sync_workspace=""
# Development loop: the number of files the lowered tree changed on this run (0 when nothing changed), set only when the
# tree is the one SWIFTUIWEB_DEV_CACHE keeps (dev_tree=1). Empty when unknown, which always builds.
tree_changes=""; dev_tree=0
# Debug development loop: the framework's non-generic functions are marked `@export(interface)` by the lowering and the
# libraries are built with DeferredCodeGen, so each library compiles that code once and the executable stops recompiling
# it on every save; an edit inside such a function leaves the module unchanged and only relinks the app
# (Documentation/Performance/BUILD_TIME.md, "The development loop"). Release builds, and SWIFTUIWEB_EXPORT_INTERFACE=0, keep the
# empty-object-file model.
export_interface=""
# The profile `fast` needs neither: full Swift already compiles each library's code in that library.
if [[ -z "$full_swift" && -n "${SWIFTUIWEB_DEV_CACHE:-}" && "$configuration" == debug && "${SWIFTUIWEB_EXPORT_INTERFACE:-1}" != 0 ]]; then
  export_interface="--export-interface"; export SWIFTUIWEB_LIBRARY_CODEGEN=deferred
else
  unset SWIFTUIWEB_LIBRARY_CODEGEN
fi
# Debug development loop, with the export-interface lowering: every located declaration gets its own source location
# (`stable-source-locations`), so an edit that adds lines inside one declaration leaves the others' locations, and the
# module bytes of the libraries, alone. SWIFTUIWEB_STABLE_SOURCE_LOCATIONS=0 turns it off. Errors then name
# `path|declaration:line`, mapped back to the original file by Tools/dev-watch.mjs.
stable_source_locations=""
if [[ -n "$export_interface" && "${SWIFTUIWEB_STABLE_SOURCE_LOCATIONS:-1}" != 0 ]]; then stable_source_locations="--stable-source-locations"; fi
export SWIFTUIWEB_EMBEDDED=1 SWIFTUIWEB_EMBEDDED_RESTRICTIONS=1
# Package.swift reads this: the browser package without the Embedded compiler mode.
if [[ -n "$full_swift" ]]; then export SWIFTUIWEB_FULL_SWIFT=1; else unset SWIFTUIWEB_FULL_SWIFT; fi
LOWERING_STATE_ROOT="$BUILD_ROOT/swiftuiweb-embedded"
LOWERING_REPORT_ROOT="$BUILD_ROOT/embedded-source-lowering"
mkdir -p "$LOWERING_REPORT_ROOT"
state="$BUILD_ROOT/embedded-source-lowering/state.json"; [[ ! -f "$state" ]] || "$LOWERER" --restore --root "$ROOT" --state "$state"
tmp="$(mktemp -d "$BUILD_ROOT/.embedded-browser.XXXXXX")"
workspace="$tmp/workspace"; scratch="$tmp/scratch"
framework_workspace=""
server_pid=""
mock_pid=""
restore_external_sources() {
  [[ "${SWIFTUIWEB_PLUGIN_MODE:-0}" == 1 ]] && return 0
  [[ "$EXTERNAL_PACKAGE" == 1 ]] || return 0
  "$LOWERER" --restore --root "$PACKAGE_ROOT" --state "$LOWERING_STATE_ROOT/app-state.json" 2>/dev/null || true
  "$LOWERER" --restore --root "$ROOT" --state "$LOWERING_STATE_ROOT/framework-state.json" 2>/dev/null || true
}
cleanup(){
  local exit_code=$?
  trap - EXIT INT TERM HUP
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill -TERM "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  if [[ -n "$mock_pid" ]] && kill -0 "$mock_pid" 2>/dev/null; then
    kill -TERM "$mock_pid" 2>/dev/null || true
    wait "$mock_pid" 2>/dev/null || true
  fi
  restore_external_sources
  # SWIFTUIWEB_KEEP_WORKSPACE=1 leaves the lowered sources and build products for inspection.
  if [[ "${SWIFTUIWEB_KEEP_WORKSPACE:-0}" == 1 ]]; then echo "Kept lowered workspace: $tmp" >&2; else rm -rf "$tmp"; fi
  exit "$exit_code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
if [[ "$EXTERNAL_PACKAGE" == 1 ]]; then
  # Recover a checkout left lowered by an older interrupted in-place run before anything else.
  restore_external_sources
  if [[ "$STAGED" == 1 ]]; then
    # SwiftPM command plugins may read the consumer checkout but cannot write
    # it without an explicit package-directory permission. Copy both sides of
    # a relative path dependency into a disposable topology that preserves
    # the checkout's actual relative path. This matters for examples nested
    # under the framework (for example `Examples/UniversalApp` uses `../..`),
    # while external consumers commonly use `../swiftuiweb`.
    # The staged framework goes where the consumer's manifest says SwiftUIWeb is (`../../swiftuiweb`), so the checkout
    # that provides it can be any directory: a worktree, a copy with another name, SWIFTUIWEB_ROOT elsewhere.
    relative_framework="$(bun "$ROOT/Tools/local-package-dependencies.mjs" --framework-path "$PACKAGE_ROOT")"
    framework_by_url=0
    if [[ -z "$relative_framework" ]]; then
      if bun "$ROOT/Tools/framework-url-dependency.mjs" has "$PACKAGE_ROOT/Package.swift"; then
        # The manifest names the framework by URL, so there is no declared place to mirror. The staged copies of the
        # manifests are rewritten to a path dependency on a directory the launcher names, `swiftuiweb`, whatever the
        # checkout is called (a worktree is fine). Two levels up, like an application in a monorepo folder.
        relative_framework="../../swiftuiweb"
        framework_by_url=1
      else
        relative_framework="$(bun "$ROOT/Tools/staging-layout.mjs" relative-framework "$ROOT" "$PACKAGE_ROOT")"
      fi
    fi
    staging_root="$tmp/staging"
    # Choose an opaque consumer path whose relative dependency resolves to a
    # directory named `swiftuiweb`. SwiftPM derives a local package identity
    # from that final directory component, so preserving the path alone is
    # insufficient for manifests that declare `package: "swiftuiweb"`.
    staging_layout="$(bun "$ROOT/Tools/staging-layout.mjs" layout "$staging_root" "$relative_framework")"
    workspace="${staging_layout%%$'\n'*}"
    framework_workspace="${staging_layout#*$'\n'}"
    # Debug development loop: the framework's generic-type names go to a file that the application's and the local packages'
    # runs read (`--generic-types-in`). Those runs scan only their own files, and `export-interface` must still see that
    # `extension View` is generic. SWIFTUIWEB_CONSUMER_CODEGEN=0 keeps the application lowering as it was.
    framework_generic_types=""; application_export_args=()
    if [[ -n "$export_interface" && "${SWIFTUIWEB_CONSUMER_CODEGEN:-1}" != 0 ]]; then
      framework_generic_types="$tmp/framework-generic-types.txt"
      application_export_args=(--export-interface --export-interface-application --generic-types-in "$framework_generic_types")
    fi
    "$LOWERER" --apply ${SWIFTUIWEB_LIVE_LITERALS:+--live-literals} ${development_exports:+"$development_exports"} --root "$ROOT" --product "$product" --workspace "$framework_workspace" --report "$LOWERING_REPORT_ROOT/framework-report.json" ${lowering_cache:+--cache "$lowering_cache/framework"} ${export_interface:+"$export_interface"} ${stable_source_locations:+"$stable_source_locations"} ${full_swift:+"$full_swift"} ${framework_generic_types:+--generic-types-out "$framework_generic_types"}
    "$LOWERER" --apply ${SWIFTUIWEB_LIVE_LITERALS:+--live-literals} ${development_exports:+"$development_exports"} --root "$PACKAGE_ROOT" --product "$product" --lower-codable --workspace "$workspace" --report "$LOWERING_REPORT_ROOT/app-report.json" ${lowering_cache:+--cache "$lowering_cache/app"} ${stable_source_locations:+"$stable_source_locations"} ${full_swift:+"$full_swift"} ${application_export_args[@]+"${application_export_args[@]}"}
    # The consumer's other local packages (`.package(path: "../Shared")`) must exist at the same relative place in the
    # staging topology, lowered like the consumer: the package that SwiftPM builds finds them where its manifest says.
    # Each is a directory with a Package.swift next to the consumer's, below the staging root.
    dependency_workspaces=""
    while IFS=$'\t' read -r dependency_source dependency_workspace; do
      [[ -n "$dependency_source" ]] || continue
      dependency_name="$(basename "$dependency_source")"
      "$LOWERER" --apply ${SWIFTUIWEB_LIVE_LITERALS:+--live-literals} ${development_exports:+"$development_exports"} --root "$dependency_source" --product "$product" --lower-codable --workspace "$dependency_workspace" --report "$LOWERING_REPORT_ROOT/dependency-$dependency_name-report.json" ${lowering_cache:+--cache "$lowering_cache/dependency-$dependency_name"} ${stable_source_locations:+"$stable_source_locations"} ${full_swift:+"$full_swift"} ${application_export_args[@]+"${application_export_args[@]}"}
      dependency_workspaces="$dependency_workspaces$dependency_workspace"$'\n'
    done < <(bun Tools/local-package-dependencies.mjs "$PACKAGE_ROOT" "$workspace" "$staging_root" "$ROOT")
    # A manifest that names SwiftUIWeb by URL (`.package(url: ".../swiftuiweb.git", from: "0.1.0")`) would make SwiftPM fetch
    # the original framework; in the staged copies it points at the lowered framework instead, as a path dependency.
    bun Tools/framework-url-dependency.mjs rewrite "$workspace/Package.swift" "$framework_workspace" >/dev/null
    while IFS= read -r dependency_workspace; do
      [[ -z "$dependency_workspace" ]] || bun Tools/framework-url-dependency.mjs rewrite "$dependency_workspace/Package.swift" "$framework_workspace" >/dev/null
    done <<< "${dependency_workspaces:-}"
    # Debug development loop: the application's library targets get the framework's DeferredCodeGen model too, in the
    # staged manifests only (Tools/dev-consumer-manifest.mjs). SWIFTUIWEB_CONSUMER_CODEGEN=0 leaves them as they are.
    if [[ -n "$export_interface" && "${SWIFTUIWEB_CONSUMER_CODEGEN:-1}" != 0 ]]; then
      consumer_manifests=("$workspace/Package.swift")
      while IFS= read -r dependency_workspace; do [[ -z "$dependency_workspace" ]] || consumer_manifests+=("$dependency_workspace/Package.swift"); done <<< "${dependency_workspaces:-}"
      bun Tools/dev-consumer-manifest.mjs "${consumer_manifests[@]}" >/dev/null
    fi
  else
    if bun "$ROOT/Tools/framework-url-dependency.mjs" has "$PACKAGE_ROOT/Package.swift"; then
      echo "error: $PACKAGE_ROOT/Package.swift names SwiftUIWeb by URL, which only the staged build can point at the lowered framework." >&2
      echo "       Unset SWIFTUIWEB_LOWER_IN_PLACE, or declare the framework as a path dependency." >&2
      exit 2
    fi
    # The standalone launcher may preserve the historical in-place path for
    # consumers that explicitly opted into it; the exit trap restores both
    # checkouts even when compilation fails.
    restore_external_sources
    "$LOWERER" --apply ${SWIFTUIWEB_LIVE_LITERALS:+--live-literals} ${development_exports:+"$development_exports"} --root "$ROOT" --product "$product" --state "$LOWERING_STATE_ROOT/framework-state.json" --report "$LOWERING_REPORT_ROOT/framework-report.json" ${full_swift:+"$full_swift"}
    "$LOWERER" --apply ${SWIFTUIWEB_LIVE_LITERALS:+--live-literals} ${development_exports:+"$development_exports"} --root "$PACKAGE_ROOT" --product "$product" --lower-codable --state "$LOWERING_STATE_ROOT/app-state.json" --report "$LOWERING_REPORT_ROOT/app-report.json" ${full_swift:+"$full_swift"}
  fi
  manifest="$BUILD_ROOT/release-manifest-$product.json"
  # Application evidence is the consumer's code only; the framework sources
  # are passed separately and supply CSS/icon vocabulary, never feature use.
  source_roots="$PACKAGE_ROOT/Sources:$PACKAGE_ROOT/Web"
  framework_roots="$ROOT/Sources"
  [[ -z "$framework_workspace" ]] || { source_roots="$workspace/Sources:$workspace/Web"; framework_roots="$framework_workspace/Sources"; }
  # The consumer's local packages are part of the application, not of the framework.
  while IFS= read -r dependency_workspace; do [[ -z "$dependency_workspace" ]] || source_roots="$source_roots:$dependency_workspace/Sources"; done <<< "${dependency_workspaces:-}"
  bun Tools/release-reachability.js --root "$ROOT" --source "$source_roots" --framework-source "$framework_roots" --product "$product" --configuration "$configuration" --output "$manifest"
else
  # Lower a complete disposable SwiftPM workspace. The checkout remains
  # byte-for-byte unchanged even if compilation or linker setup fails.
  # In the development loop the lowerer writes straight into the tree that lives between runs (`--sync-workspace`):
  # only the files whose bytes change are written, so SwiftPM recompiles only what changed, without a copy of the
  # repository, a sync and a removal on every save (SWIFTUIWEB_SYNC_WORKSPACE=0 goes back to copy and sync).
  sync_workspace=""
  if [[ -n "${SWIFTUIWEB_DEV_CACHE:-}" && "${SWIFTUIWEB_SYNC_WORKSPACE:-1}" != 0 ]]; then
    mkdir -p "$SWIFTUIWEB_DEV_CACHE"; workspace="$SWIFTUIWEB_DEV_CACHE/tree"; sync_workspace="--sync-workspace"
  fi
  lower_args=(--apply ${SWIFTUIWEB_LIVE_LITERALS:+--live-literals} ${development_exports:+"$development_exports"} --root "$ROOT" --product "$product" --workspace "$workspace" --report "$LOWERING_REPORT_ROOT/$product-report.json" ${lowering_cache:+--cache "$lowering_cache/$product"} ${sync_workspace:+"$sync_workspace"} ${export_interface:+"$export_interface"} ${stable_source_locations:+"$stable_source_locations"} ${full_swift:+"$full_swift"})
  if [[ -n "$sync_workspace" ]]; then
    # A sync run's summary counts the workspace files it changed (`workspaceChanges`); the build below reads it.
    # A lowering that fails or is interrupted can have written some files before it stopped, and the next run, with the
    # source fixed, then writes nothing and reports no change. The marker stays until a lowering finishes, so that next
    # run builds instead of trusting a stamp that no longer describes the tree.
    lowering_marker="$SWIFTUIWEB_DEV_CACHE/lowering-in-progress"
    lowering_interrupted=0; [[ ! -e "$lowering_marker" ]] || lowering_interrupted=1
    : > "$lowering_marker"
    "$LOWERER" "${lower_args[@]}" | tee "$tmp/lowering-summary.json"
    rm -f "$lowering_marker"
    tree_changes="$(bun -e 'const m = await Bun.file(process.argv[1]).json(); if (Number.isInteger(m.workspaceChanges)) console.log(m.workspaceChanges)' "$tmp/lowering-summary.json" 2>/dev/null || true)"
    [[ "$lowering_interrupted" == 0 ]] || tree_changes=""
  else
    "$LOWERER" "${lower_args[@]}"
  fi
  manifest="$BUILD_ROOT/release-manifest-$product.json"; bun Tools/release-reachability.js --product "$product" --configuration "$configuration" --output "$manifest"
fi
flags=(-Xswiftc -Xclang-linker -Xswiftc -mexec-model=reactor)
# The profile `fast` compiles full Swift, which accepts code Embedded Swift refuses (an existential of a generic protocol,
# reflection). The compiler's EmbeddedRestrictions diagnostics report such code as warnings in every target, so it is seen
# on the save that wrote it and not only when the Embedded build runs.
[[ -z "$full_swift" ]] || flags+=(-Xswiftc -Wwarning -Xswiftc EmbeddedRestrictions)
# The browser runs one thread and its executor is the host event loop, so the
# runtime's "called on the same actor" checks (on in Swift 6 mode) can only
# misfire there. Compile-time isolation still applies; the checks are dropped.
flags+=(-Xswiftc -Xfrontend -Xswiftc -disable-dynamic-actor-isolation -Xswiftc -Xfrontend -Xswiftc -disable-actor-data-race-checks)
# SwiftUI renders deep, generic view hierarchies recursively. Apple's main
# thread runs them on an 8 MiB stack; wasm-ld's default is only 64 KiB, and a
# deep screen then overflows into static data and the allocator. Match the
# native budget (overridable) so view depth behaves like SwiftUI.
flags+=(-Xlinker -z -Xlinker "stack-size=${SWIFTUIWEB_WASM_STACK_SIZE:-8388608}")
# Generic specialization emits many near-identical bodies for different view
# types. Swift's own function-merging pass folds them; a lower threshold merges
# more aggressively (size only, measurable with Tools/analyze-wasm-size.js). A release merges at 30, which shrinks
# app.wasm after wasm-opt (Documentation/Performance/WASM_SIZE.md); a debug build keeps the toolchain default.
# SWIFTUIWEB_WASM_MERGEFUNC_THRESHOLD=<n> picks another threshold, =off keeps the toolchain default.
mergefunc_default=off; [[ "$configuration" == release ]] && mergefunc_default=30
mergefunc_threshold="${SWIFTUIWEB_WASM_MERGEFUNC_THRESHOLD:-$mergefunc_default}"
[[ "$mergefunc_threshold" == off ]] || flags+=(-Xswiftc -Xllvm -Xswiftc "-swiftmergefunc-threshold=$mergefunc_threshold")
# SwiftPM appends its own `-g` after user `-Xswiftc` flags, so `-Xswiftc -gnone`
# never wins; `-debug-info-format none` stops SwiftPM from passing `-g`.
# `--strip-debug` drops any remaining .debug_* at link time and keeps `name`,
# which SWIFTUIWEB_KEEP_WASM_NAMES and the size analysis read.
# Debug builds drop DWARF too: it is most of a 60 MB app.wasm that the browser
# compiles on every reload, while the `name` section (kept) is what gives readable
# stack traces. SWIFTUIWEB_WASM_DEBUG_INFO=1 keeps DWARF for debugging Swift in
# DevTools (the C/C++ DWARF extension).
debug_flags=()
if [[ "$configuration" == release || "${SWIFTUIWEB_WASM_DEBUG_INFO:-0}" != 1 ]]; then debug_flags=(-debug-info-format none); fi
[[ "$configuration" == release || "${SWIFTUIWEB_WASM_DEBUG_INFO:-0}" == 1 ]] || flags+=(-Xlinker --strip-debug)
# Release profile (SWIFTUIWEB_RELEASE_PROFILE, or --release-profile on the launcher): how much of the build time to trade for
# size. The Embedded app module specializes and optimizes the serialized SIL of every library in one thread, so the
# optimizer, not the type checker or the number of cores, is the build time. Measured on the Showcase (Documentation/
# Performance/BUILD_TIME.md): size (default) is the shipping build; balanced leaves the framework libraries unoptimized and
# optimizes the app (about 5 to 10% faster, app.wasm about 5% larger); fast optimizes nothing in swiftc and leaves it to
# wasm-opt (about 55% faster, app.wasm about 2.4x larger) for previews and CI, never for shipping.
# SWIFTUIWEB_WASM_OPTIMIZATION still wins when set.
release_profile="${SWIFTUIWEB_RELEASE_PROFILE:-size}"
case "$release_profile" in size|balanced|fast) ;; *) echo "SWIFTUIWEB_RELEASE_PROFILE is size, balanced or fast, not $release_profile" >&2; exit 2 ;; esac
wasm_optimization="${SWIFTUIWEB_WASM_OPTIMIZATION:-}"
if [[ -z "$wasm_optimization" ]]; then if [[ "$release_profile" == fast ]]; then wasm_optimization=-Onone; else wasm_optimization=-Osize; fi; fi
if [[ "$configuration" == release && "$release_profile" != size ]]; then echo "Release profile: $release_profile (not a shipping build)" >&2; fi
# Split app.wasm by what the first screen runs (Documentation/Architecture/WASM_SPLIT.md), the release default. Unset, a
# machine without what the split needs (Binaryen's wasm-split, a headless Chromium) builds one app.wasm with a warning, as a
# release without wasm-opt does; SWIFTUIWEB_WASM_SPLIT=0 builds one app.wasm on purpose, =1 makes a split that cannot be
# made an error. Debug, the development loop (SWIFTUIWEB_DEV_CACHE) and the fast profile (previews, CI) build no split unless
# asked: the profile run costs a browser start and a few seconds per build.
wasm_split=off
case "${SWIFTUIWEB_WASM_SPLIT:-}" in
  1) [[ "$configuration" == release ]] || { echo "SWIFTUIWEB_WASM_SPLIT=1 needs CONFIGURATION=release" >&2; exit 2; }; wasm_split=required ;;
  0) ;;
  "") [[ "$configuration" != release || "$release_profile" == fast || -n "${SWIFTUIWEB_DEV_CACHE:-}" ]] || wasm_split=auto ;;
  *) echo "SWIFTUIWEB_WASM_SPLIT is 0 or 1, not ${SWIFTUIWEB_WASM_SPLIT}" >&2; exit 2 ;;
esac
# Package.swift reads this while SwiftPM evaluates the manifest; it only affects the framework's own library targets.
if [[ "$configuration" == release && "$release_profile" == balanced ]]; then export SWIFTUIWEB_LIBRARY_OPTIMIZATION=none; else unset SWIFTUIWEB_LIBRARY_OPTIMIZATION; fi
if [[ "$configuration" == release ]]; then flags+=(-Xswiftc "$wasm_optimization" -Xlinker --strip-debug -Xswiftc -D -Xswiftc SWIFTUIWEB_RELEASE); while IFS= read -r d; do [[ -z "$d" || "$d" == SWIFTUIWEB_RELEASE ]] || flags+=(-Xswiftc -D -Xswiftc "$d"); done < <(bun -e 'const m=await Bun.file(process.argv[1]).json(); for(const d of m.swiftDefines||[]) console.log(d)' "$manifest"); fi
# Extra `swift build` arguments for diagnosing build time, e.g.
# SWIFTUIWEB_EXTRA_BUILD_FLAGS="-Xswiftc -stats-output-dir -Xswiftc /tmp/stats".
# Word-split on purpose; leave unset for normal builds.
[[ -z "${SWIFTUIWEB_EXTRA_BUILD_FLAGS:-}" ]] || { read -r -a extra_flags <<< "$SWIFTUIWEB_EXTRA_BUILD_FLAGS"; flags+=("${extra_flags[@]}"); }
package_path="$workspace"; [[ "$EXTERNAL_PACKAGE" == 1 ]] && package_path="$PACKAGE_ROOT"
if [[ "$EXTERNAL_PACKAGE" == 1 && "$STAGED" == 1 ]]; then
  package_path="$workspace"
fi
# Development loop (`swiftuiweb-run --watch`): SWIFTUIWEB_DEV_CACHE names a folder that lives between runs. The lowered
# tree is synced into it, rewriting only the files whose bytes changed, and SwiftPM's scratch folder stays there, so the
# next build recompiles only what changed instead of everything. An external package lowered in place has no disposable
# tree to sync, so it builds from scratch as before.
if [[ -n "${SWIFTUIWEB_DEV_CACHE:-}" ]]; then
  if [[ "$EXTERNAL_PACKAGE" == 1 && "$STAGED" != 1 ]]; then
    echo "note: SWIFTUIWEB_DEV_CACHE needs a staged build; this package is lowered in place, so it builds from scratch." >&2
  else
    if [[ -z "$sync_workspace" ]]; then
      sync_from="$workspace"; [[ "$EXTERNAL_PACKAGE" == 1 ]] && sync_from="$staging_root"
      mkdir -p "$SWIFTUIWEB_DEV_CACHE"
      # The files the sync writes are listed for the direct build, which must know that each one is its to compile
      # (SWIFTUIWEB_SYNC_LIST=1 also prints them, to find files that change without an edit).
      tree_summary="$(bun Tools/sync-tree.mjs "$sync_from" "$SWIFTUIWEB_DEV_CACHE/tree" --list 2> "$tmp/sync-changes.txt" || true)"
      [[ -z "${SWIFTUIWEB_SYNC_LIST:-}" ]] || cat "$tmp/sync-changes.txt" >&2
      echo "Lowered tree: $tree_summary"
      # `changed 0, removed 0, …` is a tree the last build already saw; anything else (or no summary) builds.
      # The number of files written is what the direct build compares with the Swift sources it finds changed; a removed
      # file, or a summary that cannot be read, is a build for `swift build`.
      if [[ "$tree_summary" == "changed 0, removed 0,"* ]]; then tree_changes=0
      elif [[ "$tree_summary" =~ ^changed\ ([0-9]+),\ removed\ 0, ]]; then tree_changes="${BASH_REMATCH[1]}"
      else tree_changes=""; fi
      package_path="$SWIFTUIWEB_DEV_CACHE/tree${package_path#"$sync_from"}"
    fi
    scratch="$SWIFTUIWEB_DEV_CACHE/scratch"
    dev_tree=1
    # Nothing reads the index of this scratch folder (an editor indexes the checkout, not the lowered copy), and writing
    # it is about 16% of a framework module's compile (Documentation/Performance/BUILD_TIME.md).
    flags+=(--disable-index-store)
    # The LLVM IR verifier only catches compiler bugs; in the debug loop it is about 0.8 s of an app module's 4.3 s of LLVM.
    [[ "$configuration" != debug ]] || flags+=(-Xswiftc -Xfrontend -Xswiftc -disable-llvm-verify)
  fi
fi
# The direct build (development profile `fast`, development loop): the compiler commands of a verbose `swift build` are kept,
# and a save whose changes are Swift sources of known modules is compiled by replaying them, without the 1.3 s `swift build`
# takes to find out what changed (Tools/dev-direct-build.mjs). Anything else builds with `swift build` as before.
# SWIFTUIWEB_DIRECT_BUILD=0 turns it off.
direct_build=0
if [[ -n "$full_swift" && "$dev_tree" == 1 && "${SWIFTUIWEB_DIRECT_BUILD:-1}" != 0 ]]; then direct_build=1; flags+=(-v); fi
# Hot swap (SWIFTUIWEB_HOT_SWAP=1, with the direct build): the product is linked as a main module (the framework and the
# standard library) and a side module (the application). A save that changes only the application links the side module,
# and the page loads it into the module it is running instead of reloading (Tools/side-module.js;
# Documentation/DEVELOPMENT_WORKFLOW.md, "Hot swap").
hot_swap=""; [[ "$direct_build" != 1 || "${SWIFTUIWEB_HOT_SWAP:-0}" != 1 ]] || hot_swap="--hot"
build_args=(build --disable-sandbox --package-path "$package_path" --scratch-path "$scratch" --configuration "$configuration" --swift-sdk "$sdk" --product "$product" ${debug_flags[@]+"${debug_flags[@]}"} "${flags[@]}")
# Development loop: when the lowered tree changed nothing and every input of the build is that of the last successful build
# of this cache, `swift build` has nothing to do (its planning alone is about 1.5 s), so it is skipped. The stamp holds the
# fingerprint of those inputs and is written only after a build that passed; it is removed before any build starts, so a
# failed or interrupted build never leaves one that skips the next. SWIFTUIWEB_SKIP_UNCHANGED_BUILD=0 always builds.
skip_swift_build=0; stamp=""; fingerprint=""; direct_status=3
if [[ "$dev_tree" == 1 ]]; then
  stamp="$SWIFTUIWEB_DEV_CACHE/last-build.stamp"
  # Everything else that decides the build: the compiler and SDK, the configuration, the product, the package, the whole
  # argument list (flags and debug flags) and the environment variables Package.swift reads.
  fingerprint="$(printf '%s\n' "$swift" "$sdk" "$configuration" "$product" "$package_path" "${build_args[@]}" \
    "SWIFTUIWEB_EMBEDDED=${SWIFTUIWEB_EMBEDDED-<unset>}" "SWIFTUIWEB_EMBEDDED_RESTRICTIONS=${SWIFTUIWEB_EMBEDDED_RESTRICTIONS-<unset>}" \
    "SWIFTUIWEB_LIBRARY_OPTIMIZATION=${SWIFTUIWEB_LIBRARY_OPTIMIZATION-<unset>}" "SWIFTUIWEB_LIBRARY_CODEGEN=${SWIFTUIWEB_LIBRARY_CODEGEN-<unset>}" "SWIFTUIWEB_FULL_SWIFT=${SWIFTUIWEB_FULL_SWIFT-<unset>}")"
  # The stamp also says whether the last build was a hot one. A hot build links the side module and leaves the ordinary
  # executable as it was (and the reverse), so a run in the other mode with nothing changed is not a build to skip: the
  # direct build then links what that mode bundles. The plan is the same for both, so the mode is not in its fingerprint.
  stamp_text="$(printf '%s\n%s' "$fingerprint" "hot-swap=${hot_swap:-off}")"
  built_artifact="$(find "$scratch" -path '*Products*' -name "$product.wasm" -print 2>/dev/null | head -1 || true)"
  if [[ "${SWIFTUIWEB_SKIP_UNCHANGED_BUILD:-1}" != 0 && "$tree_changes" == 0 && -f "$stamp" && "$(cat "$stamp" 2>/dev/null || true)" == "$stamp_text" && -f "$built_artifact" ]]; then
    skip_swift_build=1
  fi
fi
if [[ "$skip_swift_build" == 1 ]]; then
  echo "Swift build skipped: nothing changed since the last build"
  : > "$tmp/swift-build.log"
else
  [[ "$dev_tree" != 1 ]] || rm -f "$stamp"
  if [[ "$direct_build" == 1 ]]; then
    build_started="$(bun -e 'console.log(Date.now())')"
    direct_status=0
    # A staged tree is synced by Tools/sync-tree.mjs, which lists the files it wrote; the lowerer's own sync gives a count.
    direct_changes=(); [[ -n "$sync_workspace" ]] || direct_changes=(--changed-files "$tmp/sync-changes.txt")
    bun Tools/dev-direct-build.mjs build --cache "$SWIFTUIWEB_DEV_CACHE" --fingerprint "$fingerprint" --tree-changes "$tree_changes" ${direct_changes[@]+"${direct_changes[@]}"} ${hot_swap:+"$hot_swap"} 2>&1 | tee "$tmp/swift-build.log" || direct_status=$?
    if [[ "$direct_status" != 0 && "$direct_status" != 3 ]]; then
      echo "error: the Swift build of the browser product failed. The first error above names a lowered copy of a source file; its path after Sources/ is the original file." >&2
      exit 1
    fi
  fi
  # With the direct build on, the build's standard output is also kept on its own: the commands are read from it, and a
  # warning written to standard error in the middle of a command line would cut that line.
  swift_build() {
    if [[ "$direct_build" == 1 ]]; then { "$swift" "${build_args[@]}" 2>&3 | tee "$tmp/swift-build.commands"; } 3>&1
    else "$swift" "${build_args[@]}" 2>&1; fi
  }
  [[ "$direct_status" == 0 ]] || swift_build | tee "$tmp/swift-build.log" || {
    echo "error: the Swift build of the browser product failed. The first error above names a lowered copy of a source file under the staging directory; its path after Sources/ is the original file, and its line numbers follow the lowering's line map in $LOWERING_REPORT_ROOT/app-report.json." >&2
    [[ -z "$stable_source_locations" ]] || echo "note: a path of the form file|declaration:line is a line relative to that declaration (its first line is line 1); the lowering's report maps it to the original line." >&2
    exit 1
  }
  # The commands this build printed are what the direct build replays on the next saves.
  [[ "$direct_build" != 1 || "$direct_status" == 0 ]] || bun Tools/dev-direct-build.mjs record --cache "$SWIFTUIWEB_DEV_CACHE" --scratch "$scratch" --log "$tmp/swift-build.commands" --fingerprint "$fingerprint" --started "$build_started"
  # A hot build's two modules, after a build the build system did (the first, or one the direct build handed back).
  if [[ -n "$hot_swap" && "$direct_status" != 0 ]]; then bun Tools/dev-direct-build.mjs prepare-hot --cache "$SWIFTUIWEB_DEV_CACHE" || true; fi
  # SwiftPM changes the one file it owns in the tree: a build deletes or rewrites the tree's Package.resolved, which the
  # next sync would write again and count as a change. Putting back the lowered copies of those files (and nothing else)
  # means the next run finds the tree this build saw, so an unchanged run can skip the build.
  if [[ "$dev_tree" == 1 ]]; then
    resolved_from="$ROOT"; [[ -z "$sync_workspace" ]] && resolved_from="$sync_from"
    resolved_to="$workspace"; [[ -z "$sync_workspace" ]] && resolved_to="$SWIFTUIWEB_DEV_CACHE/tree"
    while IFS= read -r resolved; do
      cmp -s "$resolved_from/$resolved" "$resolved_to/$resolved" || cp "$resolved_from/$resolved" "$resolved_to/$resolved"
    done < <(cd "$resolved_from" && find . -maxdepth 4 -name Package.resolved -not -path '*/.build/*' -not -path '*/node_modules/*' 2>/dev/null)
  fi
fi
# Concurrency diagnostics in the Embedded build are real: the dynamic isolation checks are off in the
# browser, so a warning here is a data race the compiler could not rule out. This toolchain gives these
# warnings no diagnostic group, so `-Werror <group>` cannot select them; the log is checked instead.
# SWIFTUIWEB_CONCURRENCY_WARNINGS=error (the default for this repository's own examples, and what CI
# runs) fails the build; `warn` (the default for an external package) only reports them.
concurrency_mode="${SWIFTUIWEB_CONCURRENCY_WARNINGS:-$([[ "$EXTERNAL_PACKAGE" == 1 ]] && echo warn || echo error)}"
if grep -E 'warning: .*(Sendable|actor-isolated|nonisolated|data race)' "$tmp/swift-build.log" | sed -E 's/\x1b\[[0-9;]*m//g' | sort -u > "$tmp/concurrency-warnings.log" && [[ -s "$tmp/concurrency-warnings.log" ]]; then
  echo "$(wc -l < "$tmp/concurrency-warnings.log" | tr -d ' ') concurrency warning(s) in the Embedded build:" >&2
  cat "$tmp/concurrency-warnings.log" >&2
  if [[ "$concurrency_mode" == error ]]; then
    echo "Failing: these are data-race warnings and SWIFTUIWEB_CONCURRENCY_WARNINGS is error. Fix the listed code, or as a TEMPORARY override only, rerun with SWIFTUIWEB_CONCURRENCY_WARNINGS=warn." >&2
    exit 1
  fi
  echo "Reported only: SWIFTUIWEB_CONCURRENCY_WARNINGS=$concurrency_mode. Set SWIFTUIWEB_CONCURRENCY_WARNINGS=error to fail the build on them." >&2
fi
# The stamp is written after the concurrency check, so a build with warnings or data-race errors never becomes one that is skipped.
if [[ "$dev_tree" == 1 && "$skip_swift_build" == 0 && ! -s "$tmp/concurrency-warnings.log" ]]; then printf '%s\n' "$stamp_text" > "$stamp"; fi
artifact="$(find "$scratch" -path '*Products*' -name "$product.wasm" -print | head -1)"; [[ -f "$artifact" ]] || { echo "Could not locate $product.wasm" >&2; exit 1; }
# A save of Swift sources that the direct build compiled changes one file of the bundle, app.wasm, as long as the
# application uses the same framework features as before (the reachability manifest decides which host files and icons the
# bundle holds). The watcher says when every saved file was a Swift source (SWIFTUIWEB_WATCH_SWIFT_ONLY=1); then the module
# is put in the bundle the last build left and the steps that would write the same files again are skipped.
bundle_manifest="${SWIFTUIWEB_DEV_CACHE:-$BUILD_ROOT}/bundle-manifest-$product.json"
# A staged package's manifest names its sources below this run's temporary folder; the comparison leaves that name out.
comparable_manifest() { sed "s|${tmp##*/}|.embedded-browser|g" "$manifest"; }
# A hot build's bundle holds the two modules: app.wasm is the main module and app-side.wasm the application.
hot_main=""; hot_side=""
# Only when the plan says the split is valid now (a failed preparation deletes the modules and marks the plan).
if [[ -n "$hot_swap" ]] && bun Tools/dev-direct-build.mjs hot-status --cache "$SWIFTUIWEB_DEV_CACHE" --fingerprint "$fingerprint"; then
  hot_main="$SWIFTUIWEB_DEV_CACHE/hot/main.wasm"; hot_side="$SWIFTUIWEB_DEV_CACHE/hot/side.wasm"
fi
replace_in_bundle() { cp "$1" "$BUNDLE_ROOT/$product/$2.next" && mv "$BUNDLE_ROOT/$product/$2.next" "$BUNDLE_ROOT/$product/$2"; }
if [[ "$direct_status" == 0 && "${SWIFTUIWEB_WATCH_SWIFT_ONLY:-0}" == 1 && "${BUILD_ONLY:-0}" == 1 && -f "$BUNDLE_ROOT/$product/app.wasm" && -f "$BUNDLE_ROOT/$product/index.html" ]] && comparable_manifest | cmp -s - "$bundle_manifest"; then
  if [[ -z "$hot_main" ]]; then
    replace_in_bundle "$artifact" app.wasm
    echo "Bundle ready: $BUNDLE_ROOT/$product (app.wasm replaced)"
  elif grep -q '^Hot swap: the side module changed' "$tmp/swift-build.log" && [[ -f "$BUNDLE_ROOT/$product/app-side.wasm" ]]; then
    # Only the application changed: the watcher reads this line and tells the pages to swap it in.
    replace_in_bundle "$hot_side" app-side.wasm
    echo "Bundle ready: $BUNDLE_ROOT/$product (app-side.wasm replaced)"
  else
    replace_in_bundle "$hot_side" app-side.wasm; replace_in_bundle "$hot_main" app.wasm
    echo "Bundle ready: $BUNDLE_ROOT/$product (app.wasm replaced)"
  fi
  exit 0
fi
if [[ -n "$hot_main" ]]; then
  cp "$hot_main" "$tmp/app.wasm"; cp "$hot_side" "$tmp/app-side.wasm"
  # The loader the page imports when it meets a hot build; no other bundle has it.
  bun build Tools/side-module.js --target=browser --format=esm --minify --outfile="$tmp/side-module.js" >/dev/null
  bun Tools/check-wasm-exports.mjs "$tmp/app.wasm" --side "$tmp/app-side.wasm" --product "$product" "$LOWERING_REPORT_ROOT"
else
  cp "$artifact" "$tmp/app.wasm"
  bun Tools/check-wasm-exports.mjs "$tmp/app.wasm" --product "$product" "$LOWERING_REPORT_ROOT"
fi
# index.js, render-worker.js and the chunk both import (runtime-shared.js), built together. A release leaves out the browser
# hosts the manifest proves unused; debug keeps every host (Tools/build-runtime-bundle.mjs).
# The loader of a split module (Tools/wasm-split-loader.js) is in the scripts only when the module will be split, so whether
# this machine can split is settled first.
if [[ "$wasm_split" != off ]] && ! split_unavailable="$(bun Tools/wasm-split-release.mjs --check 2>&1)"; then
  if [[ "$wasm_split" == required ]]; then echo "error: SWIFTUIWEB_WASM_SPLIT=1, but $split_unavailable" >&2; exit 1; fi
  echo "warning: this release app.wasm is NOT split (one module, downloaded whole before the first screen): $split_unavailable. SWIFTUIWEB_WASM_SPLIT=0 builds without the split on purpose." >&2
  wasm_split=off
fi
runtime_flags=(); [[ "$wasm_split" == off ]] || runtime_flags=(--wasm-split)
if [[ "$configuration" == release ]]; then bun Tools/build-runtime-bundle.mjs --outdir "$tmp" --manifest "$manifest" ${runtime_flags[@]+"${runtime_flags[@]}"}; else bun Tools/build-runtime-bundle.mjs --outdir "$tmp" ${runtime_flags[@]+"${runtime_flags[@]}"}; fi
# Copy only the browser helpers the reachability manifest lists (initial and
# lazy); an unreachable helper is neither shipped nor referenced by index.html.
while IFS= read -r helper; do [[ -z "$helper" || "$helper" == icon-adapter.js ]] && continue; if [[ "$helper" == *.js ]]; then bun build "Tools/$helper" --minify --outfile="$tmp/$helper" >/dev/null; else cp "Tools/$helper" "$tmp/"; fi; done < <(bun -e 'const m=await Bun.file(process.argv[1]).json(); for(const f of [...(m.runtime?.initial||[]),...(m.runtime?.lazy||[])]) console.log(f)' "$manifest")
cp Tools/browser-index.html "$tmp/index.html"; bun Tools/generate-icon-asset.js --manifest "$manifest" --output "$tmp/icon-adapter.js"; if [[ -f "$tmp/icon-adapter.js" ]]; then bun build "$tmp/icon-adapter.js" --minify --outfile="$tmp/icon-adapter.min.js" >/dev/null && mv "$tmp/icon-adapter.min.js" "$tmp/icon-adapter.js"; fi; bun Tools/rewrite-release-index.js --index "$tmp/index.html" --manifest "$manifest"
# Embedded owns bootstrap directly, so browser-index imports index.js/init.
bun Tools/patch-browser-index.mjs embedded-bootstrap "$tmp/index.html"
bun Tools/build-styles.mjs "$tmp/styles.css"
# Drops the framework's optional-feature rules (maps, charts, canvas, ...) the
# manifest proves unused; it is a no-op when the app builds CSS classes dynamically.
[[ "$configuration" != release ]] || bun Tools/prune-release-css.js --css "$tmp/styles.css" --manifest "$manifest" >/dev/null
# An unchanged module skips the strip and Binaryen: the earlier result is reused (SWIFTUIWEB_WASM_STRIP_CACHE=0 turns it off).
if [[ "${SWIFTUIWEB_WASM_STRIP_CACHE:-1}" == 1 ]]; then export WASM_STRIP_CACHE_DIR="${SWIFTUIWEB_DEV_CACHE:-$BUILD_ROOT}/wasm-strip-cache"; else unset WASM_STRIP_CACHE_DIR; fi
[[ "$configuration" != release ]] || { [[ -n "${SWIFTUIWEB_KEEP_WASM_NAMES:-}" ]] && cp "$tmp/app.wasm" "${SWIFTUIWEB_KEEP_WASM_NAMES}"; WASM_SIZE_REPORT=0 WASM_OPT_ONE_CALLER_INLINE_MAX_SIZE="${WASM_OPT_ONE_CALLER_INLINE_MAX_SIZE:-256}" Tools/strip-wasm-release.sh "$tmp/app.wasm" "$tmp/app.wasm"; }
[[ -n "$sync_workspace" ]] || rm -rf "$workspace"; [[ -n "${SWIFTUIWEB_DEV_CACHE:-}" ]] || rm -rf "$scratch"
[[ -z "$framework_workspace" ]] || rm -rf "$framework_workspace"
restore_external_sources
# The build's logs and staging copy do not ship with the bundle: the logs go next to the bundles
# (.build/browser-logs/<product>), the staging copy goes.
build_logs="$BUILD_ROOT/browser-logs/$product"; rm -rf "$build_logs"; mkdir -p "$build_logs"
for build_log in swift-build.log concurrency-warnings.log sync-changes.txt; do
  [[ ! -f "$tmp/$build_log" ]] || mv "$tmp/$build_log" "$build_logs/"
done
rm -rf "$tmp/staging"
final_tmp="$tmp"
final="$BUNDLE_ROOT/$product"; rm -rf "$final"; mkdir -p "$(dirname "$final")"; mv "$tmp" "$final"; trap - EXIT
# The manifest this bundle was made from (read by the app.wasm-only path above).
[[ -z "${SWIFTUIWEB_DEV_CACHE:-}" ]] || sed "s|${final_tmp##*/}|.embedded-browser|g" "$manifest" > "$bundle_manifest"
# Consumer packages can keep browser-only static files in a package-level
# Resources directory. SwiftPM's native resource bundle is not available to
# the Embedded browser product, so copy those files next to the generated
# index/WASM bundle where relative Image/URL sources can resolve them.
# The directory is SWIFTUIWEB_RESOURCES when set, else `Web/Resources` (next to
# the browser target), else `Resources`. Symbolic links are followed, so a
# file shared with another target (fonts) can live in one place.
# The local packages the consumer depends on can ship browser files of their own in `Web/Resources/` (the script of a
# page service, a JavaScript SDK): they are copied first, and their head.html fragments go before the application's
# (Tools/package-web-resources.mjs), so an application never keeps copies of a library's files.
[[ "$EXTERNAL_PACKAGE" != 1 ]] || bun "$ROOT/Tools/package-web-resources.mjs" "$PACKAGE_ROOT" "$final"
if [[ "$EXTERNAL_PACKAGE" == 1 ]]; then
  resources_dir="${SWIFTUIWEB_RESOURCES:-}"
  if [[ -z "$resources_dir" ]]; then
    for candidate in "$PACKAGE_ROOT/Web/Resources" "$PACKAGE_ROOT/Resources"; do
      [[ -d "$candidate" ]] && { resources_dir="$candidate"; break; }
    done
  fi
  if [[ -n "$resources_dir" && -d "$resources_dir" ]]; then
    # Links are followed (shared fonts), but a link leaving the package would copy files from outside it into the bundle.
    package_real="$(cd "$PACKAGE_ROOT" && pwd -P)"
    # Every entry the copy will read, links followed at any depth (a link inside a linked folder too), must resolve inside
    # the package.
    # A part the walk cannot read (a loop, a permission) stops the build: it would otherwise go unchecked and be copied.
    resource_list="$(mktemp)"
    if ! find -L "$resources_dir" -print0 > "$resource_list"; then
      rm -f "$resource_list"
      echo "error: could not check every resource under $resources_dir (a link loop or an unreadable folder)" >&2
      exit 1
    fi
    while IFS= read -r -d '' resource_entry; do
      resource_target="$(realpath "$resource_entry" 2>/dev/null || true)"
      case "$resource_target" in
        "$package_real"|"$package_real"/*) ;;
        *) rm -f "$resource_list"; echo "error: $resource_entry points outside the package (${resource_target:-a missing file}); resources may only link inside $package_real" >&2; exit 1 ;;
      esac
    done < "$resource_list"
    rm -f "$resource_list"
    cp -RL "$resources_dir/." "$final/"
  fi
fi
if [[ -f "$final/.package-head.html" ]]; then
  { cat "$final/.package-head.html"; [[ ! -f "$final/head.html" ]] || cat "$final/head.html"; } > "$final/.head.html.merged"
  mv "$final/.head.html.merged" "$final/head.html"
  rm -f "$final/.package-head.html"
fi
# Application document-head hook: Resources/head.html is inserted into
# <head> after styles.css and Resources/app.css is linked after it, so web
# fonts, <meta> configuration and app tokens load without Swift branches.
# Asset-catalog colors (`*.xcassets/*.colorset`) become CSS custom properties,
# so `Color("Name")` resolves the same way it does in a native app, and image
# sets are copied into catalog-assets/ with a manifest the runtime hands
# to Swift as a WASI environment entry, so `Image("Name")` resolves too.
[[ "$EXTERNAL_PACKAGE" != 1 ]] || bun "$ROOT/Tools/compile-assets.mjs" "$PACKAGE_ROOT" "$final/catalog-assets.css" "$final"
bun "$ROOT/Tools/inject-app-head.mjs" "$final"
if [[ "$product" == ShowcaseApp ]]; then cp Tools/showcase.css "$final/showcase.css"; bun build Tools/showcase-host.js --target=browser --format=esm --minify --outfile="$final/showcase-host.js"; bun Tools/patch-browser-index.mjs showcase-host "$final/index.html"
fi
# The resize rule names the elements whose stylesheets declare a transition, so it is written once every stylesheet of the
# bundle (the framework's and the application's) is in place, and before a release renames the files.
bun "$ROOT/Tools/scope-resize-transitions.mjs" "$final"
# Split app.wasm (see wasm_split above): the functions the first screen runs stay in app.wasm, the rest go to app-rest.wasm,
# which downloads behind the first screen (Tools/wasm-split-release.mjs, Tools/wasm-split-loader.js). It runs the bundle in
# headless Chromium, so it comes once every file is in place, and before the files get their hashed names. A split whose
# inputs did not change is reused from the cache (SWIFTUIWEB_WASM_SPLIT_CACHE=0 turns it off) and runs no browser.
# By default a split that fails leaves one app.wasm with a warning. SWIFTUIWEB_WASM_SPLIT_ROUTE (default /),
# SWIFTUIWEB_WASM_SPLIT_VIEWPORTS (default 1280x800,390x844).
if [[ "$wasm_split" != off ]]; then
  split_args=(--route "${SWIFTUIWEB_WASM_SPLIT_ROUTE:-/}" --viewports "${SWIFTUIWEB_WASM_SPLIT_VIEWPORTS:-1280x800,390x844}" --log-dir "$build_logs")
  [[ "$wasm_split" != auto ]] || split_args+=(--fallback)
  [[ "${SWIFTUIWEB_WASM_SPLIT_CACHE:-1}" != 1 ]] || split_args+=(--cache-dir "$BUILD_ROOT/wasm-split-cache")
  split_status=0; bun "$ROOT/Tools/wasm-split-release.mjs" "$final" "${split_args[@]}" || split_status=$?
  # 3: the split fell back to one app.wasm. The runtime scripts were built with the split loader, which on the main thread
  # requests app-rest.wasm before it knows the module is not split, so they are built again without it.
  if [[ "$split_status" == 3 ]]; then bun "$ROOT/Tools/build-runtime-bundle.mjs" --outdir "$final" --manifest "$manifest"; elif [[ "$split_status" != 0 ]]; then exit "$split_status"; fi
fi
# A release names each framework file by its content (`app.3f9a1c2e.wasm`), so the server can cache it for a year;
# index.html keeps its name and is revalidated. Every reference is rewritten (Tools/hash-release-bundle.mjs). It runs
# before the CSP is sealed, because the inline bootstrap changes when its import is renamed.
[[ "$configuration" != release ]] || bun "$ROOT/Tools/hash-release-bundle.mjs" "$final"
# Content-Security-Policy: hash the final inline scripts. No bundle gets 'unsafe-eval'; DOM components are registered
# functions from the application's own files (Documentation/BROWSER_APP_SHELL.md).
bun "$ROOT/Tools/seal-csp.mjs" "$final"
# First paint (opt-in, release): the first screen as markup and styles in index.html, captured from this very bundle in headless
# Chromium and verified against what the runtime then shows; the build fails if they differ (Documentation/Architecture/FIRST_PAINT.md).
# After the seal (it needs a working page and adds one hash to the policy) and before the precompressed copies.
# SWIFTUIWEB_FIRST_PAINT_ROUTE (default /), SWIFTUIWEB_FIRST_PAINT_VIEWPORT (WIDTHxHEIGHT, default 1280x1200),
# SWIFTUIWEB_FIRST_PAINT_VERIFY=0 skips the comparison (never for shipping).
if [[ "${SWIFTUIWEB_FIRST_PAINT:-0}" == 1 ]]; then
  [[ "$configuration" == release ]] || { echo "SWIFTUIWEB_FIRST_PAINT=1 needs CONFIGURATION=release" >&2; exit 2; }
  first_paint_args=(build "$final" --route "${SWIFTUIWEB_FIRST_PAINT_ROUTE:-/}" --viewport "${SWIFTUIWEB_FIRST_PAINT_VIEWPORT:-1280x1200}")
  [[ "${SWIFTUIWEB_FIRST_PAINT_VERIFY:-1}" == 0 ]] && first_paint_args+=(--no-verify)
  bun "$ROOT/Tools/first-paint.mjs" "${first_paint_args[@]}"
fi
# Precompressed copies (`.br`, `.gz`) of the final bytes, after the CSP is sealed; Tools/bun-server.ts sends them to
# clients that accept the coding (Tools/precompress-bundle.mjs).
[[ "$configuration" != release ]] || bun "$ROOT/Tools/precompress-bundle.mjs" "$final"
[[ -z "$reuse_key" ]] || bun "$ROOT/Tools/bundle-reuse.mjs" stamp "$final" "$reuse_key"
echo "Bundle ready: $final"
[[ "${BUILD_ONLY:-0}" == 1 ]] && exit 0
if [[ -n "${PORT:-}" ]]; then
  # An explicitly supplied port is an intentional contract. Let Bun report a
  # clear EADDRINUSE error instead of silently serving on another port.
  port="$PORT"
else
  port=8080
  while (( port < 65535 )) && lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; do
    port=$((port + 1))
  done
  if (( port >= 65535 )); then
    echo "No free localhost port was found for SwiftUIWeb." >&2
    exit 1
  fi
  if [[ "$port" != 8080 ]]; then
    echo "Port 8080 is busy; using localhost port $port." >&2
  fi
fi
if [[ "${SWIFTUIWEB_OPEN_BROWSER:-0}" == 1 ]] && command -v open >/dev/null 2>&1; then
  # Give Bun a moment to bind the socket before asking macOS to load the page.
  # This is opt-in so the lower-level plugin/launcher remains usable in CI.
  (sleep 0.25; open "http://127.0.0.1:${port}") >/dev/null 2>&1 &
fi
# An example that calls a jsonplaceholder-shaped API (it has an `Examples/<Product>/.mock-api` marker, or SWIFTUIWEB_MOCK_API=1) gets one on
# this machine, and the dev server forwards `/api` to it: the app calls `/api/posts` on its own origin. `API=real` answers the data routes
# from jsonplaceholder.typicode.com instead (the pictures stay local); SWIFTUIWEB_MOCK_API=0 starts none. See Tools/mock-jsonplaceholder.mjs.
if [[ "${SWIFTUIWEB_MOCK_API:-}" != 0 ]] && { [[ "${SWIFTUIWEB_MOCK_API:-}" == 1 ]] || [[ -f "$ROOT/Examples/$product/.mock-api" ]]; }; then
  mock_port=8090
  # Never the port the dev server is about to take: it is not listening yet, so lsof would not show it.
  while (( mock_port < 65535 )) && { (( mock_port == port )) || lsof -nP -iTCP:"$mock_port" -sTCP:LISTEN >/dev/null 2>&1; }; do mock_port=$((mock_port + 1)); done
  mock_args=(--port "$mock_port" --persist)
  [[ -z "${MOCK_API_DELAY:-}" ]] || mock_args+=(--delay "$MOCK_API_DELAY")
  [[ "${API:-}" != real ]] || mock_args+=(--upstream https://jsonplaceholder.typicode.com)
  bun Tools/mock-jsonplaceholder.mjs "${mock_args[@]}" &
  mock_pid=$!
  export SWIFTUIWEB_API_ORIGIN="http://127.0.0.1:$mock_port" SWIFTUIWEB_API_PATH=/api
fi
PORT="$port" bun Tools/bun-server.ts "$final" "$port" &
server_pid=$!
set +e
wait "$server_pid"
server_exit=$?
set -e
exit "$server_exit"
