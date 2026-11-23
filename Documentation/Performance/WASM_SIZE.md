# Where the WASM bytes go

Embedded Swift specializes every generic view type the application uses, so the linked `app.wasm` grows with the number of distinct
view types and with how deeply they nest, not with the size of the framework's source. This page explains where the bytes are, how to
attribute them, and which techniques keep them down. The numbers are for the Showcase release build (stripped, `size` profile) unless
a row says otherwise.

## Attributing bytes to functions

Release builds strip the `name` section. A release build keeps a copy with the names when asked, next to the stripped bundle:

- `SWIFTUIWEB_KEEP_OPTIMIZED_WASM_NAMES=<file>` is the module as it ships, optimized exactly as the release is. Size questions are
  about this one.
- `SWIFTUIWEB_KEEP_WASM_NAMES=<file>` is the module as it was linked, before `wasm-opt`: about a quarter larger, with functions the
  optimizer folds or removes.

```sh
SWIFTUIWEB_KEEP_OPTIMIZED_WASM_NAMES=.build/size/showcase-names.wasm \
  BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh showcase
bun Tools/wasm-function-sizes.mjs .build/size/showcase-names.wasm --top 40 \
  --json .build/size/showcase-names.json
bun Tools/wasm-function-sizes.mjs --diff before.json after.json
```

The report groups code bytes by Swift module (from the `$e<len>Module` mangling) and by kind (generic specialization, outlined value
witness, thunk, plain), and lists the largest functions. `--diff` compares two named builds by symbol. A stripped bundle still reports
its function count and size distribution, which separates "more functions" from "bigger functions".

`Tools/wasm-size-attribution.mjs` answers the next questions on the same module: which generic functions have the most copies, how
much of the code is the application's own and how much is framework code copied for the application's types (`--app-modules`), and,
given a split's profile and its first module, what the first screen runs and what the forwarding stubs of the split cost. A copy of a
generic function is counted in the function it belongs to, closures included. The profile must come from the same build; a profile with
another function count is refused. `--json` keeps a report, and `--diff` compares two of them: the generics whose copies changed between
two builds, largest change first. `make wasm-attribution` runs the same tool with `WASM=`, `PROFILE=`, `SPLIT=` and `APP_MODULES=`.

```sh
bun Tools/wasm-size-attribution.mjs .build/size/showcase-names.wasm --top 25 --json .build/size/showcase-after.json \
  --profile .build/browser-logs/ShowcaseApp/first-screen.prof --split-primary .build/browser/ShowcaseApp/app.*.wasm
bun Tools/wasm-size-attribution.mjs --diff .build/size/showcase-before.json .build/size/showcase-after.json
```

To attribute an application without changing its checkout, run the Embedded build in plugin mode against a copy:

```sh
SWIFTUIWEB_PACKAGE_ROOT=/path/to/app-copy SWIFTUIWEB_PLUGIN_MODE=1 \
  SWIFTUIWEB_KEEP_OPTIMIZED_WASM_NAMES=.build/size/app-names.wasm \
  BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser-embedded.sh AppProduct
```

## Measuring a large application

The code grows with the number of views an application declares, so a change to the framework is measured on an application that has
many. `Tools/generate-large-app.mjs` writes one: a deterministic synthetic application shaped like a layered SwiftUI app, with a
feature folder for every ten views (a model decoded from JSON, a store, pure rules, a screen, and row, card and sheet views with
modifier chains, conditionals, `ForEach`, bindings and sheets). The same arguments write the same bytes.

```sh
make large-app-size VIEWS=200
```

The target generates the package into `.build/large-app/<VIEWS>/package`, builds it in release, and prints the sizes of the bundle's
two modules and the attribution of the module as it ships. The report stays in `.build/large-app/<VIEWS>/report.json`:

- **A change to the framework.** Run the target before and after, keep the first report under another name, and compare the two with
  `bun Tools/wasm-size-attribution.mjs --diff before.json .build/large-app/200/report.json`.
- **Bytes per view.** Run the target for two view counts and divide the difference in code bytes by the difference in views. The code
  bytes are the ones the report gives for the whole module, not a file size: a file also holds the data segments, and the two files of
  a split hold the split's own imports and stubs.

