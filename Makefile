SHELL := /bin/sh
.DEFAULT_GOAL := help

# Swift 6.4 is the repository baseline. Native Makefile targets use the
# compiler selected by PATH; browser scripts resolve the Embedded WebAssembly SDK.
SWIFT ?= swift
# The package's tests write generated artifacts in the workspace;
# disabling SwiftPM's per-test sandbox keeps the command deterministic on
# macOS runners and in restricted developer sandboxes.
SWIFT_TEST_FLAGS = --enable-swift-testing --disable-xctest --no-parallel --disable-sandbox
CONFIGURATION ?= debug
# What the browser suites of `browser-test` build: debug compiles in about a third of the time of release; the nightly
# run (release-browser-test) runs the same suites on release bundles.
SUITE_CONFIGURATION ?= debug
EXAMPLE ?= site
BUNDLE ?= .build/browser/ShowcaseApp
PRODUCTS := ShowcaseApp ShowcaseSite BoardBenchmarkApp Lumio Quill Seekr Neighborly Stayly Mailo WebMountExample MediaExample AVKitExample PhotosPickerExample MapKitExample UserNotificationsExample SecurityExample

# WEBKIT=0 leaves out every WebKit run of the browser suites; Chromium still runs. CI on Linux sets it and runs WebKit on macOS:
# Playwright's WebKit crashes and hangs at random on x86_64 Linux, while it passes on macOS and on aarch64 Linux.
WEBKIT ?= 1
WEBKIT_ONLY = $(if $(filter 0,$(WEBKIT)),@echo "Skipped (WEBKIT=0):",)
ON_WEBKIT = $(WEBKIT_ONLY) SWIFTUIWEB_BROWSER_ENGINE=webkit
ifeq ($(WEBKIT),0)
# The suites that run both engines themselves.
export HEADLESS_PLAYER_ENGINES ?= chromium
export MEDIA_WORKER_ENGINES ?= chromium
export AVKIT_CONTROLS_ENGINES ?= chromium
export SELECTION_HIGHLIGHT_ENGINES ?= chromium
endif

# `make run site` is supported in addition to the usual
# `make run EXAMPLE=site` form. The first goal after `run` wins.
REQUESTED_EXAMPLE := $(word 1,$(filter-out run snapshot,$(MAKECMDGOALS)))
SELECTED_EXAMPLE := $(if $(REQUESTED_EXAMPLE),$(REQUESTED_EXAMPLE),$(EXAMPLE))

.PHONY: plugin-test-quick cross-package-test
.PHONY: swiftui-parity swiftui-parity-update swiftui-parity-rewrite-baseline browser-release geometry-test geometry-browser-test tools-test test-layout docs-test feature-matrix feature-matrix-write plugin-test server-test universal-app-test universal-app-ios-test universal-app-web-test universal-app-browser-test api-diff api-diff-update api-availability doctor bundle-sizes coverage
.PHONY: media-worker-test markdown-probe-test trio-web trio-web-build trio-browser-test
.PHONY: example-web example-web-build example-web-build-all example-browser-test
.PHONY: setup help toolchain build test architecture-check architecture-audit full-test reachability-test browser-test-setup integration-release-test run snapshot styles wasm-size wasm-size-check clean list \
        site lumio quill seekr neighborly stayly mailo web-mount webmount media media-example avkit avkit-example photos-picker photospicker map mapkit notifications user-notifications security webkit

setup:
	Tools/setup.sh

# Strict browser production build. Every reachable Swift runtime target is
# compiled with Embedded Swift; unsupported functionality is a hard failure.
browser-release:
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh "$(EXAMPLE)"

# Development loop: build the project site (or PRODUCT=...), serve it, and when a source file is saved rebuild what
# changed and reload the open page. A debug build, kept between runs in .build/dev-cache.
# A debug loop uses the development profile `fast`; SWIFTUIWEB_DEV_PROFILE=embedded make watch builds the module that ships
# (Documentation/DEVELOPMENT_WORKFLOW.md).
.PHONY: watch
watch:
	bun Tools/dev-watch.mjs --package-root "$(CURDIR)" --product "$(or $(PRODUCT),ShowcaseSite)" --configuration "$(CONFIGURATION)"

tools-test:
	bun Tools/run-scripts.mjs "test ./Tools/test-compile-assets.mjs ./Tools/test-compile-strings.mjs ./Tools/test-inject-app-head.mjs ./Tools/test-seal-csp.mjs ./Tools/test-first-paint.mjs ./Tools/test-hash-release-bundle.mjs ./Tools/test-precompress-bundle.mjs ./Tools/test-bun-server-encoding.mjs ./Tools/test-bun-server-api-proxy.mjs ./Tools/test-local-package-dependencies.mjs ./Tools/test-framework-url-dependency.mjs ./Tools/test-staging-layout.mjs ./Tools/test-patch-browser-index.mjs ./Tools/test-embedded-capabilities.mjs ./Tools/test-embedded-preflight.mjs ./Tools/test-strip-wasm.mjs ./Tools/test-wasm-split-release.mjs ./Tools/test-swiftuiweb-tools.mjs ./Tools/test-wasm-audit.mjs ./Tools/test-perf-ab-stats.mjs ./Tools/test-cloudflare-site-stage.mjs" "test ./Tools/test-text-format.mjs" "test ./Tools/test-unicode-data.mjs" "test ./Tools/test-audit-showcase-catalog.mjs" "Tools/audit-showcase-catalog.mjs" "test ./Tools/test-compare-react.mjs ./Tools/test-compare-react-orders.mjs ./Tools/test-publish-react-comparison.mjs" "test ./Tools/test-mock-jsonplaceholder.mjs" "Tools/publish-react-comparison.mjs --check" "Tools/test-audits.mjs" "Tools/test-cloudflare-site-prerender.mjs" "Tools/audit-no-python.mjs" "Tools/test-audit-no-python.mjs" "Tools/audit-private-terms.mjs" "Tools/test-audit-private-terms.mjs" "Tools/test-bundle-reuse.mjs" "Tools/test-run-test-groups.mjs" "Tools/test-run-scripts.mjs" "Tools/test-swiftui-api-parity.mjs" "Tools/swiftuiweb-tools.mjs browser-io-protocol --check" "Tools/swiftuiweb-tools.mjs binary-atoms --check"
	bun build --no-bundle --target=bun Tools/BrowserIO/browser-io.mjs > /dev/null

test-layout:
	bun Tools/audit-test-layout.mjs

docs-test:
	bun Tools/audit-docs.mjs

feature-matrix:
	bun Tools/swiftuiweb-tools.mjs feature-matrix --check

feature-matrix-write:
	bun Tools/swiftuiweb-tools.mjs feature-matrix --write

api-diff:
	bun Tools/api-contract.mjs --check

api-availability:
	bun Tools/api-contract.mjs --check-availability

api-diff-update:
	bun Tools/api-contract.mjs --update

# Compares the public API with Apple's SwiftUI symbol graph (needs Xcode; the baseline matches Xcode 27.2, which the
# macOS CI job pins). Signature divergences are gated too.
swiftui-parity:
	bun Tools/swiftui-api-parity.mjs --generate --check --strict-signatures

# Prunes baseline entries that now match Apple; never adds entries.
swiftui-parity-update:
	bun Tools/swiftui-api-parity.mjs --generate --update

# Regenerates the whole baseline, adding every divergence. Review the diff before committing.
swiftui-parity-rewrite-baseline:
	bun Tools/swiftui-api-parity.mjs --generate --rewrite-baseline

plugin-test:
	bun Tools/test-swiftuiweb-plugin.mjs

# The plugin contract without compiling the Showcase (about a minute): the launcher help and its
# diagnostics only. CI runs the full `plugin-test`.
plugin-test-quick:
	bun Tools/test-swiftuiweb-plugin.mjs --skip-build

