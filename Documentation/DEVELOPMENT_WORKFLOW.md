# Development workflow

SwiftUIWeb has one browser build path: Embedded Swift/WASM, the JavaScript
host, and BrowserIO. Native SwiftPM tests validate the public API and semantics; they
are not a second browser runtime.

## What the build needs

`make doctor` (or `Tools/toolchain-report.sh`) lists every tool the Embedded browser build needs and does not
find, each with the command that installs it, and installs nothing. The build entry point
(`Tools/run-browser-embedded.sh`, so also `make run`, the launcher and the SwiftPM plugin) runs the same
check first and stops with the full list instead of failing on the first missing tool. Required today: a Swift
6.4+ compiler and the Embedded WebAssembly SDK built for that exact toolchain, and `bun`. `wasm-opt` (Binaryen) is optional and shrinks
release bundles. `SWIFTUIWEB_SKIP_TOOLCHAIN_REPORT=1` turns the check off.

## Hot reload: save a file, the page updates

```sh
make watch                                                   # the project site
./swiftweb dev                                               # your app (swift package web init writes the script)
swift ../SwiftUIWeb/Tools/swiftuiweb-run.swift --path . --product MyApp --watch   # the same, spelled out
```

It builds once, serves the app, and watches the package and the framework sources. When you save, it rebuilds what
changed and tells every open page to reload; the URL is kept, so the page comes back on the same screen.

- **It watches files, not an editor.** Xcode, VS Code or anything else works: the loop starts from the file landing on
  disk. Xcode does not build this WebAssembly product itself, so keep the terminal running next to it.
- **Swift edits** rebuild only the modules that changed. The lowered sources and SwiftPM's scratch folder live in
  `.build/dev-cache/<product>-<configuration>` between runs, and only files whose bytes changed are rewritten, so their
  modification times survive and the compiler skips the rest. Measured on the Showcase, debug, M5 Pro (median of an
  interleaved A/B, [`Performance/BUILD_TIME.md`](Performance/BUILD_TIME.md)): 1.5 s when nothing changed, 0.1 s for a
  stylesheet-only save, 15.5 s after editing an app file, 13.6 s after adding lines to a non-generic framework function.
- **What keeps a save short** (all of it debug and development loop only; release builds are unchanged):
  - a save that changes only stylesheets refreshes them in the bundle without a build (`Tools/dev-refresh-styles.mjs`;
    `SWIFTUIWEB_WATCH_STYLES_FAST_PATH=0` turns it off), and a save that changes nothing the build reads skips
    `swift build` (`SWIFTUIWEB_SKIP_UNCHANGED_BUILD=0` always builds);
  - each declaration is lowered at line 1 of its own virtual file (`#sourceLocation(file: "<path>|<declaration>",
    line: 1)`), so adding a line in one function does not move the serialized locations of the others and the module
    does not change; compiler errors are rewritten back to `<path>:<line>` (`SWIFTUIWEB_STABLE_SOURCE_LOCATIONS=0` turns
    it off; `#file`/`#line` in lowered code see the virtual file in this loop);
  - an application's own library targets get the same model as the framework's (DeferredCodeGen and
    `@export(interface)`), so an edit inside a library function relinks the executable without recompiling it
    (`SWIFTUIWEB_CONSUMER_CODEGEN=0` turns it off);
  - the LLVM IR verifier is skipped;
  - the lowering keeps each file's result in the cache and lowers the others in parallel (`SWIFTUIWEB_LOWERING_CACHE=0`
    turns the cache off), and for a framework product it writes straight into the cached tree instead of copying the
    repository (`SWIFTUIWEB_SYNC_WORKSPACE=0` goes back to copy and `Tools/sync-tree.mjs`);
  - the watcher resolves the compiler and the Embedded SDK on its first build and reuses them;
  - the framework's non-generic functions are marked `@export(interface)` by the lowering and the libraries are built
    with DeferredCodeGen, so each library compiles that code once, the app stops recompiling it on every save, and an edit
    inside such a function relinks the app without recompiling it (`SWIFTUIWEB_EXPORT_INTERFACE=0` turns it off);
  - no index store is written for the cached scratch folder.
