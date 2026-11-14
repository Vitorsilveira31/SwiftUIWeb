# Build time

This page describes how long the Showcase takes to build, which build profiles and development loops exist, what each one
does, and how to measure them. The numbers were taken on an Apple Silicon Mac with 18 cores and Swift 6.4.0, with other
work running on the machine, so they carry a spread. Read the differences between rows, not the absolute values. Instruction
counts (`-stats-output-dir`) do not depend on load and are the better comparison when two builds differ by a few percent.

The build of a single application is the same pipeline in every profile: the lowering (`Tools/SwiftUIWebLowering`, a Swift
package that rewrites the sources for the browser), `swift build`, and the bundle steps (JavaScript, CSS, the index page, the
content security policy, and the optimizer that runs on `app.wasm`). `Tools/run-browser-embedded.sh` drives the pipeline.

## Build times of a release and a debug build

| Scenario | `swift build` | whole pipeline |
|---|---|---|
| release, empty scratch | 72 to 84 s | 77 to 90 s |
| release, `SWIFTUIWEB_DEV_CACHE`, nothing changed | 2 s | 5 s |
| release, cache, one app file edited | about 50 s | about 56 s |
| debug, empty scratch | 28 to 35 s | 31 to 38 s |
| debug, cache, nothing changed | 1.6 s | 4.8 s |
| debug, cache, one app file edited | 16 to 24 s | 19 to 28 s |
| debug, cache, one `SwiftUIWebCore` file edited (even a comment) | 36 to 45 s | 40 to 48 s |
| debug, cache, a comment in Fiber or Networking | 3 s | 6 s |

- `swift build` is 90 to 93 % of a release or debug pipeline. The lowering takes 1 to 2 s per package, Binaryen (the release
  optimizer) 2 to 4 s, and the JavaScript and CSS steps 6 to 8 s in release and 3 to 4 s in debug.
- The first build on a machine compiles swift-syntax for the lowerer once: about 120 s with the SwiftPM cache warm. After that
  an edit to the lowerer takes about 10 s to rebuild it, and a run with nothing changed takes about 15 ms to find that out.
- An Embedded application build uses one `swift-frontend` process for most of its time, so it uses about 1.1 of the 18 cores.
  The application module specializes the serialized SIL of every library, which is most of its time. A non-Embedded build of the
  same library does more total work but spreads it over processes.
- Things that do not change the time: `-j`, type-checker annotations (the slowest body of the Showcase is about 1 s), warnings,
  and the module list (SwiftPM builds the 19 modules the Showcase needs).
- `SwiftUIWebCore` changes trigger the most work. An edit that adds or removes lines moves the source locations of the later
  functions in the file; see "The development loop".

### Release profiles

`SWIFTUIWEB_RELEASE_PROFILE` (or `--release-profile`) chooses how the release build optimizes. Measured on the Showcase with
`swift build`, interleaved runs:

| Profile | `swift build` time |
|---|---|
| `size` (default) | 67 to 79 s |
| `balanced` (framework libraries `-Onone`, application `-Osize`) | 61 to 74 s |
| `fast` (`-Onone` everywhere, then `wasm-opt -Oz`) | 27 to 33 s |

`balanced` changes only the libraries, so an application module keeps `-Osize`. Both `size` and `balanced` bundles pass
`Tools/test-showcase-live.mjs`. The size each profile produces is in [`WASM_SIZE.md`](WASM_SIZE.md); In the same measurement, `balanced` gave a release `app.wasm` 4.6 % larger than `size`, and `fast` 143 % larger.

Two release settings that are not the default: `SWIFTUIWEB_WASM_OPTIMIZATION=-O` instead of `-Osize` is 19 % slower to build and 24 % larger, and `WASM_OPT=0` skips the optimizer, which leaves the build time about the same and
makes `app.wasm` about 38 % larger.

### Skipped work in a release build

- `Tools/strip-wasm-release.sh` keeps its result for each input in `<dev cache or build root>/wasm-strip-cache`, and reuses it
  for an unchanged module. A "nothing changed" release run takes about 5 s instead of 7 s.
- The watcher runs the toolchain report only for its first build.
- CI restores the lowerer's build folder (`.github/actions/cache-lowering-tool`) instead of compiling swift-syntax in each job.

## Measuring

- A single build: `Tools/run-browser.sh showcase` with `BUILD_ONLY=1 CONFIGURATION=release` (or `debug`), timing each stage.
- Instruction and object counts per module: add `SWIFTUIWEB_EXTRA_BUILD_FLAGS="-Xswiftc -stats-output-dir -Xswiftc <dir>"`.
  Read `Frontend.WallClockMicroseconds` and `Frontend.NumInstructionsExecuted` from the JSON files in that directory.
