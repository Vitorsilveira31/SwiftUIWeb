@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
/// The number formatting and text folding that answer `_swiftUIWebFormatNumber` and `_swiftUIWebFoldText`. For a
/// malformed request they answer nil and the callers keep their fallback.
///
/// Every WebAssembly build of SwiftUIWeb is the browser product (the Embedded release and the full-Swift development
/// profile): there the browser runtime installs `Intl` and `String.normalize` (BrowserIO) before the first render, so
/// Core names no browser target, and nothing else is linked. A native build (tests, tools) has no browser at all: it
/// starts with Swift's answers, Foundation's output on Apple platforms (NativeNumberFormatting.swift,
/// NativeStringFolding.swift, compiled only off wasm32). This is the only place the two builds differ.
package enum _TextHost {
  #if arch(wasm32)
  nonisolated(unsafe) package static var formatNumber: ((String, String) -> String?)?
  nonisolated(unsafe) package static var fold: ((String, Bool, Bool) -> String?)?
  #else
  nonisolated(unsafe) package static var formatNumber: ((String, String) -> String?)? = { _swiftNumberFormat($0, options: $1) }
  nonisolated(unsafe) package static var fold: ((String, Bool, Bool) -> String?)? = { _swiftFoldText($0, diacritics: $1, case: $2) }
  #endif
}
