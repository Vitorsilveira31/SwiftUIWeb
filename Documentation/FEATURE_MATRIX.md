# SwiftUIWeb feature matrix

This is the runtime contract for the canonical Embedded Swift + browser host. `supported` means the capability is exercised by the host; `fallback` means the semantic API remains available with a documented browser/native substitute; `unsupported` is an explicit capability result; `no-op` is an intentional side-effect-free modifier. Every row must retain executable source evidence.

| Feature | Embedded status | Evidence |
| --- | --- | --- |
| `images` | **supported** | `Sources/SwiftUIWebBrowser/BrowserApp.swift`, `Tools/image-pipeline.js` |
| `adaptiveMedia` | **supported** | `Sources/SwiftUIWebAVFoundation`, `Tools/avfoundation.js` |
| `maps` | **fallback** | `Sources/SwiftUIWebMapKit/MapKit.swift`, `Sources/SwiftUIWebMapKit/MapLibreBackend.swift` |
| `charts` | **supported** | `Sources/SwiftUIWebCharts/Charts.swift` |
| `datePickers` | **fallback** | `Sources/SwiftUIWebInternationalization/DatePickers.swift`, `Tools/BrowserIO/browser-io.mjs` |
| `webView` | **supported** | `Sources/SwiftUIWebWeb/WebContent.swift` |
| `photos` | **supported** | `Sources/SwiftUIWebPhotosUI/PhotosUI.swift` |
| `notifications` | **fallback** | `Sources/SwiftUIWebUserNotifications/UserNotifications.swift` |
| `keychain` | **supported** | `Sources/SwiftUIWebSecurity/SecKeychain.swift`, `Tools/BrowserIO/browser-io.mjs`, `Tools/test-security-browser.mjs` |
| `location` | **supported** | `Sources/SwiftUIWebCoreLocation/Location.swift` |
| `webMount` | **supported** | `Sources/SwiftUIWebBrowser/WebMount.swift`, `Tools/embedded-dom.js` |
| `paste` | **fallback** | `Sources/SwiftUIWebFeatures/PasteButton.swift`, `Tools/host-interactions.js` |
| `canvas` | **supported** | `Sources/SwiftUIWebCore/MissingFeatures.swift` |
| `meshGradient` | **supported** | `Tools/mesh-gradient.js`, `Sources/SwiftUIWebCore/MissingFeatures.swift` |
| `lazyCollections` | **supported** | `Sources/SwiftUIWebFiber/LazyLayout.swift`, `Tools/embedded-dom.js` |
| `geometry` | **supported** | `Sources/SwiftUIWebCore/Geometry.swift`, `Sources/SwiftUIWebCore/GeometryMeasurement.swift`, `Tools/geometry-host.js`, `Tools/layout-host.js`, `Tools/test-geometry-browser.mjs` |
| `navigation` | **supported** | `Sources/SwiftUIWebCore/Navigation.swift`, `Tools/host-interactions.js` |
| `dragDrop` | **supported** | `Sources/SwiftUIWebCore/DragDrop.swift`, `Tools/host-interactions.js` |
| `networking` | **supported** | `Sources/SwiftUIWebNetworking/Networking.swift`, `Tools/BrowserIO/browser-io.mjs` |
| `storage` | **supported** | `Sources/SwiftUIWebBrowser/WebStorage.swift`, `Tools/BrowserIO/browser-io.mjs` |
| `containerRelativeFrame` | **supported** | `Sources/SwiftUIWebFeatures/ContainerRelativeFrame.swift`, `Tools/css-layout.js` |
| `contextMenu` | **supported** | `Sources/SwiftUIWebFeatures/ContextMenu.swift`, `Tools/embedded-dom.js` |
| `liveDateTexts` | **supported** | `Sources/SwiftUIWebInternationalization/DateFormatting.swift`, `Tools/embedded-dom.js` |
| `dateFormatStyle` | **supported** | `Sources/SwiftUIWebInternationalization/DateFormatStyle.swift`, `Tools/BrowserIO/browser-io.mjs` |
| `accessibilityElements` | **supported** | `Sources/SwiftUIWebCore/AccessibilityElement.swift` |
| `animatedShapeTrim` | **supported** | `Sources/SwiftUIWebCore/Modifiers.swift`, `Tools/embedded-dom.js` |
| `sensoryFeedbackNoOp` | **no-op** | `Sources/SwiftUIWebCore/TextAndSymbolModifiers.swift` |
| `keyboardShortcuts` | **supported** | `Sources/SwiftUIWebCore/KeyboardShortcut.swift`, `Sources/SwiftUIWebCore/KeyPress.swift`, `Tools/host-interactions.js`, `Tools/embedded-dom.js` |
| `presentationDetents` | **supported** | `Sources/SwiftUIWebFeatures/PresentationDetents.swift`, `Tools/host-interactions.js` |
| `controlStyles` | **supported** | `Sources/SwiftUIWebCore/PickerSegmented.swift`, `Sources/SwiftUIWebCore/ToggleStyles.swift`, `Sources/SwiftUIWebCore/ButtonPressState.swift` |
| `optionalTintNoOp` | **no-op** | `Sources/SwiftUIWebCore/MissingFeatures.swift` |
| `nativeFoundation` | **unsupported** | `Sources/WebFoundation` |

The matrix is checked by `make feature-matrix`; it deliberately does not infer support from a source-name match or from a native-only build.