# Three tiers. `test` checks the Swift code and the tooling without a browser (about a minute and a half): run it after
# every edit. `browser-test` is what a pull request must pass: the source lowerer and every suite that drives the real
# Embedded bundle in Chromium and WebKit, built as it ships (release) or in the default development profile. `nightly-test`
# adds `example-test` (the example apps, the CSP of every bundle, first paint, the consumer packages and the SwiftPM
# plugin's full build, and the other configurations: Embedded debug and the Embedded development profile), coverage,
# size and performance.
#
# A browser suite builds its bundle with BUILD_ONLY=1, and a build from unchanged inputs reuses the bundle already there or
# the copy kept from its last build (Tools/bundle-reuse.mjs), so each application compiles once per configuration. The
# groups below run at the same time (Tools/run-test-groups.mjs); a group holds the targets that write the same bundle
# folder or development cache, which run one after another. Each target's log is in .build/test-logs.
# browser-test first builds the bundles the suites share (one after another: a build already uses every core), then runs
# every group at the same time; the suites only read those bundles. A group holds targets that write the same folder.
BROWSER_BUNDLES = "bundles: browser-bundles"
# The layout conformance check compares the browser with SwiftUI itself (Tools/LayoutConformance/run-apple.sh needs Xcode),
# so it joins browser-test on macOS only; CI runs it in the macOS job. So does the CSS layout oracle: it compares the frames
# CSS lays out with the ones SwiftUI measured with the system font of Apple's platforms, and the text of any other platform
# measures differently (Linux's Chromium draws `system-ui` with another face), so every node with text would miss.
ifeq ($(shell uname -s),Darwin)
CONFORMANCE_GROUP = "conformance: layout-conformance css-layout-oracle"
endif
BROWSER_GROUPS = \
	"controls: controls-browser-test" "controls-a11y: controls-accessibility-test" "presentation: presentation-browser-test" \
	"focus: focus-browser-test" "identity: identity-browser-test" "scrolling: scrolling-browser-test" \
	"accessibility: accessibility-browser-test" "publication: publication-browser-test" "webkit: webkit-browser-test" \
	"lowering: lowering-unit-test lowering-test" $(CONFORMANCE_GROUP) "integrated: integrated-check" \
	"security: security-browser-test" "runtime: single-browser-runtime-audit server-test plugin-test-quick" \
	"direct-build: direct-build-test" "live-literals: live-literals-browser-test" "state-reload: state-reload-browser-test" \
	"hot-swap: hot-swap-browser-test"
# csp-bundles-test builds every release bundle the Makefile knows, so it runs before the groups, which then reuse them.
EXAMPLE_GROUPS = \
	"showcase: embedded-showcase-test integration-release-test" \
	"board-site: lazy-rows-browser-test lazy-cell-state-browser-test showcase-site-test first-paint-browser-test wasm-split-browser-test" \
	"apps: lumio-test quill-test seekr-test neighborly-test stayly-test mailo-test" \
	"media: media-worker-test" "universal: universal-app-browser-test first-route-browser-test" \
	"consumers: cross-package-test consumer-regression plugin-test web-command-test" \
	"hostile-values: hostile-values-browser-test" \
	"variants: dev-profile-test live-literals-embedded-test state-reload-embedded-test" \
	"lowering-debug: embedded-link-debug-test"
MEASUREMENTS = memory-test coverage wasm-size-check perf-ci

.PHONY: browser-bundles browser-test release-browser-test example-test nightly-test
browser-bundles:
	BUILD_ONLY=1 CONFIGURATION=$(SUITE_CONFIGURATION) Tools/run-browser.sh showcase
	BUILD_ONLY=1 CONFIGURATION=$(SUITE_CONFIGURATION) Tools/run-browser.sh lowering
	SWIFTUIWEB_PRODUCT=SecurityExample BUILD_ONLY=1 CONFIGURATION=$(SUITE_CONFIGURATION) Tools/run-browser.sh x

browser-test:
	bun Tools/run-test-groups.mjs $(BROWSER_BUNDLES)
	bun Tools/run-test-groups.mjs $(BROWSER_GROUPS)

# The same suites on release bundles, what ships (nightly).
release-browser-test:
	$(MAKE) --no-print-directory browser-test SUITE_CONFIGURATION=release

example-test:
	bun Tools/run-test-groups.mjs "csp: csp-bundles-test"
	bun Tools/run-test-groups.mjs $(EXAMPLE_GROUPS)

nightly-test: browser-test release-browser-test example-test
	@for target in $(MEASUREMENTS); do $(MAKE) --no-print-directory $$target || exit $$?; done

# Every browser bundle the Makefile builds loads under the Content-Security-Policy it ships with, without a violation. The test
# derives the products from this Makefile and fails if one has no bundle, so a product added elsewhere must be built here too.
csp-bundles-test:
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh showcase
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh lowering
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh site
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh board
	SWIFTUIWEB_PRODUCT=MediaProbeApp BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh media
	SWIFTUIWEB_PRODUCT=SecurityExample BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh x
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh neighborly
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh mailo
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh stayly
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh lumio
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh quill
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh seekr
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh photos-picker
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh notifications
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh motion
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh view-transition
	bun Tools/test-csp-bundles.mjs

# An application-shaped package compiled against this checkout: lowered sources, generated strings, aliased SwiftUI.
# Catches declarations that compile inside SwiftUIWeb but are invisible to a consumer package.
cross-package-test:
	bun Tools/test-cross-package-consumer.mjs

server-test:
	bun Tools/test-server-lifecycle.mjs

# The universal example is one shared SwiftUI-shaped app compiled for both
# Apple platforms and SwiftUIWeb's Embedded browser runtime. Keep both builds
# in CI so API drift cannot silently break one host.
universal-app-test: universal-app-ios-test universal-app-web-test

universal-app-ios-test:
	xcodebuild -quiet -project Examples/UniversalApp/Darwin/UniversalApp.xcodeproj \
		-scheme UniversalApp -sdk iphonesimulator \
		-destination 'generic/platform=iOS Simulator' -configuration Debug \
		CODE_SIGNING_ALLOWED=NO -derivedDataPath .build/universal-app-ios build

universal-app-web-test:
	mkdir -p .build/universal-app-plugin-cache/clang .build/universal-app-plugin-cache/swift
	CLANG_MODULE_CACHE_PATH="$(CURDIR)/.build/universal-app-plugin-cache/clang" \
	SWIFT_MODULECACHE_PATH="$(CURDIR)/.build/universal-app-plugin-cache/swift" \
		$(SWIFT) package --disable-sandbox plugin swiftuiweb \
		--path Examples/UniversalApp --product UniversalWebApp

universal-app-browser-test: universal-app-web-test
	bun Tools/test-universal-app-browser.mjs \
		--bundle .build/plugins/SwiftUIWebPlugin/outputs/browser/UniversalWebApp

# Examples/Trio: one Skip Fuse package for iOS and Android whose shared sources also build for the browser (the layout
# of a Skip Fuse app). The web build is the same package with SWIFTUIWEB_EMBEDDED=1; module aliases let the shared
# files keep `import SwiftUI` / `import Foundation`.
TRIO_WEB_ENV = SWIFTUIWEB_MODULE_ALIASES=1 SWIFTUIWEB_PACKAGE_ROOT="$(CURDIR)/Examples/Trio" \
	SWIFTUIWEB_BUILD_ROOT="$(CURDIR)/.build/trio-web" SWIFTUIWEB_BUNDLE_ROOT="$(CURDIR)/.build/browser/TrioWeb"

trio-web:
	$(TRIO_WEB_ENV) CONFIGURATION=debug Tools/run-browser-embedded.sh TrioWeb

trio-web-build:
	$(TRIO_WEB_ENV) BUILD_ONLY=1 CONFIGURATION=debug Tools/run-browser-embedded.sh TrioWeb

trio-browser-test: trio-web-build
	bun Tools/test-trio-browser.mjs .build/browser/TrioWeb/TrioWeb

# The small apps: fifteen apps (Examples/MonthCalendar ... Examples/PhotoEditor), one package each, for iOS and the browser. They are ordinary iOS SwiftUI that
# exists to find what the browser host cannot do yet. EXAMPLE picks one: `make example-web EXAMPLE=Skies`.
EXAMPLE_APPS = MonthCalendar Sparkline Carousel SwipeDeck MotionGallery ShapeGallery CanvasGallery MarkdownReader \
	TextStudies WrapAround Skies PocketOS StoreMap ClipPlayer PhotoEditor
EXAMPLE ?= Sparkline
example_env = SWIFTUIWEB_MODULE_ALIASES=1 SWIFTUIWEB_PACKAGE_ROOT="$(CURDIR)/Examples/$(1)" \
	SWIFTUIWEB_BUILD_ROOT="$(CURDIR)/.build/example-web/$(1)" SWIFTUIWEB_BUNDLE_ROOT="$(CURDIR)/.build/browser/Examples/$(1)"

example-web:
	$(call example_env,$(EXAMPLE)) CONFIGURATION=debug Tools/run-browser-embedded.sh $(EXAMPLE)Web

example-web-build:
	$(call example_env,$(EXAMPLE)) BUILD_ONLY=1 CONFIGURATION=debug Tools/run-browser-embedded.sh $(EXAMPLE)Web