Measured on 2026-11-22: 1,575,673 B of code at 100 views and 2,065,598 B at 200, so 4.9 KB of code for each view; the two modules
of the bundle are 498,548 B and 602,041 B with Brotli -q11.

## Where the bytes are

- **Per-type duplication of generic code.** Each view type gets its own copy of the generic code that wraps it. The framework moves
  the type-independent part into non-generic functions, so that each view type keeps only what depends on it.
- **Nested modifier chains.** A modifier chain nests by type (`ModifiedContent<ModifiedContent<…>, M>`), and each level holds the inner
  view by value. Without boxing, each level's copy, destroy and closure-context witnesses copy the whole chain beneath it, so a chain of
  depth N compiles to outlined code of order N². `_ViewBox`, a final class that holds the wrapped view, reduces each level to a pointer
  copy. `ModifiedContent` and `_ConditionalContent` use it.
- **Modifier builders.** `frame(...)`, `padding(...)` and `fixedSize(...)` build their style tables in non-generic functions
  (`_frameModifier`, `_paddingModifier`, `_fixedSizeModifier`). The generic methods only wrap the result. Their specializations are
  about 190 KB on the Showcase, almost all of it the unavoidable per-type `_render` that calls `body`.
- **Type-erased views and `ForEach`.** Each `AnyView` closure would carry the environment and state-scope bookkeeping and format the
  view's type name on every render. `_enterRenderScope` and `_exitRenderScope` hold that bookkeeping once, and the name is computed once
  per `AnyView`. `ForEach`'s algorithm (occurrence keys, the lazy descriptor, the eager fragment) is in `_renderKeyedCollection`, so a
  `ForEach` specialization is only the element lookup and the `content` call.
- **Conditional content.** `_ConditionalContent._render` keys the branch and the state scope in the non-generic `_renderBranch`. The
  per-type part is one `AnyView` erasure.
- **Renderers that only render their content.** `GeometryReader`, `ScrollView`, the overlay and background modifiers and the tab
  view's sidebar content build their node, and finish it, in non-generic functions. The generic function forms the content, renders it
  and hands it over, so every copy of it is the same code and the optimizer keeps one.
- **Branches only one type takes.** A generic function is compiled for every type it is used with, the branches only one of them can
  take included. Naming that type (`Label.self == PrimitiveButtonStyleConfiguration.Label.self` in `Button._render`) or asking a
  constant of the type (`V._comparesInputs` in `_ViewRenderer.reusedRender`) lets the compiler drop the branch, and the functions only
  it calls, from every other copy.
- **Code only another host runs.** `AnyView` forms a view's body inside the owner's Swift Observation scope where Swift Observation
  exists. The browser build registers the renderer itself as the owner, so the closure that forms the body, and
  `_makeObservationBodyRenderer` behind it, are compiled out of it: left in, they are emitted once per erased view type and never
  called.
- **Writes to a render node.** Reading a `_RenderNode` is inlined; writing one is a call (`_setClasses`, `_openAttributes`, ...). A
  write resolves the node and, on a node a Fiber holds, compares what it had with what it gets, and the framework writes a node in
  about two thousand places. `_NodeValues`' setter and `_RenderContext.child(_:)` are calls for the same reason.
- **Framework code specialized for the application.** In a large application, `SwiftUIWebCore` instantiated for the application's
  types is about 6.8 MB of code (65 % of it), against 1.95 MB of application code. Generic specializations were 5.2 MB of that, outlined
  copies of value types 1.5 MB, and closure-context destructors 450 KB.

## Results of the techniques

Across the first five techniques above, the Showcase release bundle (stripped) went from 3.20 MB to 2.73 MB raw, and from 739 KB to
700 KB with Brotli -9. The release sizes of each build are reported by `make wasm-size`.

The next four (the renderers that only render their content, the branches only one type takes, the code only another host runs and
the writes to a render node), with the second `wasm-opt` round below, measured on a large application (434 views with a body, release,
Brotli -q11, 2026-11-22):