- **CSS-only saves** swap the stylesheets in place without reloading the page.
- **A failed build** leaves the last good bundle running and shows the compiler errors over the page; the next good
  save clears them.
- **A save that only changes literal values shows at once, with the state kept.** Change the text of a label, a padding, a
  duration or a boolean inside a view body, a function or a closure and the open pages render again with the new value in
  milliseconds; the build runs behind them and does not reload. In a debug loop the lowering wraps those literals of
  application files in `_live(id, literal)`, the watcher compares the saved file with the one the pages have
  (`swiftuiweb-lowering --literal-diff`), and when only literal values differ it sends them to the page. Anything else
  (a new modifier, an interpolation, a literal outside a body, a hexadecimal number, a stored property's default) builds
  as before. A literal the page cannot replace (one whose type is the application's own, or an
  `AttributedString` or `Decimal`) makes the page reload when the build ends, and so does a literal written directly in the
  `App`'s `body` (outside a view's `body`: the scene is built once at launch and kept), as does a page that was opened while that build
  was running and missed the replacement. `SWIFTUIWEB_LIVE_LITERALS=0` turns it off; a release never has it.
- **Plain state is kept across a rebuild.** The app is a new WebAssembly module, so the page reloads; before it does, a
  debug page writes the values of its `@State` properties to the session's storage and the new module starts from them.
  It keeps booleans, `Int`, `Double`, `String`, and optionals and arrays of them. A state of another type (a struct, an
  enum, an `@Observable` object), a state whose view moved in the hierarchy, and a state whose type changed start from
  their initial value; so does every state on a reload you ask for yourself. A state whose *initial value* you just
  edited keeps the value it had: reload the page to see the new one. `SWIFTUIWEB_STATE_RELOAD=0` turns it off; a release
  has none of it. The route is kept because the app restores it from the URL.
- **No WebAssembly runtime such as wasmtime is involved.** The app runs in the browser's own engine; the watcher only
  rebuilds the bundle and the dev server tells the page to reload (`Tools/dev-watch.mjs`, `Tools/live-reload.mjs`, a
  server-sent-events stream that exists only when the watcher starts the server).
- Debug builds only by default (`--configuration release` is allowed but slower to iterate on), `--port N` picks the
  port, `SWIFTUIWEB_OPEN_BROWSER=1` opens it on macOS.

## Development profile: `fast`

```sh
make watch                                  # the debug loop uses the profile fast
SWIFTUIWEB_DEV_PROFILE=embedded make watch  # the loop on the module that ships
swift ../SwiftUIWeb/Tools/swiftuiweb-run.swift --path . --product MyApp --watch --dev-profile embedded
```

A debug build has two profiles. `embedded` compiles what ships: Embedded Swift, where the compiler always works on a
whole module, so one edited file recompiles its module and the application. `fast` compiles the same lowered sources as
full Swift for regular WebAssembly instead. **The watcher (`--watch`, `make watch`) uses `fast` in debug**;
`--dev-profile` or `SWIFTUIWEB_DEV_PROFILE` chooses, and every other build (`--build-only`, a plain run, the test
targets, a release) is `embedded` unless told otherwise. The compiler then works file by file, and a save
recompiles the files it changed and links. Measured on the Showcase, debug, M5 Pro, median of 3 interleaved rounds
([`Performance/BUILD_TIME.md`](Performance/BUILD_TIME.md)):

| Save | `embedded` (default) | `fast` |
|---|---|---|
| first build | 33 s | 11 s |
| nothing changed | 2.4 s | 2.1 s |
| a string in an app file | 11.5 s | 3.7 s |
| lines added to a non-generic framework function | 11.3 s | 5.3 s |
| lines added to a generic framework function on the render path | 35.7 s | 6.3 s |

- **Saves do not go through `swift build`.** The first build of a loop is a verbose `swift build`, and its compiler
  commands are kept. A save that changes Swift sources of the modules it knows is then compiled by replaying those
  commands: the module that changed, the modules that import it when what it publishes changed, and the link
  (`Tools/dev-direct-build.mjs`). That leaves out the 1.3 s `swift build` spends finding out what changed. A new or
  removed file, a manifest change, a C source or a changed flag is built by `swift build`, which records again.
  `SWIFTUIWEB_DIRECT_BUILD=0` turns it off. Measured on the Showcase (whole save, toolchain resolved, median of three
  interleaved rounds): an app file 2.66 s to 1.28 s, a framework function 4.5 to 5.5 s to 2.5 to 2.9 s.
