# Performance contracts

This page lists what the performance checks measure, the command that runs each check, and the file that holds its budget.
The budgets in `PERFORMANCE_BUDGETS.json` and `BROWSER_ARTIFACT_SIZE_BASELINE.json` are the release gates. The size targets
are reports: `make wasm-size` and `make wasm-size-check` record the sizes and compare them with the baseline, and they never fail
a run because a size grew (`Tools/wasm-size.mjs`: "Size is a target, not a gate"). Only `make wasm-budget` fails on a size.

```sh
make perf-test                 # Swift lifecycle metrics, under .build/performance/
make memory-test
make wasm-size                 # raw, gzip, Brotli and zstd sizes of the local deployment assets
make wasm-size-check           # the same, compared with EMBEDDED_WASM_SIZE_BASELINE.json (reports only)
make wasm-budget BUNDLE=.build/browser/ShowcaseApp   # Brotli budget of a bundle; fails when it is exceeded
make perf-browser-test         # builds the ShowcaseApp bundle, then checks browser performance
make perf-ci                   # the set the nightly CI job runs
```

The collectors are Bun scripts: `Tools/performance-contracts.mjs`, `Tools/wasm-size.mjs`, `Tools/measure-bundle.mjs`,
`Tools/coverage.mjs` and `Tools/wasm-function-sizes.mjs`. They write their numbers and exit codes under `.build/performance/`,
`.build/wasm-size/` and `.build/coverage/`. The `Tools/test-*.mjs` scripts (run by `make integrated-check`) check those outputs
against stored expected files.

The Embedded SDK is required for the Embedded size measurements. When it is missing, the result is reported as an environment
blocker. It is never replaced with a native-only result.

## Artifact budgets

`Tools/report-release-size.js` writes the measured artifact report to `.build/performance/artifact-size.json`. When no build report
exists, the gate uses the checked-in `BROWSER_ARTIFACT_SIZE_BASELINE.json`, so local and CI runs check the same product name
(`ShowcaseApp`). Artifact budgets are evaluated against an absolute maximum and against the baseline's regression limit. Delivery
budgets use Brotli, and gzip is reported as a compatibility metric. The bundle audit's experimental codecs are diagnostic only.
Lifecycle behavior (ownership of views and mounts) is checked by the Swift and browser ownership tests.

## Frame-time budgets

`FRAME_BUDGETS.json` holds the frame-time targets of the browser apps: main-thread time per commit, long tasks and frame shares at
CPU 1x and 4x. Each budget is in report mode. An application supplies the interaction scenario, and `make perf-frames` and
`make perf-frames-check` measure and evaluate it. See [`FRAME_BUDGETS.md`](FRAME_BUDGETS.md).

## Phase diagnostics

Diagnostics are off by default. Turn them on with `?render-performance=1` in the browser, or with
`mountEmbeddedBrowser(instance, { performanceDiagnostics: true })` when mounting a custom host:

```js
const session = mountEmbeddedBrowser(instance, { performanceDiagnostics: true });
session.performanceMetrics.reset();
// Run one representative interaction, then inspect:
const sample = session.performanceMetrics.snapshot();
```

The built-in browser entry exposes the live session as `window.__performanceMetrics`. The values are cumulative between `reset()` and
`snapshot()`, so take a snapshot before and after an interaction and subtract.

- `swiftDispatchPublishMs` is the complete synchronous WASM dispatch, including Swift's reconciliation, snapshot and HTML serialization.
  In the Embedded build the Swift phases are in `snapshot().fiber` as microsecond counters (`publishReconcileUs`,
  `publishSnapshotWalkUs`, `publishAnnotateUs`, `publishSerializeUs`, `publishBookkeepingUs`). They use the WASI monotonic clock.
- The adapter records HTML read and parse, DOM patching, and post-patch host work. `postPatchSyncMs` is the total of that host
  work and includes its phase counters, so do not add them together.
- Gesture counters report the tracked pointer moves, the values queued and flushed per `requestAnimationFrame`, and the time of the
  pointer, flush and finish handlers. `gestureFrameFlushMs` includes synchronous callbacks into Swift, and `gestureWasmDispatches`
  counts the dispatches of queued gesture updates. The pointer-up finish dispatch is counted separately.
- The layout snapshot reports `passes` (layout passes the host ran), `passesSkipped` (passes skipped because nothing changed) and
  `unlaid` (the semantic roots of the last pass that CSS could not lay out), and `cssMs`. A same-value attribute write on `<html>` or
  `<body>` does not request a pass.
- Fiber route misses are split into unavailable owner groups, source-count mismatches, dirty groups without an active owner, and
  unresolved stale owner tokens. `publishedObservationOwnerPathRemaps` counts the conservative remaps to a narrower live owner, and
  `publishedObservationRouteMisses` is the aggregate fallback count.

