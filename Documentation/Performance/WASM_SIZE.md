# Where the WASM bytes go

Embedded Swift specializes every generic view type the application uses, so the linked `app.wasm` grows with the number of distinct
view types and with how deeply they nest, not with the size of the framework's source. This page explains where the bytes are, how to
attribute them, and which techniques keep them down. The numbers are for the Showcase release build (stripped, `size` profile) unless
a row says otherwise.

## Attributing bytes to functions

Release builds strip the `name` section. Keep a named copy next to the stripped bundle to analyze it:

```sh
SWIFTUIWEB_KEEP_WASM_NAMES=.build/size/showcase-names.wasm \
  BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh showcase
bun Tools/wasm-function-sizes.mjs .build/size/showcase-names.wasm --top 40 \
  --json .build/size/showcase-names.json
bun Tools/wasm-function-sizes.mjs --diff before.json after.json
```

The report groups code bytes by Swift module (from the `$e<len>Module` mangling) and by kind (generic specialization, outlined value
witness, thunk, plain), and lists the largest functions. `--diff` compares two named builds by symbol. A stripped bundle still reports
its function count and size distribution, which separates "more functions" from "bigger functions".

To attribute an application without changing its checkout, run the Embedded build in plugin mode against a copy:

```sh
SWIFTUIWEB_PACKAGE_ROOT=/path/to/app-copy SWIFTUIWEB_PLUGIN_MODE=1 \
  SWIFTUIWEB_KEEP_WASM_NAMES=.build/size/app-names.wasm \
  BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser-embedded.sh AppProduct
```

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
- **Framework code specialized for the application.** In a large application, `SwiftUIWebCore` instantiated for the application's
  types is about 6.8 MB of code (65 % of it), against 1.95 MB of application code. Generic specializations were 5.2 MB of that, outlined
  copies of value types 1.5 MB, and closure-context destructors 450 KB.

## Results of the techniques

Across the techniques above, the Showcase release bundle (stripped) went from 3.20 MB to 2.73 MB raw, and from 739 KB to 700 KB with
Brotli -9. The release sizes of each build are reported by `make wasm-size`.

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