- Slow function bodies: `-Xswiftc -Xfrontend -Xswiftc -warn-long-function-bodies=25` reports them as warnings.
- Saves in a development loop: `Tools/dev-watch.mjs` runs the watcher. For a comparison, alternate the two sides in rounds
  (each round builds both, with the order changing) and take the median, because a single run on a shared machine can be off by
  a factor of two.

## The development loop

The development loop is the watcher's cycle: save a file, rebuild, and reload the page. The Embedded profile is what ships, so
these numbers are for its debug build. The loop has these parts.

- **Cached lowering.** Each file's lowering result is kept, keyed by the lowerer binary, the options, the `@Observable` and
  generic type names, and the text. Misses are lowered in parallel. For a framework product the cached tree is updated in place,
  touching only the files whose bytes change. The lowering costs 0.4 to 0.7 s per save.
- **Stable source locations.** The serialized SIL of generic code and of functions that return `some` carries absolute line
  numbers. The `stable-source-locations` pass gives each declaration line 1 of a virtual file
  (`#sourceLocation(file: "<path>|<declaration>", line: 1)`), so adding a line in one function does not change the module.
  The report maps each virtual file back to its line, and the watcher rewrites compiler errors to `<path>:<line>:<column>`.
- **Exported interfaces.** The lowering marks the non-generic framework functions `@export(interface)`
  (`Tools/SwiftUIWebLowering/Sources/LoweringCore/ExportInterface.swift`), and the libraries are built with `DeferredCodeGen`.
  Each library compiles those functions once and keeps their bodies out of the `.swiftmodule`, so editing one leaves the module
  byte-identical and the application only relinks. What the application still compiles is its own code and the generic framework
  code specialized for its types.
- **Thin generics.** Embedded Swift compiles a generic function once per concrete type, in the module that uses it. The framework
  keeps in generic functions only the code that depends on their parameters. The view memo holds the `_ViewRenderer<V>` that renders
  the view, so the memo lookup is one generic class instead of a copy per view type. `ModifiedContent` renders over its modifier
  alone, and the non-generic parts of `TabView`, the button, the shapes and the state store are out of their generic types. The
  application module's debug instructions for the Showcase fell from 208 G to 156 G (-25 %) and its objects from 11.75 MB to 8.56 MB.
- **Stylesheet and no-op saves.** A stylesheet-only save never builds: `Tools/dev-refresh-styles.mjs` updates the bundle's
  stylesheets. A save whose lowered tree changed nothing skips `swift build` when a stamp shows that the last build had the same
  compiler, SDK, arguments and manifest environment.
- **Debug LLVM.** The debug loop passes `-disable-llvm-verify`, which removes about 0.8 s of LLVM work from the application module.
- **Application libraries.** An application that has library targets (such as `Examples/UniversalApp`, with `Shared` and an
  executable) gets the same `DeferredCodeGen` and `@export(interface)` treatment there. Recompiling `Shared` fell from 40.2 G to
  23.2 G instructions, and an edit inside a `Shared` function does not recompile the executable.
- **Module determinism.** Two compiles of the same sources must produce the same module bytes, or every dependent rebuilds. Embedded
  Swift serialization once ordered the specializations of closures passed to `withUnsafePointer(to:)` from generic functions
  differently between compiles. The framework does not pass such closures, and `make module-determinism-test` compiles every library
  module repeatedly and fails when one varies. When a module varies, `Tools/test-module-determinism.mjs --keep` keeps the first build's
  modules for inspection.

Measured on the Showcase, debug, with the watcher's second and later builds (`Tools/dev-watch.mjs` with `SWIFTUIWEB_DEV_CACHE`), the
median of five interleaved rounds:

| Save | Without the loop work | With it |
|---|---|---|
| nothing changed | 6.1 s | 1.5 s |
| a stylesheet only | 5.7 s | 0.1 s |
| one app file | 24.6 s | 15.5 s |
| two lines added in a non-generic `SwiftUIWebCore` function | 48.1 s | 13.6 s |
| a comment at the end of a `SwiftUIWebCore` file | 47.4 s | 14.3 s |

Thin generics (below) reduce an app-file save further: the whole save falls from 22.9 s to 17.2 s (median of six
interleaved rounds, the machine loaded), and the application module's wall time from 15.9 s to 10.9 s. Those two rows are for the
Embedded profile; the `fast` profile below is quicker for application code.