To measure a page, open it with `?swuidiag` and take the difference of `window.__performanceMetrics.snapshot()` (`commits`,
`layout.passes`, `diagnostics.layoutUpdateMs`) around the interaction. Measure a release bundle. A debug bundle is much slower to
interact with. To compare two builds, use `Tools/perf-ab.mjs` ([A/B benchmark](AB_BENCHMARK.md)), which serves both and alternates
the runs.

## Window resize does not animate

An element under an `.animation` modifier carries an inline CSS transition. If the window resize changed its width, the transition would
run, and every frame of it would report new sizes to Swift, which renders and lays out again.

While a resize settles (`RESIZE_SETTLE_MS` after the last width change or `resize` event), `SemanticLayoutHost` sets
`data-layout-resizing` on the document element. The resize rule of the bundle turns the transitions off under it. The rule names only
the elements that declare a transition: the ones with `data-animation`, `data-layout-animation` or an inline `transition` style.
A rule over every element would restyle the whole document on each toggle.

- `Tools/test-layout-resize-settle.mjs` checks the mark and the generated rule.
- `Tools/test-resize-transition-browser.mjs` checks the computed durations in Chromium and WebKit.

## A layout pass costs what the commit changed

Every commit runs `SemanticLayoutHost.update()`. The pass offers the mapper the semantic roots of the page and applies what it styled.
`Tools/css-layout.js` analyses only the elements that a mutation reached (see [`CSS_LAYOUT.md`](../Architecture/CSS_LAYOUT.md)).
A pass is skipped when it would find nothing. It is skipped only when all of these hold:

- the last pass completed and nothing called `schedule` since;
- the collected records changed nothing that the layout reads (a mutation inside a CSS island that `affectsCssLayout` does not name
  is not a change);
- no epoch moved (fonts, global attributes), and the window did not resize.

The exception is a page with a user-defined `Layout`: the sizes it reports follow its subviews' content, and a text change is not one
the mapper notes, so its pass is not skipped on that basis. `layout.passesSkipped` counts the skipped passes.
`Tools/test-layout-skip-pass.mjs` checks each condition that must make the pass run.

Two debug switches compare the incremental work with a full recomputation:

- `window.__layoutVerify = true` compares every incremental analysis of the mapper with one made from scratch. A divergence is
  reported in `window.__layoutMismatch` and as a console error. `SWIFTUIWEB_LAYOUT_VERIFY=1` sets it in every page that a
  `Tools/test-*-browser.mjs` suite opens (`Tools/browser-test-support.mjs`).

### Binary publications

Publications travel as binary streams (`Tools/binary-publication.js` and `BinaryFiberEncoder`). The whole tree is sent when the page
holds nothing (the first publication, a full one, or the first after the move to the main thread). Otherwise only the records of the
elements that changed since the epoch the page acknowledged are sent. The HTML serializer does not run for them. A tree that the HTML
parser would restructure is written as one it keeps (see [`BINARY_PATCHES.md`](../Architecture/BINARY_PATCHES.md), "Placement").

- `window.__binaryVerify = true` (`?binary-verify=1`, `SWIFTUIWEB_BINARY=verify`) makes Swift attach a reference to each publication:
  the whole tree encoded again by a fresh encoder. After every commit the page builds that reference in a detached document and
  compares the DOM with it. Each difference is reported in `window.__binaryVerifyReport` and as a console error (`BINARY-MISMATCH` in
  the browser suites).
- `SWIFTUIWEB_BINARY=full` stops the page from acknowledging, so every publication is a whole tree.
- `window.__acknowledgeLag = n` acknowledges each publication n commits late, as a busy page does.

### Post-patch syncs

After a commit's patch, the page runs its post-patch syncs (tab selections and the tab shell, title and head, secure fields, theme,
platform, focus, scroll, presentations, history, geometry, media, layout, lazy windows and canvases). Each one is skipped when nothing
it reads changed. `CommitChanges` (`Tools/embedded-dom.js`) records every change under the root since the previous commit's syncs.
The syncs' own writes are not recorded. A host answers `needsSync(changes)`.

- `?sync-gates=0` (`window.__syncGates = false`, `SWIFTUIWEB_SYNC_GATES=0` for the suites) runs every sync after every commit.
- `?sync-verify=1` (`window.__syncVerify = true`, `SWIFTUIWEB_SYNC_VERIFY=1`) runs each skipped sync anyway. Anything it then writes into
  the document or sends to Swift is reported in `window.__syncVerifyReport` and as a console error. It does not see the bookkeeping a
  host keeps for later, which the host's own tests cover.

