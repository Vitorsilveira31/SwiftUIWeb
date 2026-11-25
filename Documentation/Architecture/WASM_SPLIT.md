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
4. The data only the second module's code uses moves into the second module (section 2, "Data that moves with the code").
5. The split bundle is loaded once more at each viewport and must reach its first screen with no page error. A first screen
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

### Data that moves with the code

`wasm-split` moves functions and leaves every byte of data where it was, so `app.wasm` still holds the vtables, witness tables, type
metadata and string literals of the whole application, although the first screen reads a small part of them. On a large application
that is a fifth of the first module. `Tools/wasm-data-split.mjs` moves the part nothing in the first module can reach into
`app-rest.wasm`, as active data segments at the same addresses: they are written into the shared linear memory when the second module
is instantiated, which happens before any of its functions can run (in the Worker, after the first screen or at the first call that
needs it; on the main thread, before the application starts). The page makes no request for it and no API changes.

What decides that an object moves, all of it from the two modules and the linker's map (the launcher asks the linker for
`-Xlinker -Map=` on a build that splits, `.build/wasm-link-maps/<product>.map`):

- **The extent of an object.** Swift gives each global an input section of its own, so the map says exactly which bytes are a string
  literal, a witness table or a metadata record. The map must describe the module: its objects must cover the initialized bytes of the
  data section, or nothing moves. The cache key of a split includes the map.
- **Only what code cannot write.** Everything the linker put in `.rodata`, and the objects of `.data` that are type metadata (`...Mf`),
  protocol or value witness tables (`...WP`, `...WV`) or async function pointers (`...Tu`): the compiler does not mark them
  `const`, but Embedded Swift builds no metadata at run time and never stores to them (no store with a constant address in either module
  of the Showcase or of a large application hits one). Variables stay.
- **Who names it.** An object stays when the first module's code names an address inside it (an `i32.const`, or the offset of a load or
  a store, where LLVM folds a global's address), when a global's initializer does, when an object that stays holds a word that looks like
  its address (read at every byte offset, so a packed pointer counts), or when something names the address one past its end (which is
  also the start of the object that touches it). Initialized bytes the map gives to no object stay in the first module, and a word in
  them that looks like an address keeps what it points at. A string
  literal is also named by an address up to 24 bytes before it: a `String` holds the address of its native object, the first character
  less a 20-byte header (`_StringObject.nativeBias` on a 32-bit target). Objects the linker made share bytes (a string that is the tail of
  another) are one object. An object moves when the second module's code names it, or when only moving objects point at it, unless an
  object that stays (anything that is not moving, an object nobody names included) may point at it. Zero padding between two moving
  objects that no object owns goes with them.
- **Doubt keeps the data where it was.** A module with a passive data segment (`memory.init` names those by index), with an opcode the
  scan does not know, or whose map does not fit, moves nothing, and the build says why (`wasm split: the data stays in app.wasm (...)`).
  `SWIFTUIWEB_WASM_SPLIT_DATA=0` turns the move off.
- **The build checks it.** The analysis reads addresses out of code, and an address can be built in ways no scan sees (the string bias
  above was one: the first version moved a string the first screen then read as zeros). So the move is run before it ships: the first
  module, with the data moved, is instrumented with Binaryen's `--instrument-memory` (an import is called for every load and store),
  (`--llvm-memory-copy-fill-lowering` runs first, so a bulk copy is seen as the loads it is) and the first screen runs at each viewport
  of the profile run; every access that touches a moved range, whatever bytes it starts and ends at, before `app-rest.wasm` is instantiated
  fails the check (so does a run that measured nothing: the instrumented module did not report, the second module was not instantiated within the run, or the Worker that ran the module ended because the app moved to the main thread, taking its record along), and then the data stays in `app.wasm` and the build says what was touched. The check covers the first screen the
  profile run sees, as the split does, so it is a net under the analysis and not a proof for every later interaction; the analysis
  is the rule, and it errs towards keeping data.

A move from the Worker to the main thread copies a snapshot of the Worker's memory over the new instance's. A snapshot taken before the
Worker loaded `app-rest.wasm` has zeros where its data goes, so the main thread then instantiates the second module after the copy
(`loadAroundCopy` of `Tools/wasm-split-loader.js`, with `hold()` and `release()`); a snapshot taken after has the data, and the
instantiation comes first so that the copy has the last word. `window.__renderWorker.holds(address, word)` (performance diagnostics) answers
whether a word of the adopted memory is the given value, which lets a test check the data without reading the memory out.

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

Data that moves with the code (section 2), measured on 2026-11-24 on main at bdf4a72c, the same sources before and after (brotli,
quality 11; the second module grows by most of what the first loses, and the pair by about 1%):

| | `app.wasm` before | `app.wasm` after | `app-rest.wasm` before | `app-rest.wasm` after | Data moved |
|---|---|---|---|---|---|
| A large application | 396.9 KB | 348.9 KB (−12.1%) | 1,097.4 KB | 1,160.0 KB | 204.0 KB, 5,667 objects |
| Showcase | 241.2 KB | 231.6 KB (−4.0%) | 521.0 KB | 535.9 KB | 46.5 KB, 1,340 objects |
| Project site | 379.6 KB | 375.7 KB (−1.0%) | 229.9 KB | 236.8 KB | 21.6 KB, 469 objects |

The second module grows by more than the first shrinks (the large application: +62.6 KB against −48.0 KB): the moved bytes compress
worse beside code than beside the data they came from, and each run of them is a data segment of its own. What the first screen of a
large application allocates is a small part of its type metadata (2,824 of the 3,386 metadata records of its generic classes belong
to views no first screen creates), which is why it gains the most. The project site has no string catalog (its two languages are
literals in the code of the pages that show them), and its first screen is the whole landing page, so little of its data is only for
later.

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
- Data moves only when the check of section 2 passes at every profiled viewport, and never with `--no-verify`. A first
  screen that the profile run does not see (a route, a signed-in state) can read moved data the analysis did not name; the second
  module's arrival (right after the first screen in the Worker) ends that window, and the analysis is written to keep data
  whenever an address might name it.
- The total is larger than one module (the moved functions' exports and placeholders, the second module's element segments,
  and two compressed streams).
- A module that needs reference types, lists a feature `FEATURE_FLAGS` does not know, or has code that writes its function
  table keeps the two-table layout and the trampolines it brings.
- A call that waits for `app-rest.wasm` while the background download is still on its way makes a second request for it;
  Chromium serves that one from the first (its `transferSize` is 0 on the Board), so no byte comes twice there.