example-web-build-all:
	@for example in $(EXAMPLE_APPS); do $(MAKE) --no-print-directory example-web-build EXAMPLE=$$example || exit 1; done

example-browser-test: example-web-build-all
	bun Tools/test-examples-browser.mjs .build/browser/Examples $(EXAMPLE_APPS)

geometry-test:
	bun Tools/test-platform-geometry.mjs

# GeometryReader / onGeometryChange / coordinate spaces through the real
# Embedded Swift + JavaScript host bundle.
geometry-browser-test:
	BUILD_ONLY=1 CONFIGURATION=debug Tools/run-browser.sh lowering
	bun Tools/test-geometry-browser.mjs .build/browser/EmbeddedLoweringConformanceApp

help:
	@echo "  make integrated-check           Validate server/ABI/source contracts"
	@echo "  make css-layout-oracle          Compare CSS layout with SwiftUI's frames (macOS: the frames use Apple's system font)"
	@echo "  make browser-contract-test      Real Chromium adapters with explicit wire fixtures"
	@echo "  make lazy-rows-browser-test    Board benchmark: a selection and a favorite show in the publication that answers the click, and after a scroll"
	@echo "  make motion-browser-test         Transitions in and out, sliding siblings, numeric text and springs in Chromium and WebKit"
	@echo "  make live-literals-browser-test  A save that only changes literal values is shown by the running page, state kept (both development profiles)"
	@echo "  make state-reload-browser-test   A reload of the development loop keeps the page's plain state (both development profiles)"
	@echo "  make hot-swap-browser-test       An application edit is loaded into the running page as a side module: no reload, the state kept"
	@echo "  make web-command-test            swift package web init writes ./swiftweb, which reports the toolchain, builds and serves the development loop"
	@echo "  make direct-build-test           The development loop compiles a save by replaying the recorded compiler commands, and hands unknown saves to swift build"
	@echo "  make dev-profile-test            The development profile fast (full Swift, regular WebAssembly) passes the motion, showcase and identity suites in Chromium"
	@echo "  make lazy-cell-state-browser-test  A view with state of its own in a LazyVGrid cell redraws when it changes, as in a plain stack (Chromium and WebKit)"
	@echo "  make view-transition-browser-test  A matched swap runs one view transition with the final DOM of the page without transitions (Chromium and WebKit)"
	@echo "  make redacted-skeleton-browser-test  Redacted placeholder paints a skeleton; unredacted subtrees keep their look, privacy blurs (Chromium and WebKit)"
	@echo "  make first-paint-browser-test  First screen prerendered into index.html: painted before the wasm, no shift, verify mode (SWIFTUIWEB_FIRST_PAINT=1 turns it on for a release build)"
	@echo "  make wasm-split-browser-test   app.wasm split by the first screen (SWIFTUIWEB_WASM_SPLIT=1): the rest loads behind it, a call that needs it waits (Chromium and WebKit)"
	@echo "  make first-paint-measure BUNDLE=<dir> [NETWORK=fast|slow] [CPU=1|4]  FCP, LCP, mount time and layout shift of a release bundle"
	@echo "  make cloudflare-site-check     Build the project site and validate its Cloudflare Worker without uploading"
	@echo "  make cloudflare-site-deploy    Build the project site and deploy it to Cloudflare (cf auth login, or CLOUDFLARE_API_TOKEN)"
	@echo "  make identity-test              Run semantic Fiber identity regressions"
	@echo "  make identity-fuzz-test        Run deterministic identity fuzzing"
	@echo "  make identity-browser-test     Run real Embedded DOM/focus/presentation identity checks"
	@echo "  make layers-browser-test       Check that shared frame/padding/fixedSize elements are styled by CSS layout"
	@echo "  make publication-browser-test  Check what Swift publishes: placeholders for what the host holds, same page as full publications"
	@echo "  make binary-publication-test   Check the binary publication: the encoder's fixtures, and the page building the parser's DOM from them"
	@echo "  make scrolling-test            Run semantic ScrollView viewport tests"
	@echo "  make scrolling-browser-test    Run real Embedded nested/anchor/restore scrolling checks"
	@echo "  make presentation-test         Run semantic presentation/focus unit tests"
	@echo "  make presentation-browser-test Run real Embedded presentation lifecycle checks"
	@echo "  make focus-browser-test        Run real Embedded focus and keyboard checks"
	@echo "  make controls-test             Run semantic control behavior regressions"
	@echo "  make controls-browser-test     Run real Embedded control and IME checks"
	@echo "  make controls-accessibility-test Run real Embedded control accessibility checks"
	@echo "  make accessibility-test        Run semantic accessibility backend tests"
	@echo "  make accessibility-browser-test Run real Embedded Chromium accessibility-tree checks"
	@echo "  make reading-order-browser-test Run real Embedded DOM/Tab/geometry/a11y order checks"
	@echo "  make button-highlight-browser-test Run real button highlight, focus and hit-area shape checks"
	@echo "  make accessibility-audit       Validate the accessibility capability matrix and backend"
	@echo "  make perf-test                 Run release Swift performance contracts"
	@echo "  make memory-test               Run release lifetime and leak contracts"
	@echo "  make perf-browser-test         Run release artifact and browser performance contracts"
	@echo "  make render-commit-benchmark   Opt-in render-commit benchmark -> .build/performance/render-commit.json"
	@echo "  make perf-report               Write JSON and Markdown performance reports"
	@echo "  make perf-ci                   Run all checked-in performance contracts"
	@echo "  make perf-frames               Measure a built app bundle against the frame-time budgets (BUNDLE=, SCENARIO=)"
	@echo "  make perf-frames-check         Evaluate a frame measurement file against the frame-time budgets"
	@echo "  make integration-release-test   Rebuild and test real Swift/WASM Showcase"
	@echo "  make universal-app-test         Build the shared iOS + Embedded app example"
	@echo "  make universal-app-browser-test Exercise Settings behavior in real Chromium"
	@echo "  make trio-web                   Run the Trio example (iOS, Android and the Web) in the browser"
	@echo "  make trio-browser-test          Build the Trio web bundle and check it in the browser"
	@echo "  make setup                      Install/check Bun and validate Swift/WASM SDK"
	@echo "  make browser-test-setup         Install the Playwright browsers (Chromium, WebKit, Firefox)"
	@echo "  make watch                      Dev loop: build, serve, rebuild and reload the page when a file is saved"
	@echo "The runtime and every tool are Swift and JavaScript; the first browser build compiles the source lowerer (swift-syntax)."
	@echo "  make doctor                     List every missing build tool at once (installs nothing)"
	@echo "  make bundle-sizes BUNDLE=.build/browser/ShowcaseApp   Inventory final assets"
	@echo "  make browser-release EXAMPLE=site   Build the Embedded Swift release"
	@echo "  make tools-test                Test build/parser/measurement tooling"
	@echo "  make test-layout              Check Sources/Examples/Tests boundaries"
	@echo "  make plugin-test-quick        Plugin launcher contract without compiling the Showcase"
	@echo "  make browser-test             What a pull request must pass: the lowerer and every real-browser suite"
	@echo "  make release-browser-test     The browser suites on release bundles (what ships; nightly)"
	@echo "  make security-browser-test    The SwiftUIWebSecurity keychain (SecurityExample) in Chromium and WebKit"
	@echo "  make webkit-browser-test      The interaction suites again on WebKit (the engine of Safari)"
	@echo "  make example-test             The example apps, the CSP of every bundle, first paint and the consumer packages"
	@echo "  make nightly-test             browser-test, example-test, coverage, size and performance"
	@echo "  make csp-bundles-test         Every built example bundle loads under its shipped CSP without a violation"
	@echo "  make docs-test                Check local Markdown links"
	@echo "  make feature-matrix           Validate supported/fallback/unsupported/no-op capabilities"
	@echo "  make feature-matrix-write     Regenerate the checked-in capability matrix"
	@echo "  make plugin-test              Validate the official SwiftPM plugin and bundle contract"
	@echo "  make server-test              Validate Bun port errors and Ctrl-C cleanup"
	@echo "  make api-diff                 Check the checked-in public API baseline"
	@echo "  make api-diff-update          Review and update the public API baseline"
	@echo "  make api-availability         Validate public @available annotations"
	@echo "  make lowering-unit-test        Test the Swift source lowerer: its unit tests and the golden output"
	@echo "  make geometry-test             Compile/run isolated platform geometry checks"
	@echo "  make geometry-browser-test     GeometryReader/onGeometryChange/coordinate spaces in Chromium"
	@echo "Wasm size and Embedded diagnostics"
	@echo "  make wasm-audit BUNDLE=...      Audit exact sections and local asset sizes"
	@echo "  make wasm-budget BUNDLE=...     Require local runtime payload < 3,000,000 Brotli bytes"
	@echo "  make embedded-preflight         Probe the actual compiler; not an application build"
	@echo "  make embedded-core-check WASM_SDK=...   Attempt the actual Core with an Embedded SDK"
	@echo "  make lowering-test             Golden, idempotence and real Embedded lowering fixture"
	@echo "  Embedded browser builds are strict: unsupported reachable Swift code fails instead of falling back."
	@echo "SwiftUIWeb examples"
	@echo "  make run requires a matching Swift WASM SDK and a local static server"
	@echo "  Bun is required for the browser server and JS tooling; Node.js/npm are not used"
	@echo "  make run                         Run the project site"
	@echo "  make run site                    Same, by name"
	@echo "  make run lumio                  Run Lumio, a photo-sharing feed over a local jsonplaceholder-shaped API"
	@echo "  make run quill                  Run Quill, an X-like short-posts feed over a local jsonplaceholder-shaped API"
	@echo "  make run seekr                  Run Seekr, a web search over the posts, pictures and people of the local API"
	@echo "  make run neighborly              Run Neighborly, a social network (feed, photos, profiles) over the same local API"
	@echo "  make run stayly                 Run Stayly, an accommodation search, stay pages and reservations over the same local API"
	@echo "  make run mailo                  Run Mailo, a mail client (folders, reading, compose and reply) over the same local API"
	@echo "  make run web-mount              Run the internal incremental DOM fixture"
	@echo "  make run media                  Run the AVFoundation-shaped media fixture"
	@echo "  make run avkit                  Run the SwiftUIWebAVKit MP4/HLS/DASH fixture"
	@echo "  make run photos-picker         Run the browser PhotosPicker fixture"
	@echo "  make run map                   Run the keyless SwiftUIWebMapKit fixture"
	@echo "  make run notifications          Run the browser UserNotifications fixture"
	@echo "  make run security                Run SecurityExample, the SwiftUIWebSecurity keychain demo"
	@echo "  make run webkit                  Run WebKitExample, WebContentView with navigation state"
	@echo "  make snapshot site               Print the static Fiber HTML snapshot"
	@echo "  make run EXAMPLE=site            Equivalent explicit form"
	@echo "  CONFIGURATION=release make run site  Build an optimized browser bundle"
	@echo "  SWIFTUIWEB_RELEASE_PROFILE=fast CONFIGURATION=release make run site  Release build in about half the time, larger wasm (previews, CI)"
	@echo "  SWIFTUIWEB_OPEN_BROWSER=1 make run site   Also open the default browser"
	@echo "  make styles                      Build the browser stylesheet from Tools/styles.css"
	@echo "  make wasm-size                  Build/analyze the Embedded Showcase WASM"
	@echo "  make wasm-size-check            Compare Embedded size metrics with the checked-in baseline"
	@echo "  make embedded-core             Build/measure the Foundation-free Embedded Core probe"
	@echo "  WASM_SDK=<sdk-id> make run       Pin the WebAssembly SDK (also supports shell export)"
	@echo "  make build CONFIGURATION=release Build all products"
	@echo "  make test                         Run the test suite"
	@echo "  make coverage                    Audit/gate core line coverage (COVERAGE_BROWSER=1 adds Bun BrowserIO)"
	@echo "  make architecture-check          Verify renderer/module invariants"
	@echo "  make architecture-audit         Audit the consolidated single-runtime architecture"
	@echo "  make full-test                  Run the complete semantic, browser and performance suite"
	@echo "  make reachability-test             Test conservative release reachability/pruning"
	@echo "  make list                         List the supported examples"

