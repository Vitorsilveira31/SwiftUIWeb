# Split module

A SwiftUIWeb page cannot show its first screen until the whole `app.wasm` has arrived and compiled, although that screen runs
only part of it. A split build moves every function the first screen did not run into a second module, `app-rest.wasm`, which
downloads right after the screen is up. The page waits for fewer bytes before it shows anything; the total grows a little.

A release build splits by default. No Swift API changes. `SWIFTUIWEB_WASM_SPLIT=0` builds one `app.wasm` on purpose, and
`SWIFTUIWEB_WASM_SPLIT=1` makes a split that cannot be made an error. Without the variable, a machine that lacks what the
split needs (a Binaryen `wasm-split` with the options below, a headless Chromium), or a split that fails, ships one `app.wasm`
with a warning, the way a release without `wasm-opt` does. Debug builds, the development loop and the `fast` release profile
never split unless asked. The split of a module whose inputs did not change is reused from `.build/wasm-split-cache`
(`SWIFTUIWEB_WASM_SPLIT_CACHE=0` turns it off), so an unchanged build runs no browser.

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
   that had to wait for `app-rest.wasm` (a function the profile missed) is reported as a warning. A split that
   moved a mutable global into `app-rest.wasm` fails the build: a move from the Worker to the main thread carries linear
   memory only, and that global would start over (a Swift module's only mutable global is its stack pointer, which stays in
   `app.wasm`).

Which table holds the placeholders depends on the module's features. When it has reference types, Binaryen adds a second
table for them, and every moved function whose address the module's own table holds gets a trampoline in `app.wasm` (a
function that only does `call_indirect` through the new table) that stays on every call to it for the life of the page.
Without reference types it reuses the module's own table and writes no trampoline. The toolchain lists `reference-types` in the
`target_features` section of its modules because the compiler enables it, not because the code uses it, and Binaryen's reader
enables every feature of that section after the command-line flags. So the step reads that section first and, when the module
validates without the feature, splits a copy of the module without the section (every other byte as it is), with
`--mvp-features` and an `--enable-…` flag for each other feature the section lists (`FEATURE_FLAGS` in
`Tools/wasm-split-release.mjs` maps the names). The same copy and flags serve `--instrument` and `--split`, because the profile
carries the checksum of the module it was made for. The module is not rewritten through `wasm-opt`.

The two-table layout is kept, and the build's `wasm split:` line says so with the reason, when the module has no
`target_features` section or does not list reference types, lists a feature that has no flag in that table, does not
validate without reference types, or has code that writes its function table. `table.copy` and `table.init` need bulk
memory only, so validation alone lets them through; a placeholder sits in a slot of that table, and a call the split routed
through the slot would follow such a write, where the unsplit module's direct call does not. One `wasm-opt` run before the
profile run checks both: it validates the copy and counts its instructions (`--metrics`). That layout costs the trampolines in
`app.wasm`, a table of its own and an extra indirection on calls to moved functions. The single-table layout costs
`app-rest.wasm` the element segments that fill the placeholders' slots, which the two-table layout does not need to the
same degree. The split of a module is cached with its layout, and the flags are part of the cache key.

The profile belongs to the exact binary, so it is taken again on each build (a few seconds). It is kept in the build logs
(`.build/browser-logs/<Product>/first-screen.prof`).

## 2. How it loads

Binaryen leaves, in `app.wasm`, a placeholder import for each table slot of a function it moved (namespace `p.deferred`,
named by the slot), and a call to a moved function goes through its slot. By default those slots are the moved functions'
own slots in the module's indirect function table: the placeholder sits where the function was, and a direct call from the
first module to a moved function becomes an indirect call through the function's slot.
`app-rest.wasm` imports the first module's memory, table, globals and the functions it calls (namespace `primary`), and its
element segments write the real functions into those slots when it is instantiated. `Tools/wasm-split-loader.js` provides the placeholders and instantiates the second module;
a module without placeholder imports is not split, and nothing of it runs.

- **In the Worker** (the default runtime): the module starts with the placeholders. Once the first screen is published, the
  Worker fetches and compiles `app-rest.wasm` in the background and instantiates it. A call that reaches a placeholder before
  that loads it synchronously (a synchronous request and `new WebAssembly.Module`, which a Worker may do) and then calls the
  real function: the call waits, it does not fail.
- **On the main thread** (`?render-in-worker=0`, or a browser whose Worker stack is too small): the page cannot block, so it
  requests `app-rest.wasm` as soon as it knows it will start there (at once for `?render-in-worker=0`, when the stack probe
  answers otherwise), beside `app.wasm`, and starts the app once both are instantiated. Such a page downloads everything
  before its first screen, as an unsplit build does, in two requests side by side.
- **A move from the Worker to the main thread** (a stack overflow, see `Tools/embedded-host-core.js`): the main thread instantiates
  `app.wasm`, waits for `app-rest.wasm`, then copies the snapshot and replays the calls. The table is filled by the second
  module's element segment, so the snapshot of linear memory is all the state there is to carry, as before.

The loader is in the scripts of a split build only: the launcher bundles the runtime with
`globalThis.SWIFTUIWEB_WASM_SPLIT_LOADER` defined as `false` otherwise, and the bundler drops it (it would cost 1.5 KB brotli).