- **It is the same application.** The lowering makes every `hasFeature(Embedded)` condition true (`--full-swift`), so
  both profiles compile the same code paths, the module has the same exports and imports from the host, and the host
  bundle is the same. `make dev-profile-test` runs the motion, showcase and identity suites on it.
- **It is not what ships.** The module is larger (28.9 MB against 22.5 MB for the Showcase, debug build) and a state change takes
  longer (20.0 ms against 13.0 ms on the Motion app), so do not measure performance or size with it. See [`Performance/BUILD_TIME.md`](Performance/BUILD_TIME.md). A release is always Embedded Swift:
  `--dev-profile fast` with `--configuration release` is refused.
- **Embedded Swift still decides what compiles.** Full Swift accepts code that Embedded Swift refuses. The profile turns
  on the compiler's `EmbeddedRestrictions` warnings in every target, so most such code is reported on the save that wrote
  it; the Embedded build (the default profile, a release, CI) remains the check.
- **It needs the regular WebAssembly SDK** of the toolchain (`swift-<version>-RELEASE_wasm`). The artifact bundle that
  installs the Embedded SDK installs it too, so there is normally nothing to add; `make doctor` with
  `SWIFTUIWEB_DEV_PROFILE=fast` set reports it. A watcher that picked `fast` by default builds `embedded` and says so when
  that SDK is missing; a profile you chose is never replaced.
- **Browsers.** Chromium and Safari 27 run it. WebKit 26.0 as shipped with Playwright crashes in its optimizing
  WebAssembly compiler on this module (it runs with that compiler off), so the automated suites of this profile are
  Chromium only. To develop in a Safari older than 27, run the loop with `--dev-profile embedded`.
- Its cache is `.build/dev-cache/<product>-debug/full-swift`, apart from the Embedded one: switching profiles does not
  rebuild the other.

## Hot swap (experimental)

```sh
SWIFTUIWEB_HOT_SWAP=1 make watch
SWIFTUIWEB_HOT_SWAP=1 ./swiftweb dev
```