In the Embedded profile, a line added to a generic function on the render path still costs about 36 s per save, against about
6 s in the `fast` profile (see "The development profile").

Known limits: the library `SwiftUIWebCore` is one module of about 40,000 lines, so an edit to it is compiled as a whole; the
application module still compiles the framework's generic code for its own types.

## The development profile

`SWIFTUIWEB_DEV_PROFILE=fast` (or `--dev-profile fast`) is available in debug builds only. The watcher uses it by default and builds `embedded` when the regular SDK is missing. It
compiles the lowered tree as full Swift with the toolchain's regular WebAssembly SDK (`swift-6.4.0-RELEASE_wasm`), where the compiler
works per file and a library keeps its own code. The unit of a rebuild is therefore the edited file, not the whole application module.

What the profile changes (`Tools/run-browser-embedded.sh`, `Package.swift`):

- The lowering runs `embedded-feature-condition` (`--full-swift`), which makes `hasFeature(Embedded)` true in every `#if` and
  `#elseif`. Those conditions select the browser product's code (the exports, BrowserIO, serialization without reflection). Nothing
  else in the sources differs between the two profiles.
- `Package.swift` reads `SWIFTUIWEB_FULL_SWIFT=1` and leaves out `-enable-experimental-feature Embedded`,
  `-whole-module-optimization`, the empty-object-file and `DeferredCodeGen` model, and the Embedded Unicode tables.
  `SWIFTUIWEB_EMBEDDED=1` stays set, so the package and consumer manifests are still the browser ones.
- There are no `@export(interface)` markers and no stable source locations: both exist for the Embedded module model.
- `-Wwarning EmbeddedRestrictions` is set in every target, so code that Embedded Swift refuses is reported while developing.
- The module links with the same reactor model, stack size and `--export` list. It has the same 43 exports and 8 `browser_io` imports,
  and 17 WASI imports instead of 9. The host builds its WASI shim from the module's import list, so the host bundle is the same.

Showcase, debug, median of three interleaved rounds (each edit is built by both profiles, the order alternating), the whole launcher
run in seconds:

| Save | `embedded` | `fast` |
|---|---|---|
| first build (lowerer already built) | 33 | 11 |
| nothing changed | 2.4 | 2.1 |
| app file, a string in a body | 11.5 | 3.7 |
| Core, lines added to a non-generic function (`_RenderContext._modifierStateKey`) | 11.3 | 5.3 |
| Core, lines added to a generic function on the render path (`_ModifierBoundary._renderOwnerBoundary`) | 35.7 | 6.3 |

The costs of the profile, against the Embedded build of the same code:

- debug `app.wasm`: 28.9 MB against 22.5 MB for the Showcase, and 26.2 MB against 10.5 MB for the Motion app;
- mount in Chromium: 245 ms against 216 ms;
- a state change that renders the Motion root again (120 clicks, median of four interleaved rounds): 20.0 ms against 13.0 ms.

So the profile is for development. Measure performance and size with the Embedded build; a release is always Embedded Swift, and
`--dev-profile fast` with `--configuration release` is refused. Embedded Swift still decides what compiles: full Swift accepts code
that Embedded Swift refuses, so the Embedded build (the default profile, a release, and CI) remains the check.

&The artifact bundle that installs the Embedded SDK installs it too.
`make doctor` with `SWIFTUIWEB_DEV_PROFILE=fast` reports whether it is present.

WebKit: WebKit 26.0 (the engine of older Playwright builds) crashes on the first event after mount, in the worker and on the main thread,
in code of the optimizing WebAssembly tier. The same page runs with `__XPC_JSC_useOMGJIT=0`. Safari 27.0 runs the profile. The profile's
suites run on Chromium, and an Embedded bundle is the one to open in an older Safari.

Validation: `make dev-profile-test` runs the motion, showcase and identity suites on `fast` bundles in Chromium.

## The direct build

In the profile `fast`, an application-file save spends 1.2 to 1.3 s in `swift build` with nothing to do (SwiftPM planning), and about
0.55 s on the work: the driver call of the application module (0.25 s) and the link (0.30 s). `Tools/dev-direct-build.mjs` does only the
work, and `SWIFTUIWEB_DIRECT_BUILD=0` turns it off.

The launcher runs the first build of a development cache with `-v`, and records from its output each module's `builtin-SwiftDriver`
command, the `builtin-copy` lines that publish each module's interface next to the products, and the link command. On a save the direct
build:

- finds the Swift sources newer than the last build. It hands the save back to `swift build` when a file was added or removed, when the
  lowering changed files other than Swift sources (a manifest, a C source, a flag), when the launcher's fingerprint of the build differs,
  or when a module it must compile was not seen compiling before;
