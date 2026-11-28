// swift-tools-version: 6.4
import PackageDescription
import Foundation

let embeddedRuntimeRequested = ProcessInfo.processInfo.environment["SWIFTUIWEB_EMBEDDED"] == "1"
// Set by the launcher for the development profile `fast` (SWIFTUIWEB_DEV_PROFILE=fast, Tools/run-browser-embedded.sh): the
// browser product is compiled as full Swift for regular WebAssembly, so a save recompiles the files it changed instead of
// whole modules. The package is still the browser package (SWIFTUIWEB_EMBEDDED=1 stays set, and consumer manifests read
// it); only the Embedded compiler mode is left out. Documentation/Performance/BUILD_TIME.md, "The development profile".
let fullSwiftRequested = ProcessInfo.processInfo.environment["SWIFTUIWEB_FULL_SWIFT"] == "1"
// Set by the Embedded launcher for `--release-profile balanced`; see the library settings at the end of this file.
let libraryOptimizationOff = ProcessInfo.processInfo.environment["SWIFTUIWEB_LIBRARY_OPTIMIZATION"] == "none"
// Set by the Embedded launcher for the debug development loop; see the library settings at the end of this file.
let libraryDeferredCodeGen = ProcessInfo.processInfo.environment["SWIFTUIWEB_LIBRARY_CODEGEN"] == "deferred"

// SwiftPM applies command-line linker flags to its host-side plugins as well
// as to the WASM product. Keep the Embedded-only Unicode archive on the
// browser target itself so host-side tools never receive WASM-only linker flags.
let embeddedUnicodeLinkerSettings: [LinkerSetting] =
  embeddedRuntimeRequested && !fullSwiftRequested
    ? [.unsafeFlags(["-Xlinker", "-lswiftUnicodeDataTables"])]
    : []

// The Embedded browser build answers the standard library's Unicode character data from the browser and gives the
// Concurrency runtime a small printf (Sources/CSwiftUIWebBrowserIO/UnicodeData.c, RuntimeFormatting.c). Native builds
// and the full-Swift development profile keep the C library's and the standard library's own.
let embeddedRuntimeCSettings: [CSetting] =
  embeddedRuntimeRequested && !fullSwiftRequested ? [.define("SWIFTUIWEB_EMBEDDED_RUNTIME")] : []

// Keep Embedded Swift restrictions visible while the neutral renderer is
// compiled with the standard toolchain. This is a diagnostic guardrail: APIs
// that are genuinely unavailable to Embedded Swift still fail when an
// Embedded target is selected, but new uses of restricted language/runtime
// features are reported consistently during ordinary development builds.
let embeddedRestrictionsWarnings: [SwiftSetting] =
  (ProcessInfo.processInfo.environment["SWIFTUIWEB_EMBEDDED_RESTRICTIONS"] == "1" && !embeddedRuntimeRequested)
    ? [.treatWarning("EmbeddedRestrictions", as: .warning)]
    : []

// Application code (the examples and the tests that drive them) is written as an app shared with Apple writes it:
// `import Foundation`. Against SwiftUIWeb that name means WebFoundation on every host, as the browser build already
// spells it, so the framework's `Data`, `URL` and `Date` are the only ones a file sees.
let appFoundationAlias: [SwiftSetting] = [.unsafeFlags(["-module-alias", "Foundation=WebFoundation"])]