list:
	@echo "site               -> ShowcaseSite (the project site: purpose, benefits, performance, components)"
	@echo "lumio              -> Lumio (photo sharing: feed, explore, profile; calls the mock API)"
	@echo "quill              -> Quill (short posts: timeline, composer, replies, trends; calls the mock API)"
	@echo "seekr              -> Seekr (web search: results, images, news; calls the mock API)"
	@echo "neighborly         -> Neighborly (social network: feed, photos, profile; calls the mock API)"
	@echo "stayly             -> Stayly (accommodation search, stay pages, reservations; calls the mock API)"
	@echo "mailo              -> Mailo (mail client: folders, reading, compose, reply; calls the mock API)"
	@echo "web-mount          -> WebMountExample (internal regression fixture)"
	@echo "media              -> MediaExample (AVFoundation-shaped playback)"
	@echo "avkit              -> AVKitExample (MP4, HLS and adaptive presentation)"
	@echo "photos-picker      -> PhotosPickerExample (image/video selection)"
	@echo "map                -> MapKitExample (keyless MapLibre-backed map)"
	@echo "notifications      -> UserNotificationsExample (permission and local notifications)"
	@echo "security           -> SecurityExample (keychain: store, find after reload, forget)"
	@echo "webkit             -> WebKitExample (WebContentView: a URL or HTML, navigation state)"

toolchain:
	@$(SWIFT) --version
	@echo "Expected Swift baseline: 6.4"

build:
	@set -e; for product in $(PRODUCTS); do \
		echo "Building $$product ($(CONFIGURATION))"; \
		$(SWIFT) build -c $(CONFIGURATION) --product "$$product"; \
	done

# The Swift suite and the JavaScript checks run at the same time (Tools/run-test-groups.mjs; logs in .build/test-logs).
test:
	bun Tools/run-test-groups.mjs "swift: swift-unit-test" "tools: tools-test test-layout docs-test feature-matrix api-diff api-availability"

.PHONY: swift-unit-test
swift-unit-test:
	$(SWIFT) test -c $(CONFIGURATION) $(SWIFT_TEST_FLAGS)

# Core coverage is deliberately separate from `test`: instrumentation makes a
# full run slower, while this target remains the single reproducible CI gate.
# BrowserIO needs loopback for its real HTTP fixture and is opt-in locally.
coverage:
	bun Tools/coverage.mjs --gate $(if $(filter 1 true yes,$(COVERAGE_BROWSER)),--browserio,)

architecture-check:
	bun Tools/check-architecture-invariants.js

architecture-audit: architecture-check single-browser-runtime-audit
	bun Tools/architecture-audit.mjs

full-test: integrated-check api-diff api-availability identity-test identity-fuzz-test scrolling-test presentation-test controls-test accessibility-test perf-test memory-test browser-release embedded-capabilities embedded-fallback-audit embedded-codable-test identity-browser-test scrolling-browser-test presentation-browser-test focus-browser-test controls-browser-test accessibility-browser-test perf-browser-test architecture-audit

reachability-test:
	bun Tools/test-release-reachability.js

embedded-core:
	Tools/build-embedded-core.sh --release

run:
	Tools/run-browser.sh "$(SELECTED_EXAMPLE)"

styles:
	bun Tools/build-styles.mjs .build/styles.css

wasm-size:
	bun Tools/wasm-size.mjs

wasm-size-check:
	bun Tools/wasm-size.mjs --check

snapshot:
	@case "$(SELECTED_EXAMPLE)" in \
	site|showcase-site) product=ShowcaseSite ;; \
	lumio) product=Lumio ;; \
	quill) product=Quill ;; \
	seekr) product=Seekr ;; \
	neighborly) product=Neighborly ;; \
	stayly) product=Stayly ;; \
	mailo) product=Mailo ;; \
	web-mount|webmount) product=WebMountExample ;; \
	media|media-example) product=MediaExample ;; \
	avkit|avkit-example) product=AVKitExample ;; \
	photos-picker|photospicker) product=PhotosPickerExample ;; \
	map|mapkit) product=MapKitExample ;; \
	notifications|user-notifications) product=UserNotificationsExample ;; \
		*) echo "Unknown example: $(SELECTED_EXAMPLE)" >&2; echo "Run 'make list' for available examples." >&2; exit 2 ;; \
	esac; \
	echo "Rendering static Fiber snapshot for $(SELECTED_EXAMPLE) ($(CONFIGURATION))"; \
	$(SWIFT) run -c $(CONFIGURATION) "$$product"

# Positional example names are parsed by `run`; these targets intentionally do
# nothing when make visits them as additional command-line goals.
site lumio quill seekr neighborly stayly mailo web-mount webmount media media-example avkit avkit-example photos-picker photospicker map mapkit notifications user-notifications security webkit:
	@:

clean:
	$(SWIFT) package clean
	rm -rf .build

doctor:
	Tools/toolchain-report.sh
bundle-sizes:
	bun Tools/measure-bundle.mjs "$(BUNDLE)"

