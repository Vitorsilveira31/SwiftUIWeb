@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

/// SwiftUI's Text-returning modifiers and `Text + Text` concatenation.
///
/// Apple's `Text` exposes these modifiers as members that return `Text`, which
/// is what makes rich runs such as
/// `Text("8 tasks").bold() + Text(" and ") + Text("1 job").foregroundColor(.red)`
/// compile. The members below mirror the parameter types of the corresponding
/// `View` modifiers so that overload resolution always prefers the concrete
/// `Text` member (a more specialized declaration context) and existing call
/// sites keep compiling. The result still conforms to `View`, so chained view
/// modifiers such as `.lineLimit(2)` or `.padding()` are unchanged.
///
/// Rendering: an ordinary Text stays one text node carrying its declarations.
/// A concatenation renders one `span` text leaf whose runs are inline child
/// spans. Modifiers applied to the concatenation style the outer span and are
/// inherited by the runs; a run's own modifiers take precedence, matching
/// SwiftUI's "inner modifier wins" behavior.
extension Text {
  /// Concatenates two texts into one styled paragraph.
  @_disfavoredOverload
  public static func + (lhs: Text, rhs: Text) -> Text {
    var runs: [Text] = []
    if lhs._isPlainConcatenation { runs.append(contentsOf: lhs._textRuns) } else { runs.append(lhs) }
    if rhs._isPlainConcatenation { runs.append(contentsOf: rhs._textRuns) } else { runs.append(rhs) }
    var result = Text(verbatim: lhs.value + rhs.value)
    result._textRuns = runs
    return result
  }

  public nonisolated func bold() -> Text { _styled("font-weight", "700") }

  public nonisolated func bold(_ isActive: Bool) -> Text { isActive ? bold() : self }

  public nonisolated func fontWeight(_ weight: Font.Weight?) -> Text {
    guard let weight else { return self }
    return _styled("font-weight", weight.rawValue)
  }

  public nonisolated func fontDesign(_ design: Font.Design?) -> Text {
    guard let design else { return self }
    return _styled("font-family", design.rawValue)
  }

  public nonisolated func italic() -> Text { _styled("font-style", "italic") }

  public nonisolated func italic(_ isActive: Bool) -> Text { _styled("font-style", isActive ? "italic" : "normal") }

  public nonisolated func foregroundColor(_ color: Color) -> Text { _styled("color", color.cssValue) }

  public func foregroundColor(_ color: Color?) -> Text {
    guard let color else { return self }
    return foregroundColor(color)
  }

  public nonisolated func foregroundStyle<S: ShapeStyle>(_ style: S) -> Text {
    // Same realization and metadata as the View-level
    // `ShapeStyleForegroundModifier`: solid colors set `color`; gradients and
    // other paints clip a background to the glyphs.
    var copy = self
    copy._textStyles.append(_TextStyleDeclaration(property: "data-foreground-style", value: style._swiftUIWebCSSValue, isAttribute: true))
    if style._swiftUIWebSolidColor != nil {
      return copy._styled("color", _foregroundPaintCSSValue(style))
    }
    for (name, value) in _unresolvedImagePaintMarkers(style) {
      copy._textStyles.append(_TextStyleDeclaration(property: name, value: value, isAttribute: true))
    }
    return copy._styled("background-image", style._swiftUIWebCSSValue)
      ._styled("background-clip", "text")
      ._styled("-webkit-background-clip", "text")
      ._styled("color", "transparent")
  }

  public nonisolated func strikethrough(_ active: Bool = true, color: Color? = nil) -> Text {
    var copy = _styled("text-decoration-line", active ? "line-through" : "none")
    if let color { copy = copy._styled("text-decoration-color", color.cssValue) }
    return copy
  }

  public nonisolated func monospacedDigit() -> Text { _styled("font-variant-numeric", "tabular-nums") }

  public nonisolated func kerning(_ value: Double) -> Text { _styled("letter-spacing", "\(_textPixels(value))px") }

  @_disfavoredOverload public func kerning(_ value: Float) -> Text { kerning(Double(value)) }

  public nonisolated func baselineOffset(_ value: Double) -> Text { _styled("vertical-align", "\(_textPixels(value))px") }

  @_disfavoredOverload public func baselineOffset(_ value: Float) -> Text { baselineOffset(Double(value)) }

  var _isPlainConcatenation: Bool { !_textRuns.isEmpty && _textStyles.isEmpty && !_hasCustomAttributes }
}
