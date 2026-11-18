@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
// Host-neutral number formatting shared by the Foundation-shaped number
// `FormatStyle`s of SwiftUIWebInternationalization and by renderer code.
// The browser formats it (`Intl.NumberFormat`, see `text-format.mjs`), fed
// with the shortest decimal text of the value so no floating point crosses
// the boundary and rounding is exact half-even on those digits.

/// Formats `decimalText` (as Swift prints the value: `28300.4`, `1e+21`,
/// `nan`) with `name=value;...` options; natively Swift formats it as Foundation
/// does (NativeNumberFormatting.swift). Malformed input yields the text itself
/// so a bad option never turns into a trap in a view body.
@_spi(Renderer) public func _swiftUIWebFormatNumber(_ decimalText: String, options: String) -> String {
  _TextHost.formatNumber?(decimalText, options) ?? decimalText
}

/// The shortest round-trip decimal text of a floating-point value, which
/// the browser formats exactly.
@_spi(Renderer) public func _swiftUIWebDecimalText<Value: BinaryFloatingPoint>(_ value: Value) -> String {
  "\(Double(value))"
}

@_spi(Renderer) public func _swiftUIWebDecimalText<Value: BinaryInteger>(_ value: Value) -> String {
  String(value)
}