With the profile `fast`, the watcher can load an edited application into the page that is already open instead of
reloading it. The build links the product as two WebAssembly modules: a main module with the framework and the standard
library, and the application as a side module that imports what it uses from the main module. A save that changes only
the application compiles it and links the side module (0.03 s instead of the 0.3 s of the whole link); the page loads it
into the module it is running and starts the application again in place. The plain state is kept the way a reload keeps
it; the page itself (its scroll position, anything outside the application's root) does not go away.

- **What it saves.** The link of each application save, and the navigation. Measured on the Showcase under a loaded
  machine: the page shows the edit about 140 ms after the build ends, against about 160 ms for a reload of the ordinary
  bundle, so today the gain is the shorter link and the page that stays, not the time in the page.
- **A framework save reloads.** It changes the main module, which the page cannot replace under itself. The main module
  of a hot build is also larger to load (every symbol is exported and the whole standard library is in it): a reload
  takes about twice as long as with the ordinary bundle.
- **It runs on the main thread.** The worker's host does not load side modules, so a hot build never uses the worker.
  A few behaviours differ between the two (the motion suite has one assertion that only holds in the worker).
- **It rests on parts of the toolchain nobody promises:** position-independent Swift for WebAssembly
  (`-Xllvm -relocation-model=pic`), `wasm-ld --shared`, and a correction the loader makes to what the linker writes
  (`Tools/side-module.js` says which). A product it cannot split is built as one module, as without the option.
- The module an old version of the application lived in is never freed: a long session grows by a few megabytes per swap.

`make hot-swap-browser-test` runs it in a browser.

## Release build time: profiles

A release build of the Showcase is about 75 to 90 s on a laptop, and 90 % of it is the Swift step: the Embedded app
module specializes and optimizes the serialized SIL of every library in one thread (see
[`Performance/BUILD_TIME.md`](Performance/BUILD_TIME.md) for the measurements). `--release-profile` (or
`SWIFTUIWEB_RELEASE_PROFILE`) picks what a release build trades for time:

| Profile | What it does | Showcase `swift build` | `app.wasm` |
|---|---|---|---|
| `size` (default) | `-Osize` everywhere: the shipping build | 72 to 84 s | 3.13 MB |
| `balanced` | framework libraries unoptimized, the app `-Osize` | 5 to 10 % less | about +5 % |
| `fast` | `-Onone` everywhere, Binaryen (`wasm-opt -Oz`) does the optimizing | about 30 s | 7.6 MB |

```sh
SWIFTUIWEB_RELEASE_PROFILE=fast CONFIGURATION=release make run site
swift Tools/swiftuiweb-run.swift --path . --product MyApp --release-profile fast
```

`fast` is for previews and CI jobs that only need a bundle that runs; it is not a shipping build, and the launcher says
so. `SWIFTUIWEB_WASM_OPTIMIZATION=<swiftc flag>` still overrides the optimization level. Debug builds ignore the profile.

An unchanged module also skips the strip and Binaryen steps (2 to 4 s): their result is kept in
`<dev cache or build root>/wasm-strip-cache` and reused when the input bytes, the options and the tools are the same
(`SWIFTUIWEB_WASM_STRIP_CACHE=0` turns it off). The watcher checks the toolchain on its first build only.

## Daily checks

The checks come in three tiers:

```sh
make test           # no browser, about a minute and a half: run it after every edit
make browser-test   # what a pull request must pass: the source lowerer and every real-browser suite, on debug bundles
make nightly-test   # browser-test, the same suites on release bundles, example-test (example apps, CSP, first
                    # paint, consumer packages, the other development profiles), memory, coverage, size, performance
```

`make test` includes deterministic tooling, the Sources/Examples/Tests layout
audit, the public API baseline, and the native Swift suite.

Four things keep them short:

- **Each application compiles once per configuration.** A suite builds its bundle with `BUILD_ONLY=1`, and a build whose
  inputs did not change reuses the bundle already there, or the copy kept from its last build when another configuration
  took the folder since (`Tools/bundle-reuse.mjs`: the sources, the host files, the settings, the toolchain, and a
  bundle nobody edited). Editing a test does not rebuild its application. `SWIFTUIWEB_REUSE_BUNDLE=0` always builds.
- **Pull requests test debug bundles.** An Embedded debug build takes about a third of the time of a release one;
  `release-browser-test` runs the same suites on release bundles every night (`SUITE_CONFIGURATION=release`).
- **Independent suites run at the same time.** `browser-test` first builds the bundles the suites share, then runs them through
  `Tools/run-test-groups.mjs`, which runs groups of targets in parallel (8 at a time); a group holds the targets that write the same bundle folder or development cache. `make test` runs the Swift suite next to the
  JavaScript checks the same way, and `tools-test` and `integrated-check` run their scripts in parallel
  (`Tools/run-scripts.mjs`). `TEST_GROUPS_JOBS=1` and `RUN_SCRIPTS_JOBS=1` run one at a time.
- **The console stays short.** Each target prints one line (pass or fail, and its time); its output is in
  `.build/test-logs/<target>.log`, and the end of the log of a target that failed is printed at the end.

`make plugin-test` exercises the consumer-facing command plugin. The plugin build is intentionally build-only because SwiftPM command plugins cannot bind
localhost without an explicit permission.

The native wrapper keeps Clang and Swift module caches under `.build/` and
honors an explicit `CLANG_MODULE_CACHE_PATH` or `SWIFT_MODULECACHE_PATH`. This
makes the checks reproducible in locked-down CI where user-level caches are
read-only. The plugin harness uses the same local-cache rule; the public plugin
command itself remains the zero-flag build contract documented in the
quickstart.

Use the standalone launcher to run a server:

```sh
SWIFTUIWEB_ROOT=../swiftuiweb \
  swift ../SwiftUIWeb/Tools/swiftuiweb-run.swift \
  --path . --product ShowcaseApp
```

The launcher selects the first free port from 8080 when `--port` is omitted,
reports an occupied explicit port, and forwards Ctrl-C/termination to the
Embedded builder and Bun server. `--build-only` is the CI form.
`--lowering-profile dev` builds the source lowerer in SwiftPM's debug
configuration instead of release, for debugging or editing the lowerer itself; the plugin
forwards the same option (`swift package plugin swiftuiweb --path . --product
ShowcaseApp --lowering-profile dev`).

## Browser tests

The browser suites are Node/bun Playwright scripts (`Tools/test-*.mjs`) on top of
`Tools/browser-test-support.mjs`. Install the browsers once:

```sh
make browser-test-setup
```

Run the whole contract set with `make integrated-check` (it includes the offline
`Tools/test-icon-host.mjs`) or one area at a time, for example `make browser-contract-test`,
`make identity-browser-test` and `make scrolling-browser-test`. The suites that load a built
app take its bundle from an environment variable or argument; the Makefile targets build the
bundle first.

Environment knobs the suites honor:

- `SWIFTUIWEB_BROWSER_ENGINE=chromium|webkit|firefox` picks the engine (default Chromium).
- `CHROMIUM_PATH` points at a Chromium binary when the one Playwright expects is not
  downloaded (a suite that needs WebGL also gets Chromium's software renderer).
- `WEBKIT_PATH` points at a Playwright WebKit launcher (`pw_run.sh`) when the revision the installed
  Playwright expects cannot run on this machine (a WebKit older than the operating system, for example, may fail
  to open a persistent context); a newer revision from the same cache can stand in.
- `make WEBKIT=0 <target>` leaves out the WebKit runs of the browser targets (Chromium still runs);
  CI on Linux sets it.

Playwright for Node evaluates a string passed to `page.evaluate` as an expression, so a string
that is an arrow function is not called; pass a real function. New browser tests belong in
JavaScript run by `bun` (see `AGENTS.md`, "Tooling Languages").

CI (`.github/workflows/ci.yml`) runs these jobs on every pull request and every push to `main`:

- `test`, on macOS: `make test CONFIGURATION=release`.
- `linux`, on Ubuntu: `swift build --build-tests` and `swift test --skip-build`.
- `browser`, on Ubuntu with Chromium: `make architecture-audit` and `make browser-test`.
- `apple`, on macOS: `make webkit-browser-test security-browser-test` and `make universal-app-test`.

The jobs that build WebAssembly install a pinned Binaryen release (`.github/actions/setup-binaryen`), so CI builds,
optimizes and splits `app.wasm` as a release ships it. A pull request keeps only its newest run; a run of `main` is never
cancelled midway, and the nightly and on-demand runs have concurrency groups of their own.

The nightly jobs run on a schedule and on demand:

- `examples`, on Ubuntu: `make release-browser-test example-test`.
- `measurements`, on macOS: coverage (`COVERAGE_BROWSER=1 make coverage`), the Embedded Wasm size report (`make wasm-size-check`, which reports and does not fail)
  and the performance contracts (`make perf-ci`). Their results are uploaded as the `measurements` artifact.

## Size probes

`bun Tools/analyze-wasm-data.js` and `bun Tools/report-wasm-objects.js` show where the initialized data and the object
bytes of a release `app.wasm` come from. No `make` target runs them.

## Debug bundles and DWARF

`CONFIGURATION=debug` browser bundles are linked without DWARF
(`-debug-info-format none` and `-Xlinker --strip-debug`): DWARF was more than
half of a 60 MB `app.wasm` that the browser compiles on every reload. The
`name` section stays, so a trap still shows function names in the console stack
(for example the Swift frames under a trap). On a large app
this takes the debug `app.wasm` from 60.2 MB to 31.3 MB and the
`BUILD_ONLY=1` pipeline from 58.7 s to 52.7 s.

Set `SWIFTUIWEB_WASM_DEBUG_INFO=1` to keep DWARF when you want to step through
Swift in DevTools (with the C/C++ DWARF extension); release builds never carry it.

## Public API and release gates

```sh
make api-diff
make api-availability
make api-diff-update       # only after reviewing an intentional change
```

See [`API/VERSIONING.md`](API/VERSIONING.md) for semantic-versioning and
availability policy. Generated bundles and reports stay under `.build/`.