# The source lowerer's own tests (Tools/SwiftUIWebLowering).
.PHONY: lowering-unit-test
lowering-unit-test:
	swift test --package-path Tools/SwiftUIWebLowering

WASM_AUDIT_BROTLI_QUALITY ?= 11
.PHONY: wasm-audit wasm-budget
# Audit an existing deployed bundle; a map is optional, never guessed.
wasm-audit:
	bun Tools/wasm-audit.mjs "$(BUNDLE)" --brotli-quality "$(WASM_AUDIT_BROTLI_QUALITY)" $(if $(LINK_MAP),--link-map "$(LINK_MAP)") $(if $(MAP_REFERENCE),--map-reference "$(MAP_REFERENCE)")

# Strictly less than 3,000,000 bytes, not less than or equal. Local assets only.
WASM_BROTLI_LIMIT ?= 3000000
wasm-budget:
	bun Tools/wasm-audit.mjs "$(BUNDLE)" --brotli-quality "$(WASM_AUDIT_BROTLI_QUALITY)" --max-brotli "$(WASM_BROTLI_LIMIT)" --output .build/wasm-audit/budget.json

.PHONY: embedded-preflight embedded-core-check lowering-test
embedded-preflight:
	bun Tools/embedded-preflight.mjs

# This is a compilation gate, not a claim that the whole browser is migrated.
embedded-core-check:
	bun Tools/embedded-preflight.mjs --compile-core --swift "$(SWIFT)" $(if $(WASM_SDK),--sdk "$(WASM_SDK)")

lowering-test: lowering-unit-test
	bun test ./Tools/test-lowering.mjs
	$(MAKE) embedded-link-test
	bun Tools/test-geometry-browser.mjs .build/browser/EmbeddedLoweringConformanceApp

# The link gate: the lowering fixture (URLSession through a registered URLProtocol, AVPlayer and VideoPlayer, environment
# key paths, optional task identities, AVURLAsset.load(.variants)) must link and run. The release bundle (what ships) runs
# every lowering suite, and lowering-test's geometry check reads it; embedded-link-debug-test (nightly) links and runs the
# debug configuration too, since dead-code stripping differs between them.
.PHONY: embedded-link-test embedded-link-debug-test
embedded-link-debug-test:
	BUILD_ONLY=1 CONFIGURATION=debug Tools/run-browser.sh lowering
	bun Tools/test-embedded-lowering-runtime.mjs .build/browser/EmbeddedLoweringConformanceApp

embedded-link-test:
	BUILD_ONLY=1 CONFIGURATION=$(SUITE_CONFIGURATION) Tools/run-browser.sh lowering
	bun Tools/test-embedded-lowering-runtime.mjs .build/browser/EmbeddedLoweringConformanceApp
	# CSS layout lays the lowering fixtures out, on Chromium and WebKit.
	bun Tools/test-css-layout-fixtures-browser.mjs .build/browser/EmbeddedLoweringConformanceApp
	$(ON_WEBKIT) bun Tools/test-css-layout-fixtures-browser.mjs .build/browser/EmbeddedLoweringConformanceApp
	# A player left behind by a closed view must not stop the page's buttons (section 12.22), on Chromium and WebKit, Worker and main thread.
	bun Tools/test-headless-player-siblings-browser.mjs .build/browser/EmbeddedLoweringConformanceApp
	# Owners that render again on their own, and focus that follows the person (section 12.25), on Chromium and WebKit, Worker and main thread.
	bun Tools/test-retained-owner-browser.mjs .build/browser/EmbeddedLoweringConformanceApp
	$(ON_WEBKIT) bun Tools/test-retained-owner-browser.mjs .build/browser/EmbeddedLoweringConformanceApp
	# Canvas drawing and the navigation-bar chrome of the lowering fixtures.
	bun Tools/test-canvas-browser.mjs .build/browser/EmbeddedLoweringConformanceApp
	bun Tools/test-consumer-gaps-browser.mjs .build/browser/EmbeddedLoweringConformanceApp
	bun Tools/test-oslog-browser.mjs .build/browser/EmbeddedLoweringConformanceApp
	$(ON_WEBKIT) bun Tools/test-oslog-browser.mjs .build/browser/EmbeddedLoweringConformanceApp

.PHONY: embedded-fallback-audit
embedded-fallback-audit:
	bun Tools/audit-embedded-fallbacks.mjs

# Contract tests for the Embedded application. The showcase target below
# exercises the real linked bundle.
.PHONY: lazy-rows-browser-test embedded-ui-test embedded-showcase-test showcase-site-test lumio-test quill-test seekr-test neighborly-test stayly-test mailo-test react-board-parity-test
embedded-ui-test:
	bun Tools/test-embedded-dom.mjs
	bun Tools/test-forced-layouts-browser.mjs

embedded-showcase-test:
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh showcase
	bun Tools/test-embedded-showcase.mjs

# The rows of a lazy list show what a click changed (a selection, a favorite) in the publication that answers it, and after a scroll.
lazy-rows-browser-test:
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh board
	bun Tools/test-lazy-rows-browser.mjs
	$(ON_WEBKIT) bun Tools/test-lazy-rows-browser.mjs

# A redacted placeholder paints a skeleton, `.unredacted()` ends it and privacy blurs (a fixture with the renderer's markup, Tools/styles.css).
.PHONY: redacted-skeleton-browser-test
redacted-skeleton-browser-test:
	bun Tools/test-redacted-skeleton-browser.mjs
	$(ON_WEBKIT) bun Tools/test-redacted-skeleton-browser.mjs

# A matched swap runs one view transition whose final DOM equals the page without transitions; none with reduced motion, without the
# API or for a duplicate name (Tests/Apps/ViewTransitionApp, Tools/test-view-transition-browser.mjs).
# SwiftUI motion in a real browser: insertion and removal transitions, sliding siblings, numeric text, springs
# (Tests/Apps/MotionApp, Tools/test-motion-browser.mjs).
.PHONY: motion-browser-test
motion-browser-test:
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh motion
	bun Tools/test-motion-browser.mjs
	SWIFTUIWEB_BROWSER_ENGINE=webkit bun Tools/test-motion-browser.mjs

# The development profile `fast` (SWIFTUIWEB_DEV_PROFILE=fast): the lowered sources compiled as full Swift for regular
# WebAssembly pass the suites the Embedded module passes. Its bundles go to .build/dev-profile, next to the Embedded ones.
# Chromium only: the WebKit that Playwright ships (26.0) crashes in its optimizing WebAssembly compiler on this module, and
# Safari 27 runs it (Documentation/Performance/BUILD_TIME.md, "The development profile").
DEV_PROFILE_BUNDLES = $(CURDIR)/.build/dev-profile/browser
# Live literals: the replacements of a save that only changes literal values reach the running page, which keeps its state
# (Tools/test-live-literals-browser.mjs), in both development profiles.
.PHONY: live-literals-browser-test
live-literals-browser-test:
	SWIFTUIWEB_LIVE_LITERALS=1 SWIFTUIWEB_DEV_PROFILE=fast SWIFTUIWEB_BUNDLE_ROOT=$(CURDIR)/.build/live-literals/fast BUILD_ONLY=1 CONFIGURATION=debug Tools/run-browser.sh motion
	SWIFTUIWEB_BROWSER_ENGINE=chromium bun Tools/test-live-literals-browser.mjs $(CURDIR)/.build/live-literals/fast/MotionApp

# The same in the Embedded development profile, in Chromium and WebKit (nightly).
.PHONY: live-literals-embedded-test
live-literals-embedded-test:
	SWIFTUIWEB_LIVE_LITERALS=1 SWIFTUIWEB_BUNDLE_ROOT=$(CURDIR)/.build/live-literals/embedded BUILD_ONLY=1 CONFIGURATION=debug Tools/run-browser.sh motion
	bun Tools/test-live-literals-browser.mjs $(CURDIR)/.build/live-literals/embedded/MotionApp
	$(WEBKIT_ONLY) SWIFTUIWEB_BROWSER_ENGINE=webkit bun Tools/test-live-literals-browser.mjs $(CURDIR)/.build/live-literals/embedded/MotionApp