| | Before | After | Change |
|---|---|---|---|
| Code of the optimized module | 6,964,723 B | 6,040,381 B | -13.3 % |
| Functions | 22,484 | 20,239 | -10.0 % |
| One module, raw | 7,527,404 B | 6,588,533 B | -12.5 % |
| One module, Brotli | 1,553,689 B | 1,403,029 B | -9.7 % |
| `app.wasm` of the split, Brotli | 488,541 B | 453,589 B | -7.2 % |
| `app-rest.wasm` of the split, Brotli | 1,238,769 B | 1,099,842 B | -11.2 % |

The code only another host runs is 465 KB of that code (1,695 functions); the writes out of line and `child(_:)`, about 290 KB; the
renderers that only render their content and the branches only one type takes, about 150 KB. The Board benchmark's two modules went
from 292,429 B to 271,077 B with Brotli (`app.wasm` from 174,063 B to 160,995 B), and an interleaved comparison of the two Board
bundles (`Tools/compare-react.mjs`, 10 rounds, CPU 1x) found no significant difference in any load or interaction metric. The
synthetic application of 200 views (`make large-app-size`) went from 2,279,113 B of code to 2,065,598 B (-9.4 %), its two modules
from 648,894 B to 602,041 B with Brotli (-7.2 %), and a view from 5.3 KB of code to 4.9 KB.

## Options that were measured

- `SWIFTUIWEB_WASM_MERGEFUNC_THRESHOLD` (Swift's function-merging pass). Thresholds 2 and 8 grow the Showcase by 1.1 % and 0.7 %.
  A release merges at 30 by default; `off` keeps the toolchain default, as a debug build does. Measured after wasm-opt
  (brotli -q11 of app.wasm, release, 2026-11-16):

  | app.wasm | off | 30 | 100 |
  |---|---|---|---|
  | Board, raw | 1,318,163 | 1,313,889 (-0.3 %) | +1.1 % |
  | Board, brotli | 397,799 | 396,962 (-0.2 %) | 0.0 % |
  | Showcase, raw | 3,861,036 | 3,846,174 (-0.4 %) | 3,906,953 (+1.2 %) |
  | Showcase, brotli | 961,001 | 957,732 (-0.3 %) | 957,798 (-0.3 %) |

  wasm-opt already folds most of what the pass would merge, so the gain is small; 100 grows the raw binary. An interleaved
  A/B of the Board at 30 against off (`Tools/compare-react.mjs`, 10 rounds, CPU 1x) found no significant difference in any
  interaction or load metric.
- `wasm-opt` (Binaryen) runs on the release bundle by default in `Tools/strip-wasm-release.sh` when it is installed. `WASM_OPT=0`
  disables it. On a large application's release bundle (6.71 MB stripped, not the Showcase):

  | Level | Raw | gzip -9 | brotli -q11 |
  |---|---|---|---|
  | none | 6,712,686 | 2,043,314 | 1,037,146 |
  | `-Os` | 4,869,367 | 1,786,377 | 998,015 |
  | `-Oz` | 4,508,371 | 1,690,761 | 1,005,141 |
  | `-O2` | 4,962,706 | 1,808,703 | 1,008,824 |

  On the Board benchmark (`BoardBenchmarkApp`, release, stripped) the bundle is 1,726,911 B without Binaryen and 1,319,023 B with
  `-Oz` (-24 % raw). Brotli -q11 is 429,687 B against 410,542 B (-4.5 %), and the bytes transferred over the whole page are 571,455 B
  against 542,146 B (-5.1 %). In a local cold-load probe, the `-Oz` bundle reaches layout about 4 ms sooner, and the first frame is
  within the frame noise. Binaryen stays on by default: the size gain matters most on a slow network, and the load gain is small.

- `WASM_OPT_ROUNDS`: how many times `wasm-opt` runs its level in one call, 2 by default. What the first round inlines and removes
  leaves duplicates and constants that the second folds: on a large application the module goes from 6,613,745 B to 6,588,533 B, and
  from 1,418,690 B to 1,403,029 B with Brotli (-1.1 %). Binaryen's other size passes do not pay there: `--merge-similar-functions`
  changes nothing, `--outlining` is 1.7 % smaller raw and 4.5 % larger with Brotli, `-Os` and `-O3` are larger both ways, and
  `--reorder-functions-by-name` is 0.6 % smaller with Brotli for 2.3 % more raw (8.6 % smaller with gzip, where a host serves that).

- `--all-features` must not be passed to `wasm-opt`: it emits compact imports, which Chromium rejects (`Invalid import kind 127`).

When Binaryen is not installed, `Tools/strip-wasm-release.sh` says so on stderr for each release build and does not fail. Install it with
`brew install binaryen`, or disable it on purpose with `WASM_OPT=0`. `make setup` and `make doctor` report it as optional.

## The C and standard-library runtime

Some of the module is not Swift code the application wrote but archives the Embedded toolchain links. To see which object pulled
each archive member, pass `SWIFTUIWEB_EXTRA_BUILD_FLAGS="-Xlinker --why-extract=.build/size/why-extract.txt"` to a build.

- **Unicode data.** `String`'s comparison, hashing, `Character` iteration and case mapping read per-scalar data from
  `libswiftUnicodeDataTables` (normalization, grapheme break properties, Extended_Pictographic, case mappings). The browser has the
  same data, so `Sources/CSwiftUIWebBrowserIO/UnicodeData.c` defines those functions as calls to `Tools/BrowserIO/unicode-data.mjs`
  (`String.prototype.normalize`, `Intl.Segmenter`, the Unicode property escapes, `toUpperCase`/`toLowerCase`). The definitions are
  weak and the archive stays linked: an application that reads a property the browser does not expose (general category, numeric
  value, name, age, script, the binary properties behind `isWhitespace`) links the archive member that holds it, whose definitions
  then replace these. The Unicode version is therefore the browser's, as it is the operating system's for an Apple app. The
  framework's own parsers read ASCII digits with `_asciiDigitValue` instead of `wholeNumberValue`, which would link the numeric tables.
- **printf.** Only the Concurrency runtime's error messages format with `vsnprintf`/`vprintf`.
  `Sources/CSwiftUIWebBrowserIO/RuntimeFormatting.c` replaces wasi-libc's printf engine (`printf_core`, float printing, wide
  characters) with integer, string and pointer conversions.

