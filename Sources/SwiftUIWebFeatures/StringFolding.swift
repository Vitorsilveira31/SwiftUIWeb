@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
// Foundation's `String.folding(options:locale:)`, so search and filter code
// written against Foundation compiles unchanged. ASCII is folded here; any
// other text goes to the browser (`text-format.mjs`: canonical decomposition
// without the combining marks, then lowercase), which knows every script, or,
// in a native build that has no browser, to NativeStringFolding.swift.

/// Host-neutral folding shared by the Foundation-shaped API below and by
/// renderer code. Without a browser (a native build) Swift folds the text as
/// Foundation does on Apple platforms (NativeStringFolding.swift).
@_spi(Renderer) public func _swiftUIWebFoldText(_ value: String, diacritics: Bool, case foldsCase: Bool) -> String {
  guard diacritics || foldsCase else { return value }
  var bytes = Array(value.utf8)
  guard bytes.allSatisfy({ $0 < 0x80 }) else {
    return _TextHost.fold?(value, diacritics, foldsCase) ?? value
  }
  guard foldsCase else { return value }
  for index in bytes.indices where bytes[index] >= 65 && bytes[index] <= 90 { bytes[index] += 32 }
  return String(decoding: bytes, as: UTF8.self)
}

public extension String {
  /// Foundation's `String.CompareOptions`, with Foundation's raw values. `folding` honors the case, diacritic and width
  /// options; `range(of:options:)` (WebFoundation) the case, backwards and anchored ones.
  struct CompareOptions: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let caseInsensitive = CompareOptions(rawValue: 1)
    public static let literal = CompareOptions(rawValue: 2)
    public static let backwards = CompareOptions(rawValue: 4)
    public static let anchored = CompareOptions(rawValue: 8)
    public static let numeric = CompareOptions(rawValue: 64)
    public static let diacriticInsensitive = CompareOptions(rawValue: 128)
    public static let widthInsensitive = CompareOptions(rawValue: 256)
  }
}

// Foundation declares `folding` on StringProtocol.
public extension StringProtocol {
  /// Foundation's `folding(options:locale:)`: `.diacriticInsensitive` strips
  /// Latin, Greek and Cyrillic accents and `.caseInsensitive` folds case. The locale
  /// is accepted for source compatibility; folding is locale-independent here.
  func folding(options: String.CompareOptions = [], locale: Locale?) -> String {
    _swiftUIWebFoldText(String(self), diacritics: options.contains(.diacriticInsensitive), case: options.contains(.caseInsensitive))
  }
}