# The direct build of the development profile `fast`: after one `swift build`, saves are compiled by replaying its recorded
# commands (Tools/dev-direct-build.mjs, Tools/test-direct-build.mjs).
# `swift package web init` and the ./swiftweb script it writes, on Tests/ConsumerRegression (Tools/test-web-command.mjs).
# The development loop's reload keeps the page's plain state: the page saves it and the next module starts from it
# (Sources/SwiftUIWebCore/StateSnapshot.swift, Tools/test-state-reload-browser.mjs), in both development profiles.
.PHONY: state-reload-browser-test
state-reload-browser-test:
	SWIFTUIWEB_DEV_PROFILE=fast SWIFTUIWEB_DEV_CACHE=$(CURDIR)/.build/state-reload/cache SWIFTUIWEB_BUNDLE_ROOT=$(CURDIR)/.build/state-reload/fast BUILD_ONLY=1 CONFIGURATION=debug Tools/run-browser.sh motion
	SWIFTUIWEB_BROWSER_ENGINE=chromium bun Tools/test-state-reload-browser.mjs $(CURDIR)/.build/state-reload/fast/MotionApp

# The same in the Embedded development profile, in Chromium and WebKit (nightly).
.PHONY: state-reload-embedded-test
state-reload-embedded-test:
	SWIFTUIWEB_DEV_PROFILE=embedded SWIFTUIWEB_DEV_CACHE=$(CURDIR)/.build/state-reload/cache SWIFTUIWEB_BUNDLE_ROOT=$(CURDIR)/.build/state-reload/embedded BUILD_ONLY=1 CONFIGURATION=debug Tools/run-browser.sh motion
	bun Tools/test-state-reload-browser.mjs $(CURDIR)/.build/state-reload/embedded/MotionApp
	$(WEBKIT_ONLY) SWIFTUIWEB_BROWSER_ENGINE=webkit bun Tools/test-state-reload-browser.mjs $(CURDIR)/.build/state-reload/embedded/MotionApp

# Hot swap (SWIFTUIWEB_HOT_SWAP=1): the application is a side module, and an edit of it is loaded into the running page
# (Tools/side-module.js, Tools/test-hot-swap-browser.mjs). Chromium, the engine of the profile fast's suites.
.PHONY: hot-swap-browser-test
hot-swap-browser-test:
	bun Tools/test-hot-swap-browser.mjs

.PHONY: web-command-test
web-command-test:
	bun Tools/test-web-command.mjs

.PHONY: direct-build-test
direct-build-test:
	bun Tools/test-direct-build.mjs

.PHONY: dev-profile-test
dev-profile-test:
	SWIFTUIWEB_DEV_PROFILE=fast SWIFTUIWEB_BUNDLE_ROOT=$(DEV_PROFILE_BUNDLES) BUILD_ONLY=1 CONFIGURATION=debug Tools/run-browser.sh motion
	SWIFTUIWEB_DEV_PROFILE=fast SWIFTUIWEB_BUNDLE_ROOT=$(DEV_PROFILE_BUNDLES) BUILD_ONLY=1 CONFIGURATION=debug Tools/run-browser.sh showcase
	SWIFTUIWEB_BROWSER_ENGINE=chromium MOTION_BUNDLE=$(DEV_PROFILE_BUNDLES)/MotionApp bun Tools/test-motion-browser.mjs
	SWIFTUIWEB_BROWSER_ENGINE=chromium bun Tools/test-embedded-showcase.mjs $(DEV_PROFILE_BUNDLES)/ShowcaseApp
	SWIFTUIWEB_BROWSER_ENGINE=chromium IDENTITY_BUNDLE=$(DEV_PROFILE_BUNDLES)/ShowcaseApp bun Tools/test-identity-browser.mjs

.PHONY: lazy-cell-state-browser-test
lazy-cell-state-browser-test:
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh lazy-cells
	bun Tools/test-lazy-cell-state-browser.mjs
	$(ON_WEBKIT) bun Tools/test-lazy-cell-state-browser.mjs

.PHONY: view-transition-browser-test
view-transition-browser-test:
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh view-transition
	bun Tools/test-view-transition-browser.mjs
	$(ON_WEBKIT) bun Tools/test-view-transition-browser.mjs

# The project site (Examples/ShowcaseSite) in Chromium and WebKit, in the Worker and on the main thread.
react-board-parity-test:
	(cd Benchmarks/ReactComparison/react-board && bun install --frozen-lockfile && bun build.mjs)
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh board
	bun Tools/test-react-board-parity.mjs

lumio-test:
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh lumio
	bun Tools/test-lumio-browser.mjs
	$(ON_WEBKIT) bun Tools/test-lumio-browser.mjs

# The Quill browser test (Examples/Quill), in Chromium and WebKit, in the Worker and on the main thread.
quill-test:
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh quill
	bun Tools/test-quill-browser.mjs
	$(ON_WEBKIT) bun Tools/test-quill-browser.mjs

# The Seekr search (Examples/Seekr) in a browser, in Chromium and WebKit, against the mock API.
seekr-test:
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh seekr
	bun Tools/test-seekr-browser.mjs
	$(ON_WEBKIT) bun Tools/test-seekr-browser.mjs
# The Neighborly browser test (Examples/Neighborly), in Chromium and WebKit, in the Worker and on the main thread.
neighborly-test:
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh neighborly
	bun Tools/test-neighborly-browser.mjs
	$(ON_WEBKIT) bun Tools/test-neighborly-browser.mjs
stayly-test:
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh stayly
	bun Tools/test-stayly-browser.mjs
	$(ON_WEBKIT) bun Tools/test-stayly-browser.mjs
mailo-test:
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh mailo
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh stayly
	bun Tools/test-mailo-browser.mjs
	$(ON_WEBKIT) bun Tools/test-mailo-browser.mjs

showcase-site-test:
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh site
	bun Tools/test-showcase-site-browser.mjs
	$(ON_WEBKIT) bun Tools/test-showcase-site-browser.mjs

# The project site on Cloudflare (Tools/cloudflare-site): a Worker that serves the ShowcaseSite release bundle as static
# assets. The deploy signs in with `cf auth login` on a workstation, or CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID
# in CI (.github/workflows/deploy-site.yml). The Cloudflare CLI needs Node.js 22.18 or later.
.PHONY: cloudflare-site-stage cloudflare-site-check cloudflare-site-deploy
cloudflare-site-stage:
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh site
	bun Tools/cloudflare-site/stage.mjs .build/browser/ShowcaseSite
	cd Tools/cloudflare-site && bun install --frozen-lockfile
cloudflare-site-check: cloudflare-site-stage
	cd Tools/cloudflare-site && node_modules/.bin/cf deploy --dry-run
cloudflare-site-deploy: cloudflare-site-stage
	cd Tools/cloudflare-site && node_modules/.bin/cf deploy --message "$$(git rev-parse --short HEAD)"

.PHONY: embedded-capabilities single-browser-runtime-audit
embedded-capabilities:
	bun Tools/embedded-capabilities.mjs

single-browser-runtime-audit:
	@bun Tools/check-single-browser-runtime.mjs

.PHONY: embedded-network-storage-test embedded-network-storage-browser
embedded-network-storage-test:
	bun Tools/BrowserIO/audit-browser-integration.mjs
	$(SWIFT) build --target SwiftUIWebBrowserIO -c release
	bun Tools/BrowserIO/test-host.mjs
	bun build --no-bundle --target=bun Tools/BrowserIO/browser-io.mjs > /dev/null
	bun Tools/test-browserio-download-progress.mjs
	bun Tools/test-browserio-persistence.mjs

# Manual: open http://127.0.0.1:8091/browser-smoke.html, reload once (test-browserio-persistence.mjs automates it).
embedded-network-storage-browser:
	bun Tools/serve-static.mjs Tools/BrowserIO 8091

# Consumer regression: an application outside the framework package that imports Apple's frameworks by name and
# builds for the Embedded browser through the launcher. The checkout directory must be SwiftUIWeb in any letter case
# (SwiftPM identifies a local package by its lowercased directory name).
.PHONY: consumer-regression
consumer-regression:
	SWIFTUIWEB_BUILD_ROOT=$(or $(SWIFTUIWEB_BUILD_ROOT),$(CURDIR)/.build/consumer-regression) BUILD_ONLY=1 CONFIGURATION=release $(SWIFT) Tools/swiftuiweb-run.swift --product ConsumerRegression --package-root Tests/ConsumerRegression --build-only

# Values from the network (far dates, huge numbers, deep JSON, odd URLs) in the Embedded build, where Int is 32 bits:
# none may trap the app (Tests/HostileValues, Tools/test-hostile-values-browser.mjs).
.PHONY: hostile-values-browser-test
hostile-values-browser-test:
	SWIFTUIWEB_BUILD_ROOT=$(or $(SWIFTUIWEB_BUILD_ROOT),$(CURDIR)/.build/hostile-values) BUILD_ONLY=1 CONFIGURATION=release $(SWIFT) Tools/swiftuiweb-run.swift --product HostileValues --package-root Tests/HostileValues --build-only
	bun Tools/test-hostile-values-browser.mjs $(or $(SWIFTUIWEB_BUILD_ROOT),$(CURDIR)/.build/hostile-values)/browser/HostileValues

