@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
extension Text {
  /// Renderer SPI for date-bearing texts built by the internationalization
  /// module (`Text(_:style:)`, `Text(_:format:)`, date ranges and timers).
  /// `attributes` travel with the text leaf so a browser host can localize
  /// the value with `Intl` and keep live styles (`.relative`, `.timer`, ...)
  /// ticking without a Swift re-render.
  @_spi(Renderer) public init(_swiftUIWebValue value: String, dateStyle: DateStyle?, attributes: [(String, String)]) {
    self.init(_swiftUIWebValue: value, dateStyle: dateStyle)
    for (name, attributeValue) in attributes {
      _textStyles.append(_TextStyleDeclaration(property: name, value: attributeValue, isAttribute: true))
    }
  }
}