let package = Package(
  name: "SwiftUIWeb",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "SwiftUIWeb", targets: ["SwiftUIWeb"]),
    // Optional CryptoKit-compatible primitives for native and Embedded applications.
    // This product is intentionally not a dependency of SwiftUIWebCore or
    // the SwiftUIWeb façade.
    .library(name: "SwiftUIWebCrypto", targets: ["SwiftUIWebCrypto"]),
    .library(name: "SwiftUIWebTransferable", targets: ["SwiftUIWebTransferable"]),
    .library(name: "WebFoundation", targets: ["WebFoundation"]),
    // Apple's `OSLog` (`Logger`) for the browser: applications alias `OSLog` to it (`-module-alias OSLog=WebOSLog`).
    .library(name: "WebOSLog", targets: ["WebOSLog"]),
    .library(name: "SwiftUIWebUniformTypeIdentifiers", targets: ["SwiftUIWebUniformTypeIdentifiers"]),
    .library(name: "SwiftUIWebPhotosUI", targets: ["SwiftUIWebPhotosUI"]),
    .library(name: "SwiftUIWebCore", targets: ["SwiftUIWebCore"]),
    .library(name: "SwiftUIWebFeatures", targets: ["SwiftUIWebFeatures"]),
    .library(name: "SwiftUIWebInternationalization", targets: ["SwiftUIWebInternationalization"]),
    .library(name: "SwiftUIWebCoreLocation", targets: ["SwiftUIWebCoreLocation"]),
    .library(name: "SwiftUIWebNetworking", targets: ["SwiftUIWebNetworking"]),
    .library(name: "SwiftUIWebFiber", targets: ["SwiftUIWebFiber"]),
    .library(name: "SwiftUIWebHTML", targets: ["SwiftUIWebHTML"]),
    .library(name: "SwiftUIWebBrowser", targets: ["SwiftUIWebBrowser"]),
    // Web-only interop (DOM components, embedded web content, WebEnvironment). Not SwiftUI-shaped, so it is
    // deliberately not re-exported by the SwiftUIWeb façade and is outside the SwiftUI parity check.
    .library(name: "SwiftUIWebWeb", targets: ["SwiftUIWebWeb"]),
    .library(name: "SwiftUIWebMapKit", targets: ["SwiftUIWebMapKit"]),
    .library(name: "SwiftUIWebCharts", targets: ["SwiftUIWebCharts"]),
    .library(name: "SwiftUIWebAVFoundation", targets: ["SwiftUIWebAVFoundation"]),
    .library(name: "SwiftUIWebAVKit", targets: ["SwiftUIWebAVKit"]),
    .library(name: "SwiftUIWebUserNotifications", targets: ["SwiftUIWebUserNotifications"]),
    .library(name: "SwiftUIWebSecurity", targets: ["SwiftUIWebSecurity"]),
    .library(name: "SwiftUIWebBrowserIO", targets: ["SwiftUIWebBrowserIO"]),
    .plugin(name: "SwiftUIWebPlugin", targets: ["SwiftUIWebPlugin"]),
    .plugin(name: "SwiftUIWebWebPlugin", targets: ["SwiftUIWebWebPlugin"]),
    // Showcase, Lumio, Quill, Seekr, Neighborly, Stayly and Mailo are the supported user-facing applications.
    // WebMount remains a separate internal browser regression fixture.
    .executable(name: "ShowcaseApp", targets: ["ShowcaseApp"]),
    .executable(name: "LayoutConformanceApp", targets: ["LayoutConformanceApp"]),
    .executable(name: "EmbeddedLoweringConformanceApp", targets: ["EmbeddedLoweringConformanceApp"]),
    .executable(name: "Lumio", targets: ["Lumio"]),
    .executable(name: "Seekr", targets: ["Seekr"]),
    .executable(name: "Neighborly", targets: ["Neighborly"]),
    .executable(name: "Stayly", targets: ["Stayly"]),
    .executable(name: "Mailo", targets: ["Mailo"]),
    .executable(name: "Quill", targets: ["Quill"]),
    .executable(name: "WebMountExample", targets: ["WebMountExample"]),
    .executable(name: "MapKitExample", targets: ["MapKitExample"]),
    .executable(name: "MediaExample", targets: ["MediaExample"]),
    .executable(name: "MediaProbeApp", targets: ["MediaProbeApp"]),
    .executable(name: "SecurityExample", targets: ["SecurityExample"]),
    .executable(name: "PhotosPickerExample", targets: ["PhotosPickerExample"])
  ],
  dependencies: (embeddedRuntimeRequested ? [] : [
    // Swift Crypto provides the CryptoKit API and its BoringSSL/XKCP-backed
    // implementation on supported non-Apple hosts. Apple builds use the system CryptoKit module
    // through SwiftUIWebCrypto's conditional backend import.
    // Keep the audited Swift 6.4-compatible line. Swift Crypto 4.3.1 includes
    // the published X-Wing input-validation fix; newer 4.4+ releases raise
    // the minimum compiler version and should be audited before moving.
    .package(url: "https://github.com/apple/swift-crypto.git", exact: "5.2.0")
  ]),
  targets: [
    .target(name: "CSwiftUIWebBrowserIO", path: "Sources/CSwiftUIWebBrowserIO", publicHeadersPath: "include", cSettings: embeddedRuntimeCSettings),
    // Optional, backend-neutral cryptography. JavaScript/browser APIs are not
    // exposed here; browser applications use the same Swift implementation
    // with secure randomness supplied by the platform RNG.
    .target(name: "SwiftUIWebCrypto", dependencies: [
      .product(name: "Crypto", package: "swift-crypto")
    ], path: "Sources/SwiftUIWebCrypto"),
    // Backend-neutral content and transfer representations shared by browser
    // media pickers and future import/export controls. This target stays
    // independent from renderers and networking; Foundation.Data is used when
    // available and a compact byte collection is supplied otherwise.
    // The lock primitives alone, so a module that only needs a guarded global does not pull in Transferable.
    .target(name: "SwiftUIWebLocking", path: "Sources/SwiftUIWebLocking"),
    .target(name: "SwiftUIWebTransferable", dependencies: ["SwiftUIWebLocking", "SwiftUIWebUniformTypeIdentifiers"], path: "Sources/SwiftUIWebTransferable"),
    // Foundation-free application helpers and Embedded serialization exports.
    // This is the compatibility layer applications can use without writing
    // per-app `#if hasFeature(Embedded)` shims.
    .target(name: "WebFoundation", dependencies: ["SwiftUIWebTransferable", "SwiftUIWebCore", "SwiftUIWebFeatures", "SwiftUIWebNetworking", "SwiftUIWebInternationalization", "SwiftUIWebBrowserIO"], path: "Sources/WebFoundation"),
    // The unified logging API (`Logger`) writing to the browser's console through BrowserIO.
    .target(name: "WebOSLog", dependencies: ["SwiftUIWebBrowserIO"], path: "Sources/WebOSLog", swiftSettings: embeddedRestrictionsWarnings),
    // Foundation-free UTType support shared by browser-facing APIs. Keeping
    // this standalone avoids pulling renderers or browser runtime code into clients
    // that only need type metadata.
    .target(name: "SwiftUIWebUniformTypeIdentifiers", path: "Sources/SwiftUIWebUniformTypeIdentifiers"),
    // The public façade is deliberately tiny. It re-exports the layers below
    // so application source continues to use `import SwiftUIWeb`.
    .target(name: "SwiftUIWebCore", dependencies: ["SwiftUIWebTransferable"], path: "Sources/SwiftUIWebCore", swiftSettings: embeddedRestrictionsWarnings),
    // The part of the SwiftUI-shaped API that nothing in SwiftUIWebCore uses, kept out of Core so that an edit in either
    // module recompiles a smaller module. Applications see it through
    // SwiftUIWeb, which re-exports it.
    .target(name: "SwiftUIWebFeatures", dependencies: ["SwiftUIWebCore", "SwiftUIWebTransferable"], path: "Sources/SwiftUIWebFeatures", swiftSettings: embeddedRestrictionsWarnings),
    // Date/calendar/locale controls are kept in a separate target. Core keeps
    // the SwiftUI-facing aliases and lightweight Date representation. Direct
    // Core clients therefore avoid this target; the compatibility façade
    // re-exports it for source compatibility. Browser date presentation uses
    // an injected Intl adapter, while native formatting remains Foundation.
    // Other targets may still retain Foundation; measure the final app.
    .target(name: "SwiftUIWebInternationalization", dependencies: ["SwiftUIWebCore", "SwiftUIWebFeatures"], path: "Sources/SwiftUIWebInternationalization"),
    .target(name: "SwiftUIWebCoreLocation", dependencies: ["SwiftUIWebLocking", "SwiftUIWebTransferable"], path: "Sources/SwiftUIWebCoreLocation"),
    .target(name: "SwiftUIWebNetworking", dependencies: ["SwiftUIWebCore", "SwiftUIWebTransferable"], path: "Sources/SwiftUIWebNetworking"),
    // Optional and independent from SwiftUIWeb Core. Browser behavior uses BrowserIO.
    .target(name: "SwiftUIWebUserNotifications", dependencies: [], path: "Sources/SwiftUIWebUserNotifications"),
    // Security.framework-shaped keychain for the browser: Web Crypto + IndexedDB through BrowserIO.
    // Optional and independent from SwiftUIWeb Core.
    .target(name: "SwiftUIWebSecurity", dependencies: ["SwiftUIWebBrowserIO", "SwiftUIWebLocking"], path: "Sources/SwiftUIWebSecurity", swiftSettings: embeddedRestrictionsWarnings),
    .target(name: "SwiftUIWebFiber", dependencies: ["SwiftUIWebCore"], path: "Sources/SwiftUIWebFiber", swiftSettings: embeddedRestrictionsWarnings),
    .target(name: "SwiftUIWebHTML", dependencies: ["SwiftUIWebCore", "SwiftUIWebFiber"], path: "Sources/SwiftUIWebHTML", swiftSettings: embeddedRestrictionsWarnings),
    .target(name: "SwiftUIWebWeb", dependencies: ["SwiftUIWebCore", "SwiftUIWebFeatures", "SwiftUIWebNetworking", "SwiftUIWebTransferable"], path: "Sources/SwiftUIWebWeb"),
    // Optional, renderer-owned charting. Core intentionally has no chart
    // dependency, keeping this product independently tree-shakeable.
    .target(name: "SwiftUIWebCharts", dependencies: ["SwiftUIWebCore", "SwiftUIWebFeatures", "SwiftUIWebInternationalization"], path: "Sources/SwiftUIWebCharts"),
    .target(name: "SwiftUIWeb", dependencies: ["SwiftUIWebCore", "SwiftUIWebFeatures", "SwiftUIWebInternationalization", "SwiftUIWebNetworking", "SwiftUIWebFiber", "SwiftUIWebHTML", "SwiftUIWebTransferable", "WebFoundation"], path: "Sources/SwiftUIWeb", swiftSettings: embeddedRestrictionsWarnings),
    .target(name: "SwiftUIWebPhotosUI", dependencies: ["SwiftUIWeb", "SwiftUIWebTransferable"], path: "Sources/SwiftUIWebPhotosUI"),
    .target(name: "SwiftUIWebBrowser", dependencies: [
      "SwiftUIWebInternationalization",
      "SwiftUIWeb",
      "SwiftUIWebPhotosUI",
      "SwiftUIWebTransferable",
      "WebFoundation",
      "SwiftUIWebCore",
      "SwiftUIWebFeatures",
      "SwiftUIWebCoreLocation",
      "SwiftUIWebBrowserIO",
      "CSwiftUIWebBrowserIO"
    ], path: "Sources/SwiftUIWebBrowser", linkerSettings: embeddedUnicodeLinkerSettings),
    .target(name: "SwiftUIWebBrowserIO", dependencies: ["CSwiftUIWebBrowserIO", "SwiftUIWebLocking"], path: "Sources/SwiftUIWebBrowserIO", swiftSettings: embeddedRestrictionsWarnings),
    // Optional mapping layer. MapLibre and browser lifecycle code are kept
    // here; SwiftUIWebCore remains renderer-neutral and mapping-free.
    .target(name: "SwiftUIWebMapKit", dependencies: [
      "SwiftUIWebCore",
      "SwiftUIWebCoreLocation",
      "SwiftUIWebBrowser"
    ], path: "Sources/SwiftUIWebMapKit", linkerSettings: embeddedUnicodeLinkerSettings),
    // AVFoundation-shaped media is a browser feature wrapper.  Keeping it
    // above the browser adapter prevents Core/Fiber/HTML from acquiring any
    // media or browser-host dependency.
    .target(name: "SwiftUIWebAVFoundation", dependencies: ["SwiftUIWeb", "SwiftUIWebBrowser", "SwiftUIWebBrowserIO", "WebFoundation"], path: "Sources/SwiftUIWebAVFoundation"),
    // AVKit is a thin presentation layer. Playback and browser lifecycle stay
    // exclusively in SwiftUIWebAVFoundation, keeping this target independently
    // tree-shakeable for applications that do not need video UI.
    .target(name: "SwiftUIWebAVKit", dependencies: ["SwiftUIWeb", "SwiftUIWebAVFoundation"], path: "Sources/SwiftUIWebAVKit"),
    // This target is intentionally independent from SwiftUIWebCore.  It is a
    // small, internal Embedded Swift compatibility probe used to measure the
    // minimum retained structural/runtime slice without compiling the full
    // Core module. It is not a second
    // application programming model and is not exposed as a library product.
    .target(name: "SwiftUIWebEmbeddedCoreProbe", path: "Sources/SwiftUIWebEmbeddedCoreProbe", swiftSettings: embeddedRestrictionsWarnings),
    .executableTarget(name: "BoardBenchmarkApp", dependencies: ["SwiftUIWebBrowser"], path: "Tests/Apps/BoardBenchmarkApp", swiftSettings: appFoundationAlias),
    .executableTarget(name: "LazyCellStateApp", dependencies: ["SwiftUIWebBrowser"], path: "Tests/Apps/LazyCellStateApp", swiftSettings: appFoundationAlias),
    .executableTarget(name: "ViewTransitionApp", dependencies: ["SwiftUIWebBrowser"], path: "Tests/Apps/ViewTransitionApp", swiftSettings: appFoundationAlias),
    .executableTarget(name: "MotionApp", dependencies: ["SwiftUIWebBrowser"], path: "Tests/Apps/MotionApp", swiftSettings: appFoundationAlias),
    .executableTarget(name: "ShowcaseSite", dependencies: ["SwiftUIWebBrowser", "SwiftUIWebWeb"], path: "Examples/ShowcaseSite", swiftSettings: appFoundationAlias),
    // What the realistic example apps share: models and a typed client for the jsonplaceholder-shaped API (Examples/CloneKit/README.md).
    .target(name: "CloneKit", dependencies: ["SwiftUIWeb"], path: "Examples/CloneKit", swiftSettings: appFoundationAlias),
    .executableTarget(name: "Lumio", dependencies: ["SwiftUIWebBrowser", "CloneKit"], path: "Examples/Lumio", swiftSettings: appFoundationAlias),
    .executableTarget(name: "Seekr", dependencies: ["SwiftUIWebBrowser", "CloneKit"], path: "Examples/Seekr", swiftSettings: appFoundationAlias),
    .executableTarget(name: "Neighborly", dependencies: ["SwiftUIWebBrowser", "CloneKit"], path: "Examples/Neighborly", swiftSettings: appFoundationAlias),
    .executableTarget(name: "Stayly", dependencies: ["SwiftUIWebBrowser", "CloneKit"], path: "Examples/Stayly", swiftSettings: appFoundationAlias),
    .executableTarget(name: "Mailo", dependencies: ["SwiftUIWebBrowser", "CloneKit"], path: "Examples/Mailo", swiftSettings: appFoundationAlias),
    .executableTarget(name: "Quill", dependencies: ["SwiftUIWebBrowser", "CloneKit"], path: "Examples/Quill", swiftSettings: appFoundationAlias),
    .executableTarget(name: "ShowcaseApp", dependencies: ["SwiftUIWebBrowser", "SwiftUIWebMapKit", "SwiftUIWebCharts", "SwiftUIWebWeb"], path: "Tests/Apps/ShowcaseApp", swiftSettings: appFoundationAlias),
    .executableTarget(name: "LayoutConformanceApp", dependencies: ["SwiftUIWeb", "SwiftUIWebBrowser"], path: "Tests/Apps/LayoutConformanceApp", swiftSettings: appFoundationAlias),
    .executableTarget(name: "EmbeddedLoweringConformanceApp", dependencies: ["SwiftUIWebBrowser", "SwiftUIWebAVFoundation", "SwiftUIWebAVKit", "SwiftUIWebCharts", "WebOSLog"], path: "Tests/Apps/EmbeddedLoweringConformanceApp", swiftSettings: appFoundationAlias),
    .executableTarget(name: "WebMountExample", dependencies: ["SwiftUIWebBrowser"], path: "Tests/Apps/WebMountExample", swiftSettings: appFoundationAlias),
    .executableTarget(name: "MapKitExample", dependencies: ["SwiftUIWebBrowser", "SwiftUIWebMapKit"], path: "Examples/MapKitExample", swiftSettings: appFoundationAlias),
    .executableTarget(name: "WebKitExample", dependencies: ["SwiftUIWebBrowser", "SwiftUIWebWeb"], path: "Examples/WebKitExample", swiftSettings: appFoundationAlias),
    .executableTarget(name: "MediaExample", dependencies: ["SwiftUIWebBrowser", "SwiftUIWebAVFoundation", "SwiftUIWebAVKit"], path: "Examples/MediaExample", swiftSettings: appFoundationAlias),
    .executableTarget(name: "MediaProbeApp", dependencies: ["SwiftUIWebBrowser", "SwiftUIWebBrowserIO", "SwiftUIWebAVFoundation", "SwiftUIWebAVKit"], path: "Tests/Apps/MediaProbeApp", swiftSettings: appFoundationAlias),
    .executableTarget(name: "SecurityExample", dependencies: ["SwiftUIWebBrowser", "SwiftUIWebSecurity"], path: "Examples/SecurityExample", swiftSettings: appFoundationAlias),
    .executableTarget(name: "AVKitExample", dependencies: ["SwiftUIWebBrowser", "SwiftUIWebAVKit"], path: "Examples/AVKitExample", swiftSettings: appFoundationAlias),
    .executableTarget(name: "PhotosPickerExample", dependencies: ["SwiftUIWebBrowser", "SwiftUIWebPhotosUI"], path: "Examples/PhotosPickerExample", swiftSettings: appFoundationAlias),
    .executableTarget(name: "UserNotificationsExample", dependencies: ["SwiftUIWebBrowser", "SwiftUIWebUserNotifications"], path: "Examples/UserNotificationsExample", swiftSettings: appFoundationAlias),
    .plugin(
      name: "SwiftUIWebPlugin",
      capability: .command(
        intent: .custom(verb: "swiftuiweb", description: "Build a SwiftUIWeb browser bundle")
      ),
      path: "Plugins/SwiftUIWebPlugin"
    ),
    // `swift package web init` writes ./swiftweb, the script that runs the development loop outside SwiftPM
    // (Plugins/SwiftUIWebWebPlugin/README.md).
    .plugin(
      name: "SwiftUIWebWebPlugin",
      capability: .command(
        intent: .custom(verb: "web", description: "Set up ./swiftweb, the script that runs SwiftUIWeb for this package"),
        permissions: [.writeToPackageDirectory(reason: "Writes the ./swiftweb script at the root of the package")]
      ),
      path: "Plugins/SwiftUIWebWebPlugin"
    ),
    .testTarget(name: "SwiftUIWebTests", dependencies: [
      "SwiftUIWeb",
      "WebOSLog",
      "SwiftUIWebCore",
      "SwiftUIWebCoreLocation",
      "SwiftUIWebFiber",
      "SwiftUIWebHTML",
      "SwiftUIWebWeb",
      "SwiftUIWebCharts",
      "SwiftUIWebBrowser",
      "SwiftUIWebPhotosUI",
      "SwiftUIWebTransferable",
      "SwiftUIWebUniformTypeIdentifiers",
      "SwiftUIWebAVFoundation",
      "SwiftUIWebAVKit",
      "SwiftUIWebNetworking",
      "SwiftUIWebBrowserIO",
      "SwiftUIWebLocking",
      "SwiftUIWebMapKit",
      "WebFoundation"
    ], swiftSettings: appFoundationAlias),
    // Builds its own copy of the Embedded JSON codec (a symlink to Transferable's file) so the codec runs natively.
    .testTarget(name: "EmbeddedJSONTests", dependencies: ["SwiftUIWebLocking", "WebFoundation"], path: "Tests/EmbeddedJSONTests", exclude: ["Fixtures"], swiftSettings: appFoundationAlias + [.define("EMBEDDED_JSON_TESTS")]),
    .testTarget(name: "SwiftUIWebCryptoTests", dependencies: ["SwiftUIWebCrypto"], path: "Tests/SwiftUIWebCryptoTests"),
    .testTarget(name: "SwiftUIWebUserNotificationsTests", dependencies: ["SwiftUIWebUserNotifications"], path: "Tests/SwiftUIWebUserNotificationsTests"),
    .testTarget(name: "SwiftUIWebSecurityTests", dependencies: ["SwiftUIWebSecurity"], path: "Tests/SwiftUIWebSecurityTests"),
    .testTarget(name: "ShowcaseSiteTests", dependencies: ["ShowcaseSite"], path: "Tests/ShowcaseSiteTests", swiftSettings: appFoundationAlias),
    .testTarget(name: "CloneKitTests", dependencies: ["CloneKit"], path: "Tests/CloneKitTests", swiftSettings: appFoundationAlias),
    .testTarget(name: "LumioTests", dependencies: ["Lumio", "CloneKit"], path: "Tests/LumioTests", swiftSettings: appFoundationAlias),
    .testTarget(name: "QuillTests", dependencies: ["Quill", "CloneKit"], path: "Tests/QuillTests", swiftSettings: appFoundationAlias),
    .testTarget(name: "SeekrTests", dependencies: ["Seekr", "CloneKit"], path: "Tests/SeekrTests", swiftSettings: appFoundationAlias),
    .testTarget(name: "NeighborlyTests", dependencies: ["Neighborly", "CloneKit"], path: "Tests/NeighborlyTests", swiftSettings: appFoundationAlias),
    .testTarget(name: "StaylyTests", dependencies: ["Stayly", "CloneKit"], path: "Tests/StaylyTests", swiftSettings: appFoundationAlias),
    .testTarget(name: "MailoTests", dependencies: ["Mailo", "CloneKit"], path: "Tests/MailoTests", swiftSettings: appFoundationAlias)
  ]
)