.PHONY: css-layout-oracle
css-layout-oracle:
	bun Tools/css-layout-oracle.mjs --check

.PHONY: embedded-codable-test
embedded-codable-test:
	bun Tools/test-embedded-codable.mjs


.PHONY: csp-bundles-test stack-depth-browser-test first-route-browser-test first-paint-browser-test wasm-split-browser-test first-paint-measure security-browser-test webkit-browser-test integrated-check browser-contract-test browser-test-setup identity-test identity-fuzz-test identity-browser-test publication-browser-test scrolling-test scrolling-browser-test presentation-test presentation-browser-test focus-browser-test controls-test controls-browser-test controls-accessibility-test accessibility-test accessibility-browser-test accessibility-audit perf-test memory-test perf-browser-test render-commit-benchmark perf-report perf-ci perf-frames perf-frames-check
integrated-check:
	bun Tools/run-scripts.mjs "Tools/test-runtime-contracts.mjs" "Tools/test-embedded-worker-client.mjs" "Tools/test-embedded-migration-replay.mjs" "Tools/test-feature-loader-origin.mjs" "Tools/test-adaptive-media.mjs" "Tools/test-adaptive-media-browser.mjs" "Tools/test-media-host.mjs" "Tools/test-event-value.mjs" "Tools/test-check-wasm-exports.mjs" "Tools/test-rewrite-release-index.js" "Tools/test-build-runtime-bundle.mjs" "Tools/test-layout-resize-settle.mjs" "Tools/test-layout-skip-pass.mjs" "Tools/test-css-layout-incremental.mjs" "Tools/test-css-layout-layers.mjs" "Tools/test-css-layout-relative.mjs" "Tools/test-css-layout-roots.mjs" "Tools/test-text-fit.mjs" "Tools/test-tap-target-css.mjs" "Tools/test-icon-host.mjs" "Tools/test-live-reload.mjs" "Tools/test-browser-support.mjs" "Tools/test-csp-bundles.mjs --self-test" "Tools/test-toolchain-report.mjs" "Tools/test-format-compat.mjs" "Tools/test-coverage.mjs" "Tools/test-performance-contracts.mjs" "Tools/test-frame-budgets.mjs" "Tools/test-size-tools.mjs" "Tools/test-nspredicate-probe.mjs" "Tools/test-predicate-engine.mjs" "Tools/test-layout-conformance.mjs" "Tools/test-wasi-host.mjs" "Tools/test-semantic-integration.mjs" "Tools/test-lint-styles.mjs" "Tools/test-style-invalidation.mjs" "Tools/test-selection-highlight.mjs" "Tools/test-css-layout-grid-cells.mjs" "Tools/test-color-scheme-subtree.mjs" "Tools/test-page-scheme.mjs" "Tools/test-textarea-line-limits.mjs"

browser-contract-test:
	bun Tools/test-integrated-browser.mjs

browser-test-setup:
	bunx --bun playwright install chromium webkit firefox

.PHONY: browser-live-test integration-release-test
browser-live-test:
	bun Tools/test-showcase-live.mjs --bundle "$(BUNDLE)"

# Final gate: unlike browser-contract-test, this builds and exercises the
# application's real linked Swift WASM. No fixture ABI is involved.
integration-release-test: integrated-check
	$(SWIFT) test $(SWIFT_TEST_FLAGS) --filter SemanticLayoutIntegrationTests
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh showcase
	bun Tools/test-showcase-live.mjs --bundle .build/browser/ShowcaseApp

.PHONY: layout-conformance-contract-test layout-conformance-setup layout-conformance layout-conformance-record
layout-conformance-contract-test:
	bun Tools/LayoutConformance/check-fixtures.mjs

layout-conformance-setup: browser-test-setup
	@echo "Layout conformance browser tooling ready."

# Runs the same semantic fixtures through Apple SwiftUI and the linked
# SwiftUIWeb/browser runtime, then compares geometry (never pixels).
layout-conformance: layout-conformance-contract-test
	SUITE_CONFIGURATION=$(SUITE_CONFIGURATION) Tools/LayoutConformance/run.sh

# Records the Apple side for review/versioning after a successful live run.
layout-conformance-record: layout-conformance
	mkdir -p Tests/LayoutConformance
	cp .build/layout-conformance/apple.json Tests/LayoutConformance/apple-macos.json
	@echo "Recorded Tests/LayoutConformance/apple-macos.json"

# Identity gates intentionally use the retained Fiber tree and the same linked
# Embedded browser application. They do not substitute DOM-order snapshots for
# semantic identity.
identity-test:
	$(SWIFT) test $(SWIFT_TEST_FLAGS) --filter ReconciliationIdentityTests

identity-fuzz-test:
	$(SWIFT) test $(SWIFT_TEST_FLAGS) --filter ReconciliationIdentityTests/testDeterministicIdentityFuzzPrintsSeedAndHistory

# The Embedded inline Markdown parser: output unchanged on a fixed corpus, and thousands of brackets finish in milliseconds.
# Builds Tools/markdown-probe for wasm-embedded and runs it under Node WASI; skips with a message without that Swift SDK.
markdown-probe-test:
	bun Tools/test-markdown-probe.mjs

# A view tree 120 levels deep must render (WebKit Workers have a shallow WebAssembly stack).
stack-depth-browser-test:
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh showcase
	bun Tools/test-stack-depth-browser.mjs
	$(ON_WEBKIT) bun Tools/test-stack-depth-browser.mjs
	$(WEBKIT_ONLY) bun Tools/test-worker-overflow-browser.mjs
	bun Tools/test-click-after-mount-browser.mjs
	$(ON_WEBKIT) bun Tools/test-click-after-mount-browser.mjs
	bun Tools/test-first-route-browser.mjs
	$(ON_WEBKIT) bun Tools/test-first-route-browser.mjs

# Deep links (documentation routes, /stackDepth) and TabView selection URLs render on the first frame, never the start
# screen; the mount marker means the requested screen is there. The TabView case needs the universal app bundle.
first-route-browser-test: universal-app-web-test
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh showcase
	bun Tools/test-first-route-browser.mjs --universal .build/plugins/SwiftUIWebPlugin/outputs/browser/UniversalWebApp
	$(ON_WEBKIT) bun Tools/test-first-route-browser.mjs --universal .build/plugins/SwiftUIWebPlugin/outputs/browser/UniversalWebApp

# First paint (Documentation/Architecture/FIRST_PAINT.md): the first screen in index.html, painted before the wasm, taken over
# without a shift or a lost click, and refused by the verify mode when the capture is wrong. The Board bundle is copied and captured
# by the test; the project site is built with first paint on (SWIFTUIWEB_FIRST_PAINT=1) and checked the way an application ships it.
first-paint-browser-test:
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh board
	bun Tools/test-first-paint-browser.mjs
	$(ON_WEBKIT) bun Tools/test-first-paint-browser.mjs
	SWIFTUIWEB_FIRST_PAINT=1 BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh site
	bun Tools/test-first-paint-browser.mjs --site .build/browser/ShowcaseSite
	$(ON_WEBKIT) bun Tools/test-first-paint-browser.mjs --site .build/browser/ShowcaseSite

# Split module (Documentation/Architecture/WASM_SPLIT.md): a module split by wasm-split loads its second half in a Worker
# (waiting for it, or in the background) and on the page; the Board built with SWIFTUIWEB_WASM_SPLIT=1 (in its own bundle
# folder, so the plain Board bundle stays) reaches its first screen in the Worker, on the main thread and after a move to it.
wasm-split-browser-test:
	SWIFTUIWEB_WASM_SPLIT=1 SWIFTUIWEB_BUNDLE_ROOT=$(CURDIR)/.build/browser-split BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh board
	WASM_SPLIT_BUNDLE=.build/browser-split/BoardBenchmarkApp bun Tools/test-wasm-split-browser.mjs
	$(ON_WEBKIT) WASM_SPLIT_BUNDLE=.build/browser-split/BoardBenchmarkApp bun Tools/test-wasm-split-browser.mjs

# Paint and mount timings of a release bundle, fresh context per run: make first-paint-measure BUNDLE=.build/browser/BoardBenchmarkApp NETWORK=slow CPU=4
first-paint-measure:
	bun Tools/first-paint-measure.mjs --bundle "$(BUNDLE)" --network "$(or $(NETWORK),fast)" --cpu "$(or $(CPU),1)" --runs "$(or $(RUNS),15)"