On the Board benchmark (release) these took `app.wasm` from 440,657 to 407,057 bytes with Brotli (data section 101,902 to 45,212 bytes
raw), and the page from 606.0 to 574.7 KB; `unicode-data.mjs` adds about 1.2 KB to `index.js` and to `render-worker.js`. On the
Showcase, which links the archive's scalar properties, `app.wasm` went from 969,496 to 938,859 bytes with Brotli.

Measured and kept: the standard library's float parser (`parse_float64`, `fastParse64`, `slowDecimalToBinary`, with libm's `fma`),
about 10 KB of code before `wasm-opt` and 2 KB with Brotli, which `Double(String)` in the style, layout and measurement decoders
links; `dlmalloc`, 12 KB before `wasm-opt` (wasi-libc ships no smaller allocator); and `_Float64ToASCII`, which prints every CSS
number. Of libm only `round`, `fmod` and `remainder` remain besides `fma`; the trigonometry is Swift.

## Loading

`Tools/browser-index.html` announces `index.js` with `modulepreload`, and starts the `app.wasm` download from an inline script in the head
(`globalThis.__appModuleFetch`). The WASM transfer therefore starts while the stylesheet and the classic scripts load, not after the
module graph has been evaluated. The runtime takes that response instead of fetching again, so the module is transferred once. A
`<link rel="preload" as="fetch">` is not used: WebKit does not hand it to the runtime's `fetch`, and Safari would download the module twice.

## What remains

On the Showcase the code section is 6.65 MB, and the functions that mention `AnyView` sum to 0.87 MB. That is 3,852 thin closures and 3,390
partial-application thunks, a few dozen bytes per erased view that cannot be avoided. `ForEach` accounts for 0.18 MB. Each application view
type still gets a specialization of every wrapper it appears in. Fewer wrapper levels per view (folding built-in modifiers into one node)
and view memoization reduce both the code and the render work.
