# SwiftUIWeb documentation

The project overview is the root [`README.md`](../README.md). Each top-level folder has its own README:
[`Sources`](../Sources/README.md), [`Examples`](../Examples/README.md), [`Plugins`](../Plugins/README.md),
[`Tools`](../Tools/README.md) and [`Tests`](../Tests/README.md).

## Building an app

Start here if you want to write an app with SwiftUIWeb.

- [Quickstart](QUICKSTART.md): requirements, a first app, running it, testing it, and what to do when something fails
- [Sharing code with an Apple app](SHARING_CODE.md): one set of SwiftUI views for iOS and the web
- [Deploying](DEPLOYMENT.md): the release bundle and how to set up a static host
- [Browser application shell and styling](BROWSER_APP_SHELL.md): the page head, addresses per screen, the tab shell,
  fonts, colors and the Content-Security-Policy
- [What does not work, or works differently](LIMITATIONS.md): Combine, Foundation, Embedded Swift and the Apple
  frameworks with no browser counterpart
- [Feature matrix](FEATURE_MATRIX.md): every browser capability and the code that backs it
- [Web keychain, storage and sessions](Security/WEB_SECURITY.md)
- [Migration guide](MIGRATION.md): what to change when you update SwiftUIWeb

## How it works

For contributors, and for anyone curious about the runtime.

- [Architecture](ARCHITECTURE.md): the modules and how a change reaches the screen
- [Running the Swift side in a Web Worker](EmbeddedWorker.md)
- [Binary updates](Architecture/BINARY_PATCHES.md): the format Swift sends to the page
- [CSS layout](Architecture/CSS_LAYOUT.md): how SwiftUI layout becomes flexbox and grid
- [First paint](Architecture/FIRST_PAINT.md): the first screen prerendered into `index.html`
- [Motion](Architecture/MOTION.md): animations, transitions and content transitions
- [Observation contract](OBSERVATION_CONTRACT.md): which views a state change renders again
- [Concurrency and main-actor isolation](CONCURRENCY.md)
- [Embedded source lowering](EMBEDDED_SOURCE_LOWERING.md): what the build rewrites in your sources, and why
- [Release reachability](RELEASE_REACHABILITY.md): which optional browser features a release bundle carries

## Working on SwiftUIWeb

- [Contributing](../CONTRIBUTING.md) and the [development workflow](DEVELOPMENT_WORKFLOW.md): building, the test tiers and
  the development loop
- [Test, fixture and example layout](TEST_LAYOUT.md) and the [core test coverage contract](TEST_COVERAGE.md)
- [Public API and versioning](API/VERSIONING.md), with the [public API baseline](API/public-api.json)
- Performance: [contracts](Performance/PERFORMANCE_CONTRACTS.md) and [budgets](Performance/PERFORMANCE_BUDGETS.json),
  [frame budgets](Performance/FRAME_BUDGETS.md), [where the WebAssembly bytes go](Performance/WASM_SIZE.md),
  [build time](Performance/BUILD_TIME.md), [A/B benchmarks](Performance/AB_BENCHMARK.md), and
  [SwiftUIWeb against React](../Benchmarks/ReactComparison/README.md)

Generated bundles, reports and browser-test output belong under `.build/` and are not part of the documentation.
