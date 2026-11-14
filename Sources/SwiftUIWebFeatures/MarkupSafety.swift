@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebTransferable

/// `true` when `value` would run script if a browser navigated to it (`javascript:`, `vbscript:`). Embedded
/// documents such as an iframe accept more schemes than `_safeURLAttribute` does (`data:`, `blob:`), so they use this
/// narrower check.
@_spi(Renderer) public func _isScriptURL(_ value: String) -> Bool {
  guard let scheme = _urlScheme(value) else { return false }
  return scheme == "javascript" || scheme == "vbscript"
}