// A requested Embedded build must use the real compiler mode on every runtime
// Swift target. Host macros are separate dependencies, not browser runtime code.
// This configuration is a strict compilation gate, NOT a statement that the full
// framework or browser bridge has completed its Embedded migration.
if embeddedRuntimeRequested {
  // Crypto was already an optional product. Preserve it for normal/native users,
  // but remove both its target and dependency graph from the Embedded profile.
  package.products.removeAll { $0.name == "SwiftUIWebCrypto" }
  package.targets.removeAll { $0.name == "SwiftUIWebCrypto" || $0.name == "SwiftUIWebCryptoTests" }
  // The development profile `fast` keeps the browser package and leaves the Embedded compiler mode out.
  for target in package.targets where !fullSwiftRequested && (target.type == .regular || target.type == .executable) {
    target.swiftSettings = (target.swiftSettings ?? []) + [
      .enableExperimentalFeature("Embedded"),
      .unsafeFlags(["-whole-module-optimization"])
    ]
    if target.type == .regular {
      // Import serialized SIL from library modules and specialize at the
      // executable instead of linking standard-runtime objects into a
      // supposedly Embedded application.
      //
      // The debug development loop (SWIFTUIWEB_LIBRARY_CODEGEN=deferred, set by Tools/run-browser-embedded.sh) uses
      // DeferredCodeGen instead: it generalizes the empty object file, and a library emits the code of the functions the
      // lowering marked `@export(interface)` itself, so the executable stops recompiling them on every save
      // (Documentation/Performance/BUILD_TIME.md, "The development loop"). Release builds never set it.
      if libraryDeferredCodeGen {
        target.swiftSettings = (target.swiftSettings ?? []) + [.enableExperimentalFeature("DeferredCodeGen")]
      } else {
        target.swiftSettings = (target.swiftSettings ?? []) + [
          .unsafeFlags(["-Xfrontend", "-emit-empty-object-file"])
        ]
      }
      // Release profile `balanced` (Tools/run-browser-embedded.sh): the libraries only serialize SIL and the executable
      // optimizes it again, so skipping the optimizer here shortens the serial part of the build. It is a frontend flag
      // because the launcher's `-Osize` is appended after a manifest's own flags and would otherwise win.
      if libraryOptimizationOff {
        target.swiftSettings = (target.swiftSettings ?? []) + [
          .unsafeFlags(["-Xfrontend", "-Onone"], .when(configuration: .release))
        ]
      }
    }
  }
}
