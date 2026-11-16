# Split module

A SwiftUIWeb page cannot show its first screen until the whole `app.wasm` has arrived and compiled, although that screen runs
only part of it. A split build moves every function the first screen did not run into a second module, `app-rest.wasm`, which
downloads right after the screen is up. The page waits for fewer bytes before it shows anything; the total grows a little.

It is opt-in and experimental: `SWIFTUIWEB_WASM_SPLIT=1` on a release build. No Swift API changes; an application that does not
ask gets one `app.wasm`, as before.

## 1. How the split is made

`Tools/wasm-split-release.mjs`, one step of `Tools/run-browser-embedded.sh` once every file of the bundle is in place and
before the files get their hashed names:

```
build → strip + wasm-opt → … → scope-resize-transitions → wasm-split → hash-release-bundle → seal-csp → (first-paint) → precompress
```

1. Binaryen's `wasm-split --instrument` writes a copy of the optimized `app.wasm` that records which functions run.
2. A copy of the bundle with that module is served and opened in headless Chromium, in the Worker as a visitor's page runs it,
   until its first screen is up: `html[data-embedded-mounted="true"]`, then 400 ms without a `commit-phase` (the same
   definition as first paint). It runs at every viewport of `SWIFTUIWEB_WASM_SPLIT_VIEWPORTS` (default `1280x800,390x844`), so
   the regular and the compact layout both count, and the profiles are merged. The profile is read from the Worker through the
   instrumented module's `__write_profile` export; the profiling copy's scripts carry a small hook for that, the shipped ones
   do not.
3. `wasm-split --split --profile` writes the two modules. They do not go through `wasm-opt` again: on the Board that made
   them larger over the wire (+0.9 KB brotli) for 5 KB less raw.
4. The split bundle is loaded once more at each viewport and must reach its first screen with no page error. A first screen
   that had to wait for `app-rest.wasm` (a function the profile missed) is reported as a warning.

The profile belongs to the exact binary, so it is taken again on each build (a few seconds). It is kept in the build logs
(`.build/browser-logs/<Product>/first-screen.prof`).

## 2. How it loads

Binaryen leaves, in `app.wasm`, an import for each function it moved (namespace `p.deferred`, named by the function's slot
in a table that wasm-split adds for them next to the indirect function table, since the release module has reference
types), and calls a moved function through its table slot. `app-rest.wasm` imports the first module's
memory, table, globals and the functions it calls (namespace `primary`), and its element segment writes the real functions into
those slots when it is instantiated. `Tools/wasm-split-loader.js` provides the placeholders and instantiates the second module;
a module without placeholder imports is not split, and nothing of it runs.

- **In the Worker** (the default runtime): the module starts with the placeholders. Once the first screen is published, the
  Worker fetches and compiles `app-rest.wasm` in the background and instantiates it. A call that reaches a placeholder before
  that loads it synchronously (a synchronous request and `new WebAssembly.Module`, which a Worker may do) and then calls the
  real function: the call waits, it does not fail.
- **On the main thread** (`?render-in-worker=0`, or a browser whose Worker stack is too small): the page cannot block, so it
  fetches `app-rest.wasm` while the first module instantiates and starts the app once both are there. Such a page downloads
  everything before its first screen, as an unsplit build does.
- **A move from the Worker to the main thread** (a stack overflow, see `Tools/embedded-host-core.js`): the main thread instantiates
  `app.wasm`, waits for `app-rest.wasm`, then copies the snapshot and replays the calls. The table is filled by the second
  module's element segment, so the snapshot of linear memory is all the state there is to carry, as before.

The thread's performance timeline gets the mark `swiftuiweb-app-rest` when the second module is instantiated, with
`detail.waited` saying whether a call had to wait for it.

Both modules get content-hashed names, the loader's reference to `app-rest.wasm` is rewritten with them
(`Tools/hash-release-bundle.mjs`), and both are precompressed. The Content-Security-Policy needs nothing new: the second module
is a same-origin fetch and compiles under the `'wasm-unsafe-eval'` the page already has.

## 3. Measured

Measured on the Board (`Tests/Apps/BoardBenchmarkApp`), see the pull request that added the split for the numbers of that date.

## 4. Limits

- A first screen that depends on data the profile run did not see (a signed-in user, a different route) runs functions that
  are in `app-rest.wasm`; the Worker then waits for it at that call. Profile the route most visitors open first.
- The main-thread runtime gains nothing: it loads both modules before its first screen.
- The total is larger than one module (the moved functions' exports and placeholders, and two compressed streams).
- A call that waits for `app-rest.wasm` while the background download is still on its way may make a second request for it;
  the browser's HTTP cache usually serves the second from the first.
