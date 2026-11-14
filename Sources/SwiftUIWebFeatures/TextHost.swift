@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
/// The browser's number formatting and text folding (`Intl`, `String.normalize`), installed by the browser runtime
/// before the first render so Core names no browser target. Without one (a native build, a test) or for a malformed
/// request they answer nil and the callers keep their fallback.
package enum _TextHost {
  nonisolated(unsafe) package static var formatNumber: ((String, String) -> String?)?
  nonisolated(unsafe) package static var fold: ((String, Bool, Bool) -> String?)?
}