- runs the driver command of each changed module, in dependency order, the independent ones in parallel. The driver's incremental mode
  recompiles only the changed files;
- refreshes the copies the link reads (`<Products>/<Module>.objlib`), publishes each module's interface, and marks the modules that import
  it only when the published bytes changed (a function body does not change them; an `@inlinable` body or a new declaration does);
- links.

When every saved file was a Swift source (`SWIFTUIWEB_WATCH_SWIFT_ONLY=1`) and the reachability manifest is the one the bundle was made
from, the launcher replaces `app.wasm` in the bundle and skips the bundle steps, which would write the same files again.

`--build-system native`, which would give an llbuild manifest to run, is deprecated in Swift 6.4 and does not build this package.

Showcase, debug, profile `fast`, the whole launcher run with the toolchain resolved (what the watcher does), median of three interleaved
rounds, in seconds:

| Save | `swift build` | direct build |
|---|---|---|
| nothing changed | 0.95 | 0.95 |
| app file, a string in a body | 2.66 | 1.28 |
| Core, lines added to a non-generic function | 4.55 | 2.53 |
| Core, lines added to a generic function on the render path | 5.52 | 2.85 |

Of the 1.28 s, about 0.55 s is the compiler and the linker, and about 0.6 s is the lowering, which still reads the whole tree to find the
file that changed.

The lowering of an unchanged tree is kept small. A mirrored file is not read when its copy is known to hold its bytes: both regular files
have the same size, the source was not modified after the copy, and the source's status change is older than the copy's
(`FileSystem.unchangedSinceCopied`). A lowered file's report record is kept in the cache (`--cache`) under the lowering's key, and a run
computes only the records of the files that changed. The report is byte for byte the one a run without a cache writes. On the Showcase with
one changed file out of about 2,500, the lowerer alone takes 0.19 s with the cached records (0.56 s without them).

Validation: `make direct-build-test` covers an application edit, a library body, a new public function used by the application, a compile
error, the saves that are handed back to `swift build`, and a save through the launcher.

## Hot swap

`SWIFTUIWEB_HOT_SWAP=1`, on top of the direct build, links the product as two modules, so that an application save only links the
application.

- **main** (`<cache>/hot/main.wasm`, which the bundle's `app.wasm` replaces): the product's link without the application's objects, without
  `--gc-sections` and without the application's `--export=` list. It uses `--export-all`, an exported growable table and
  `--allow-undefined` (the framework calls `browser_io_receive`, which the application defines), and it links the whole standard runtime
  libraries (`--whole-archive`), because a side module may use any symbol. For the Showcase it is 37 MB with about 87,000 exports.
- **side** (`<cache>/hot/side.wasm`, which the bundle's `app-side.wasm` replaces): the application module, compiled with
  `-Xllvm -relocation-model=pic` and linked with `wasm-ld --shared --experimental-pic --emit-relocs`. For the Showcase it is 3 MB and
  imports 1,230 symbols, all of which the main module exports.

`Tools/side-module.js` loads the side module into the running main module. It takes memory from the main module's allocator and table
slots from the `dylink.0` section; it resolves `GOT.mem` and `GOT.func` from the main module's exports, and the side module's own symbols
after it is instantiated; it runs `__wasm_apply_data_relocs`; it writes the linker's own bytes back over every `R_WASM_MEMORY_ADDR_LOCREL_I32`
field of `reloc.DATA`, because Swift's metadata is made of differences of addresses within the module, and a generic type found by its
mangled name traps without this; it registers the side module's protocol, conformance and type-metadata sections with the Swift runtime;
then it runs the side module's constructors.

The main module's static initializers seed hashing from `/dev/urandom`, which the page's WASI layer does not provide, so a hot build sets
`SWIFT_DETERMINISTIC_HASHING=1`.

Showcase, debug, a machine under load, so compare the differences:

| | ordinary bundle | hot bundle |
|---|---|---|
| link after an application save | 0.30 s (whole product) | 0.03 s (side module) |
| a save of an application file, whole launcher run, median of three interleaved | 1.40 s | 1.16 s |
| the page, from the end of the build to the application mounted | 160 ms (reload) | 143 ms (swap) |
| a framework save, the page loads again | 160 ms | 336 ms |

The swap is not faster than a reload in Chromium, which keeps the compiled module of the page it reloads. What a hot build saves is the
link, and the page keeps its state. A framework save costs more than an ordinary one. Not covered: the worker, freeing replaced modules,
and an application whose own library targets change (they are in the main module).