The thread's performance timeline gets the mark `swiftuiweb-app-rest` when the second module is instantiated, with
`detail.waited` saying whether a call had to wait for it.

Both modules get content-hashed names, the loader's reference to `app-rest.wasm` is rewritten with them
(`Tools/hash-release-bundle.mjs`), and both are precompressed. The Content-Security-Policy needs nothing new: the second module
is a same-origin fetch and compiles under the `'wasm-unsafe-eval'` the page already has.

## 3. Measured

The module sizes were measured on 2026-11-23, with the placeholders in the module's own table (brotli, quality 11); they are
deterministic. The Board's cold load and the timings below were measured on 2026-11-16 (main at dbc7cb8f), with the
placeholders in a table of their own, on an Apple-silicon Mac shared with other work, in Chromium: the timings are medians of
interleaved runs (the split and the unsplit bundle alternate, each in a fresh browser), with the 99 percent bootstrap interval
and signed-rank test of `Tools/perf-ab-stats.mjs`.

| Module sizes (brotli) | Unsplit `app.wasm` | `app.wasm` (first screen) | `app-rest.wasm` | Total |
|---|---|---|---|---|
| Board | 235.1 KB | 152.2 KB (−35%) | 106.2 KB | 258.3 KB (+10%) |
| Showcase | 699.2 KB | 241.1 KB (−66%) | 522.0 KB | 763.1 KB (+9%) |
| Project site | 550.3 KB | 379.1 KB (−31%) | 230.4 KB | 609.5 KB (+11%) |

The total grows by the placeholders (one import for each table slot of a moved function), the exports the second module needs,
the element segments of the second module that fill the placeholders' slots, the calls of the first module to a moved function,
which go through a table, and the two halves being compressed apart. Where the placeholders sit moves bytes between the two
modules: on a large application the first module is 404,603 B with them in the module's own table and 430,450 B with a table
of their own (19 trampolines against 10,907), and the second module 1,119,675 B against 1,104,299 B.

Board, cold load (Worker, the default):

| | Unsplit | Split | Change |
|---|---|---|---|
| Transferred to show the board (the page's own requests) | 564.0 KB | 414.3 KB | −26.5% |
| Every byte of the visit, the Worker's request for `app-rest.wasm` included | 540.8 KB | 577.6 KB | +6.8% |
| Cold load to the board on screen, local network (12 rounds) | 75.7 ms | 81.9 ms | no significant difference |
| Cold load to the board on screen, Slow 4G (12 rounds) | 3,151 ms | 2,372 ms | −24.7% |
| A key typed in the search right when the board shows, Slow 4G (6 rounds) | 123 ms | 1,139 ms | it waits for `app-rest.wasm` |
| The same key 1 s after the board shows, Slow 4G (12 rounds) | 124 ms | 122 ms | no significant difference |

With the runtime in one shared chunk (main at 27716de3) the Board transfers 508.3 KB unsplit and 357.5 KB split to show
its board (−29.7%), and 492.0 against 527.7 KB over the whole visit (+7.3%); the split build's scripts carry the loader,
0.9 KB brotli more. There (10 interleaved rounds each) the cold load on Slow 4G goes from 2,906 to 2,137 ms (−26.6%), on a
local network 52.9 against 50.7 ms (not significant), and on the main thread under Slow 4G from 2,932 to 3,110 ms (+6.2%).

On the main thread (`?render-in-worker=0`, Slow 4G, 10 rounds) the split costs what its extra bytes cost: 3,153 ms against
3,346 ms (+6.2%), both modules downloading side by side. On a local network the split costs a few milliseconds at the start: the interleaved runs above put the
Worker at 75.7 against 81.9 ms (not a significant difference); two separate `Tools/compare-react.mjs` runs put it at 69 against
75 ms, and the main thread, which compiles both modules before it starts, at 53 against 66 ms. Delaying the background
download by 2 s does not change it (81.5 against 86.8 ms, not significant), so it is the start of the split module itself,
not the download competing with the first screen. Every interaction of `Tools/compare-react.mjs` starts after
`app-rest.wasm` has arrived and none of them moves beyond the spread of separate runs; the tables are in the pull request.

## 4. Limits

- A first screen that depends on data the profile run did not see (a signed-in user, a different route) runs functions that
  are in `app-rest.wasm`; the Worker then waits for it at that call. Profile the route most visitors open first.
- The main-thread runtime gains nothing: it loads both modules before its first screen, and pays for the larger total. A
  failed download of `app-rest.wasm` stops its start (the Worker still starts, and loads it when a call needs it).
- What the first screen did not run waits for `app-rest.wasm` when it is first needed: on the Board, the search's filter is
  in it, so a key typed under Slow 4G at the moment the board shows waits about a second for the download to finish. A call
  waits on the Worker; the page itself (the field's text, scrolling) does not.
- The total is larger than one module (the moved functions' exports and placeholders, the second module's element segments,
  and two compressed streams).
- A module that needs reference types, lists a feature `FEATURE_FLAGS` does not know, or has code that writes its function
  table keeps the two-table layout and the trampolines it brings.
- A call that waits for `app-rest.wasm` while the background download is still on its way makes a second request for it;
  Chromium serves that one from the first (its `transferSize` is 0 on the Board), so no byte comes twice there.