The WebMount reconciliation (which updates mounts whose content is not in the patch) and the image paints always run.

## A run of layout modifiers is one element

Every cost of a commit grows with the number of elements: the layout host describes, measures and places each one, the browser restyles
the ones a patch touches, and the worker reconciles a render node for each. A `frame`, `padding` or `fixedSize` modifier on its own would
make a wrapper `div`, and a wrapper with one child and no look of its own adds nothing to the screen.

A run of these modifiers shares one element (`_SemanticLayers` in `Sources/SwiftUIWebCore/SemanticLayout.swift`):

- The element is the outermost modifier's, with its own attributes (`data-layout-kind="frame"`, `data-frame-*`). The inner modifiers are
  layers in `data-layout-wrap`, outermost first, for example `padding;padding-top=8.0;...|fixed;fixed-x=true;...`.
- Padding around padding is the padding of the sum. The outer proposal minus the outer inset, minus the inner one, is the proposal minus
  the sum, so the sizes and origins add up. This holds for insets that are not negative; a negative inset keeps its own layer.
- Only a wrapper that is nothing but layout takes a layer. `isBareWrapper` requires that the wrapper has no key, text, event, task,
  binding, alignment guide, layout value, hover probe, tag, drag or drop descriptor or timeline; no attribute but the layout ones; no
  style but the layout ones and the neutral ones (`color`, `opacity`, the font properties); and no class but the three layer classes.
  Anything else belongs to the wrapper's own box, so a modifier applied to it (a background, a clip, a border, `onTapGesture`, an
  accessibility label, `id`) wraps it as usual.
