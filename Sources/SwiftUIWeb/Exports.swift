/// Stable application-facing module.
///
/// SwiftUIWeb intentionally re-exports the implementation layers so existing
/// applications can continue to use `import SwiftUIWeb` while the runtime is
/// organized into independently testable Core, Fiber, and HTML modules.
///
/// The Foundation stand-ins (`SwiftUIWebNetworking`, `WebFoundation`) exist for Embedded/WASI only. Natively they
/// are not exported: a native application imports Foundation for `URLSession`, `URLRequest`, `URLError`, ..., and
/// exporting SwiftUIWeb's own declarations of those names beside Foundation's makes them ambiguous. The names that
/// SwiftUIWeb's Apple-shaped API needs natively (`URL`, `Data`, `Date`, `Locale`, ...) are typealiases of Foundation's.
@_exported import SwiftUIWebCore
@_exported import SwiftUIWebFeatures
@_exported import SwiftUIWebInternationalization
@_exported import SwiftUIWebNetworking
@_exported import WebFoundation
@_exported import SwiftUIWebFiber
@_exported import SwiftUIWebHTML
@_exported import SwiftUIWebTransferable