identity-browser-test:
	BUILD_ONLY=1 CONFIGURATION=$(SUITE_CONFIGURATION) Tools/run-browser.sh showcase
	bun Tools/test-identity-browser.mjs

# Runs of frame, padding and fixedSize that share one element are all styled by CSS layout (Tools/test-layout-layers-browser.mjs).
layers-browser-test:
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh showcase
	bun Tools/test-layout-layers-browser.mjs

publication-browser-test:
	BUILD_ONLY=1 CONFIGURATION=$(SUITE_CONFIGURATION) Tools/run-browser.sh showcase
	bun Tools/test-publication-browser.mjs

# The binary publication (Documentation/Architecture/BINARY_PATCHES.md): the encoder's output for the fixtures, and the page
# building the DOM the parser builds from the markup beside each fixture, in Chromium and WebKit. Every other browser suite
# runs in the binary transport, the only one; SWIFTUIWEB_BINARY=verify also compares each commit's DOM with a reference
# encoding of the same tree.
.PHONY: binary-publication-test
binary-publication-test:
	$(SWIFT) test $(SWIFT_TEST_FLAGS) --filter BinaryEncoderTests
	bun Tools/test-binary-publication-browser.mjs
	bun Tools/test-binary-publication-fuzz.mjs
	$(ON_WEBKIT) bun Tools/test-binary-publication-browser.mjs

scrolling-test:
	$(SWIFT) test $(SWIFT_TEST_FLAGS) --filter ScrollViewTests

scrolling-browser-test:
	BUILD_ONLY=1 CONFIGURATION=$(SUITE_CONFIGURATION) Tools/run-browser.sh showcase
	bun Tools/test-scrolling-browser.mjs

# HSplitView and VSplitView dividers: pointer drag, arrow keys, re-render and limits, Chromium and WebKit.
split-view-browser-test:
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh showcase
	bun Tools/test-split-view-browser.mjs
	$(ON_WEBKIT) bun Tools/test-split-view-browser.mjs

presentation-test:
	$(SWIFT) test $(SWIFT_TEST_FLAGS) --filter PresentationFocusTests
	$(SWIFT) test $(SWIFT_TEST_FLAGS) --filter PresentationDetentsTests

presentation-browser-test:
	BUILD_ONLY=1 CONFIGURATION=$(SUITE_CONFIGURATION) Tools/run-browser.sh showcase
	bun Tools/test-presentation-browser.mjs --mode presentation

focus-browser-test:
	BUILD_ONLY=1 CONFIGURATION=$(SUITE_CONFIGURATION) Tools/run-browser.sh showcase
	bun Tools/test-presentation-browser.mjs --mode focus

controls-test:
	$(SWIFT) test $(SWIFT_TEST_FLAGS) --filter ControlSemanticsTests
	$(SWIFT) test $(SWIFT_TEST_FLAGS) --filter DatePickerTests
	$(SWIFT) test $(SWIFT_TEST_FLAGS) --filter PasteButtonTests

# Every framework module compiles to the same .swiftmodule bytes twice; a module that does not rebuilds all its
# dependents on every edit (Documentation/Performance/BUILD_TIME.md, "The development loop"). Two debug builds of the Showcase.
.PHONY: module-determinism-test
module-determinism-test:
	bun Tools/test-module-determinism.mjs

# The web keychain (SwiftUIWebSecurity) end to end: Web Crypto + IndexedDB in the worker runtime,
# on Chromium and on WebKit.
# AVPlayer reads in the Worker and on the main thread, Chromium and WebKit.
media-worker-test:
	SWIFTUIWEB_PRODUCT=MediaProbeApp BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh media
	bun Tools/test-media-worker-browser.mjs
	# VideoPlayer's AVKit-style controls over the same fixture and clip (section 12.24), Chromium and WebKit, Worker and main thread.
	bun Tools/test-avkit-controls-browser.mjs

security-browser-test:
	SWIFTUIWEB_PRODUCT=SecurityExample BUILD_ONLY=1 CONFIGURATION=$(SUITE_CONFIGURATION) Tools/run-browser.sh x
	bun Tools/test-security-browser.mjs
	$(ON_WEBKIT) bun Tools/test-security-browser.mjs

# The interaction suites again on WebKit, the engine of Safari on iPad and Mac.
webkit-browser-test:
	BUILD_ONLY=1 CONFIGURATION=$(SUITE_CONFIGURATION) Tools/run-browser.sh showcase
	$(ON_WEBKIT) bun Tools/test-identity-browser.mjs
	$(ON_WEBKIT) bun Tools/test-scrolling-browser.mjs
	$(ON_WEBKIT) bun Tools/test-presentation-browser.mjs --mode presentation
	$(ON_WEBKIT) bun Tools/test-controls-browser.mjs --mode controls
	$(ON_WEBKIT) bun Tools/test-integrated-browser.mjs

controls-browser-test:
	BUILD_ONLY=1 CONFIGURATION=$(SUITE_CONFIGURATION) Tools/run-browser.sh showcase
	bun Tools/test-controls-browser.mjs --mode controls

controls-accessibility-test:
	BUILD_ONLY=1 CONFIGURATION=$(SUITE_CONFIGURATION) Tools/run-browser.sh showcase
	bun Tools/test-controls-browser.mjs --mode accessibility

accessibility-test:
	$(SWIFT) test $(SWIFT_TEST_FLAGS) --filter AccessibilityBackendTests

accessibility-browser-test:
	BUILD_ONLY=1 CONFIGURATION=$(SUITE_CONFIGURATION) Tools/run-browser.sh showcase
	bun Tools/test-accessibility-browser.mjs

.PHONY: resize-transition-browser-test
resize-transition-browser-test:
	bun Tools/test-resize-transition-browser.mjs
	$(ON_WEBKIT) bun Tools/test-resize-transition-browser.mjs

# Declaration order vs DOM, Tab, flow geometry and accessibility-tree order on the
# Showcase /readingOrder fixture (positioned layout can diverge).
reading-order-browser-test:
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh showcase
	bun Tools/test-reading-order-browser.mjs

# Button highlight, focus and hit area follow the visible shape on the Showcase /buttonShape fixture.
button-highlight-browser-test:
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh showcase
	bun Tools/test-button-highlight-browser.mjs

accessibility-audit:
	bun Tools/accessibility-audit.mjs
	bun build --no-bundle Tools/test-accessibility-browser.mjs > /dev/null
	bun build --no-bundle --target=bun Tools/embedded-dom.js > /dev/null

perf-test:
	bun Tools/performance-contracts.mjs --phase swift

memory-test:
	bun Tools/performance-contracts.mjs --phase memory

perf-browser-test:
	mkdir -p .build/performance
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh showcase
	bun Tools/test-performance-browser.mjs
	bun Tools/performance-contracts.mjs --phase browser

# Opt-in: where the HTML commit path spends its time (Swift publish phases, HTML read/parse,
# DOM patch, frames, mutation classes) on the release Showcase. Not a gate; no budgets.
# Extra options: RENDER_COMMIT_ARGS="--iterations 9 --scenarios largeList --no-worker".
render-commit-benchmark:
	mkdir -p .build/performance
	BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh showcase
	bun Tools/test-performance-browser.mjs --render-commit $(RENDER_COMMIT_ARGS)

perf-report:
	bun Tools/performance-contracts.mjs --phase report

perf-ci: perf-test perf-browser-test perf-report
	bun Tools/performance-contracts.mjs --phase check --scope all

# Frame-time budgets (Documentation/Performance/FRAME_BUDGETS.md). `perf-frames` measures a built bundle of an application
# with a scenario module;
# `perf-frames-check` evaluates a measurement file it wrote. Both exit 0 while every budget is in report mode.
# make perf-frames BUNDLE=<dir> SCENARIO=<module.mjs> [FRAME_ARGS="--rounds 5 --api-origin http://127.0.0.1:8081"]
perf-frames:
	@test -n "$(BUNDLE)" -a -n "$(SCENARIO)" || { echo "usage: make perf-frames BUNDLE=<built bundle dir> SCENARIO=<scenario module>"; exit 2; }
	bun Tools/frame-budgets.mjs run --bundle "$(BUNDLE)" --scenario "$(SCENARIO)" --json .build/performance/frame-budgets.json $(FRAME_ARGS)

perf-frames-check:
	bun Tools/frame-budgets.mjs evaluate --measurements $(or $(FRAMES),.build/performance/browser-frames.json) --json .build/performance/frame-budgets.json $(FRAME_ARGS)