- CSS has one box for the element. `CssLayout.chainPlan` folds the chain into it.
- The code that reads the wrapper elements reads the chain instead: `_frameFixesWidth` (the search for a `Spacer`),
  `_labelVisibleCornerStyles` (a button's visible shape) and the Swift measurement of a custom `Layout`
  (`_SemanticLayers.unfolded` gives back the wrapper chain with the sizing style of each layer).
- It is off below the panes of a split view (`_RenderContext._mergesLayoutLayers`), whose content the browser lays out with CSS. There,
  each wrapper's CSS is its layout.

A frame or padding around an element that is not a wrapper (a text, an icon, a stack) keeps a box of its own. The modifiers applied after
it (a background, a border, a gesture) belong to that box.

Checks:

- `Tools/test-css-layout-layers.mjs` lays out every chain of up to four layers (frame, padding and fixed, with several parameter sets,
  fractional insets, one or two children) once as wrapper elements and once as one element. The content must have the same rectangle, or
  the chain must be refused.
- `Tools/test-layout-layers-browser.mjs` checks that every shared element in the Showcase is styled by CSS layout.
- `SemanticLayerTests` compares the unfolded chain with what the modifiers make, and the measurement of a chain with that of its wrappers.

## Forced layouts in a commit

A script that reads geometry or computed style while the page has pending changes (`getBoundingClientRect`, `getClientRects`,
`offsetWidth`, `clientWidth`, `window.innerWidth` on a phone, `getComputedStyle(...)`, `focus()`) makes the browser recalculate style and
lay out at that point. One flush costs what the rendering step would have done anyway. The cost comes from writing and then reading
again: each read after a write flushes the work that write dirtied, so a patch of N elements that alternates reads and writes flushes
N times. The commit therefore keeps its reads and writes in phases:

| Phase of a commit | Reads | Writes | Flushes it causes |
| --- | --- | --- | --- |
| DOM patch (`patchChildren`) | starting and target style of an animated element | the patch; animations are created after all the reads | none of its own |
| tab shell (`AdaptiveTabShell.sync`) | the viewport width (cached, refreshed on `resize`) | `data-tab-*`, ARIA | none |
| `syncPlatform` | `clientWidth`, `innerHeight` (cached, refreshed on resize) | none | none |
| `layout.update()` | style and boxes of the semantic roots, intrinsic measurements | geometry styles | the first read, and one per measurement wave |
| geometry readers (`GeometryHost.sync`) | `getClientRects`, `getBoundingClientRect`, `client*` | none | the second, unavoidable flush |
| focus, scroll, presentations | visibility of the focus target, scroll offsets | focus, `inert` | usually none; `focus()` flushes once |

Two rules follow from the table:

- The tab shell reads the window width from a cache. The width changes only when the window or the visual viewport does.
- A patch reads the starting styles of its animated elements while it walks the tree. It writes nothing animated until the walk ends,
  reads the target styles together, and then creates the animations. The forced recalculations of a patch are therefore fixed in number,
  whatever the number of animated elements.

`Tools/test-forced-layouts-browser.mjs` (`make embedded-ui-test`) counts the forced style recalculations and layouts of a commit from
Chromium's trace, and names the script function that caused each one. `--report` prints the counts, and `--host-root <checkout>` runs
another checkout's `Tools/*.js` against the same fixture. The same script checks the icon writes listed below.

### Geometry is measured after the frame's layout

`GeometryHost.sync` observes new geometry views and forgets removed ones. It measures them in the next `ResizeObserver` delivery
(`measureAfterLayout`), which comes after the frame's layout and before its paint. The reads then need no extra layout, and the values
reach Swift in the same frame. The reports of one delivery go to Swift as one batch (`batch_begin` and `batch_end`), so Swift publishes
once.

The CSS mapper's pending islands are applied at the start of the layout pass, before its first read (`SemanticLayoutHost.flushCss`), so
the patch and the CSS share one forced style recalculation. An island claimed during the pass is styled at its end.

## Style invalidation in a commit

The number of flushes is fixed by the phases above. What each flush costs is the number of elements the browser restyles, which depends
on how much of the page a DOM change invalidates.

- **Selectors with nothing to hold on to.** A `:has()` whose subject is not named by the rule, combined with `:only-child` or `:not(...)`,
  invalidates the whole subtree whenever the `:has()` might have changed. The rules put the `:has()` on the element the rule styles, for
  example `.frame-box > :only-child:is([data-flexible-width="true"], :has([data-flexible-width="true"]))`, and split the icon rule into
  sibling forms (`.symbol-icon ~ :not(.symbol-icon)` and `:not(.symbol-icon):has(~ .symbol-icon)`).
  `Tools/test-style-invalidation.mjs` checks that these selectors match the same elements as their plain forms on 2,000 random trees, and fails
  when a stylesheet rule puts a `:has()` on an ancestor of a subject with no class, tag, id or attribute.
- **Icons arrive with the patch.** The patch calls the icon adapter's `__realizeIcons` on a node while it is still detached, and on an icon
  whose symbol changed. An icon that keeps its symbol keeps its SVG. `data-lucide` and `data-lucide-fallback` belong to the adapter, not the
  patch. The `MutationObserver` stays for what the patch does not insert (the first mount before the adapter loads, host-built nodes).
  `Tools/test-forced-layouts-browser.mjs` checks the fixture's icons (inserted, kept, changed and unknown symbols) when the commit returns,
  before any observer callback.
- **Highlight inheritance.** Chromium inherits `::selection` highlight styles from the parent element. A universal `::selection` rule with a
  `var()` value therefore gives every element a highlight style. The runtime marks the root with `data-highlight-inheritance` when a probe
  shows the engine inherits highlights (`markHighlightInheritance` in `Tools/embedded-dom.js`). The tinted selection rule is then declared
  only on the elements that change `--color-swu-primary` (`:root`, `[data-tint]`, `[data-color-scheme]`, `.dark`). Elsewhere the rule is
  `:root:not([data-highlight-inheritance]) ::selection`. `Tools/test-selection-highlight.mjs` checks on Chromium and WebKit that plain,
  tinted and dark-scheme text keep their tint, and fails when a universal `::selection` returns.

## An icon stays an inline SVG

`Image(systemName:)` is a `span.symbol-icon` with the Lucide `<svg>` inside it, three or four elements per icon. A CSS mask on the span
gives one element per icon instead, but the browser draws an SVG image much more slowly than inline paths, so the cost moves to paint.
On the standard scenario of `Tools/perf-ab.mjs` the mask made long tasks and blocking time worse, and it is not used. A CSS image is also
drawn at a whole-pixel tile, so at fractional icon sizes the mask is off by up to half a pixel. The `<use>` form of a shared symbol was
slower too. Icons stay inline SVG.

## The host is not sent what it holds

The host (`Tools/embedded-dom.js`) keeps the tree it has. A publication lists only what changed since the epoch the host acknowledged
(`publish_ack`). A worker applies only the newest publication, so "held" always means "as of the acknowledged epoch". Binary records describe
the changes (see [`BINARY_PATCHES.md`](../Architecture/BINARY_PATCHES.md)).

- An element that the host holds and that did not change travels as a handle (`HELD`), whatever its tag and size.
- A fiber unchanged since the acknowledged epoch (`Fiber.version`) is not visited.
- Volatile fibers (lazy collections, secure fields, mounted host views) and elements that keep state in the host are visited with every
  publication.

`Tools/test-publication-browser.mjs` (`make publication-browser-test`) runs the Showcase through viewport changes and list inserts three
times: as usual; with `window.__fullPublish = true` (Swift is never acknowledged, so every publication is complete); and with a page that
acknowledges two publications late and drops some. Each run must be applied as records without a request for a full publication, and the
three pages must end up identical.
