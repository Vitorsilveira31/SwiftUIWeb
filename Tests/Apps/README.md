# Test apps

Executable apps that the tests build and drive in a real browser. They are not examples: they exist to exercise the
framework, and their code is written for that. Examples for people to learn from are in [`Examples`](../../Examples/README.md).

| App | What it is for |
|---|---|
| [`ShowcaseApp`](ShowcaseApp) | The component playground: a sidebar of working views for controls, layout, navigation, presentations, forms, collections, state, themes, `Canvas`, `Chart`, `Map` and file import/export. About 40 browser and tooling tests run against it (scrolling, presentation, accessibility, performance, security policy, lowering). `Tools/run-browser.sh showcase` serves it. |
| [`LayoutConformanceApp`](LayoutConformanceApp) | Layout cases whose boxes are compared with the ones SwiftUI reports on Apple platforms (`Tools/LayoutConformance`). |
| [`EmbeddedLoweringConformanceApp`](EmbeddedLoweringConformanceApp) | Many small fixtures (builders, Codable, controls, canvas, chrome) that exercise the source lowerer. It deliberately uses normal KeyPath spelling; the build lowers a disposable copy. |
| [`WebMountExample`](WebMountExample) | A tiny controller proving that an unrelated update does not recreate a native element (typing in an input survives a SwiftUI button press). |
| [`MediaProbeApp`](MediaProbeApp) | A player over short generated clips with one button per thing the tests read; it logs what Swift saw, in the Worker or on the main thread. Run by `make media-worker-test`. |
| [`MotionApp`](MotionApp) | One section per piece of SwiftUI motion, each with a long linear animation the test can sample: insertion and removal transitions, the default fade, sliding siblings, numeric text, springs, symbol effects, scroll transitions and completions. Run by `make motion-browser-test`. |
| [`BoardBenchmarkApp`](BoardBenchmarkApp) | The board that is compared with the React version in `Benchmarks/ReactComparison`: a header, a stats screen and a list of generated works, with the same rows as the React board. |
| [`LazyCellStateApp`](LazyCellStateApp) | A view with state of its own in a cell of a `LazyVGrid`, in three shapes (its own state, a generic card that stores its content, state changed inside `withAnimation`), and the same cells in a `VStack` as the control. Run by `Tools/test-lazy-cell-state-browser.mjs`. |
| [`ViewTransitionApp`](ViewTransitionApp) | Matched-geometry pairs, a navigation zoom and pinned swaps, each with a name the view-transition browser test (`Tools/test-view-transition-browser.mjs`) can find. |

They are executable targets of the root package. Most are also listed under `products:` in `Package.swift`; SwiftPM builds an
executable target by name, so `SWIFTUIWEB_PRODUCT=<Target> Tools/run-browser.sh x` builds any of them, listed or not.

What ShowcaseApp covers, in more detail:

- getting-started composition (`Text`, `Image`, `Link`, `Button`, stacks, `Spacer`, `Divider`, modifiers, conditional content)
- controls and semantic content (`Toggle`, `Picker`, `Slider`, `Stepper`, `ColorPicker`, `ProgressView`, `Gauge`, `Label`,
  `GroupBox`, `DisclosureGroup`, `Menu`, `AsyncImage`)
- layout (stacks, custom `Layout`/`AnyLayout`, lazy grids, `GeometryReader`, `ViewThatFits`, draggable `HSplitView`/`VSplitView`)
- navigation (`NavigationSplitView`, `NavigationStack`, typed `NavigationLink`, `NavigationPath`, titles and toolbars)
- presentation (`sheet`, `fullScreenCover`, `popover`, `alert`, `confirmationDialog`, overlays, a toast)
- forms and bindings (`TextField`, `SecureField`, `TextEditor`, `DatePicker`, validation, submit actions)
- collections and identity (`List`, `ForEach`, `Table`, `OutlineGroup`, reorderable rows, drag and drop; large keyed rows use
  the lazy visible-range engine while small collections stay eager)
- state and themes (`@State`, `@Binding`, adaptive `TabView`, live light/dark scheme)
- advanced integrations (`Canvas`, `Chart`, `Map`, `WebContentView`, `ShareLink`, accessibility metadata, refresh)
