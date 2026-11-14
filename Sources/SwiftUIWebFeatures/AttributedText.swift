@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
// Styled-run support behind `Text(AttributedString)`. Everything here compiles
// on every platform so the DOM mapping is testable natively; the Foundation
// stand-in `AttributedString` itself lives in AttributedString.swift.

extension Text {
  /// SwiftUI's `Text.LineStyle` (underline/strikethrough appearance).
  public struct LineStyle: Hashable, Sendable {
    public enum Pattern: Hashable, Sendable {
      case solid, dot, dash, dashDot, dashDotDot
    }
    var pattern: Pattern
    var color: Color?
    public init(pattern: Text.LineStyle.Pattern = .solid, color: Color? = nil) {
      self.pattern = pattern
      self.color = color
    }
    public static let single = LineStyle()
    var _cssStyle: String {
      switch pattern {
      case .solid: return "solid"
      case .dot: return "dotted"
      case .dash, .dashDot, .dashDotDot: return "dashed"
      }
    }
  }
}

/// Attributes of one character run. Equality decides run boundaries.
public struct _TextAttributes: Equatable, Sendable {
  var kern: Double?
  var tracking: Double?
  var foregroundColor: Color?
  var backgroundColor: Color?
  var fontStyles: _NodeValues?
  var underlineStyle: Text.LineStyle?
  var strikethroughStyle: Text.LineStyle?
  var linkString: String?
  var baselineOffset: Double?
  var inlineIntent: InlinePresentationIntent?

  var isEmpty: Bool { self == _TextAttributes() }

  /// Attributes shared by both values; a property that differs becomes nil.
  func _common(with other: _TextAttributes) -> _TextAttributes {
    _TextAttributes(
      kern: _sameValue(kern, other.kern),
      tracking: _sameValue(tracking, other.tracking),
      foregroundColor: _sameValue(foregroundColor, other.foregroundColor),
      backgroundColor: _sameValue(backgroundColor, other.backgroundColor),
      fontStyles: _sameValue(fontStyles, other.fontStyles),
      underlineStyle: _sameValue(underlineStyle, other.underlineStyle),
      strikethroughStyle: _sameValue(strikethroughStyle, other.strikethroughStyle),
      linkString: _sameValue(linkString, other.linkString),
      baselineOffset: _sameValue(baselineOffset, other.baselineOffset),
      inlineIntent: _sameValue(inlineIntent, other.inlineIntent))
  }

  /// Non-nil properties of `other` replace this value's (Apple's `merge`).
  mutating func _merge(_ other: _TextAttributes) {
    if let value = other.kern { kern = value }
    if let value = other.tracking { tracking = value }
    if let value = other.foregroundColor { foregroundColor = value }
    if let value = other.backgroundColor { backgroundColor = value }
    if let value = other.fontStyles { fontStyles = value }
    if let value = other.underlineStyle { underlineStyle = value }
    if let value = other.strikethroughStyle { strikethroughStyle = value }
    if let value = other.linkString { linkString = value }
    if let value = other.baselineOffset { baselineOffset = value }
    if let value = other.inlineIntent { inlineIntent = value }
  }
}

private func _sameValue<T: Equatable>(_ lhs: T?, _ rhs: T?) -> T? {
  guard let lhs, let rhs, lhs == rhs else { return nil }
  return lhs
}

/// A maximal substring sharing one attribute set.
struct _AttributedRun {
  var text: String
  var attributes: _TextAttributes
}

private func _attributePixels(_ value: Double) -> String {
  guard value.isFinite else { return "0" }
  return Int64(exactly: value).map { String($0) } ?? String(value)
}

extension Text {
  /// Builds a Text from styled runs. A single unstyled run is an ordinary
  /// Text; anything else is a concatenation of inline spans whose outer span
  /// carries the plain string as its accessibility label.
  init(_attributedRuns runs: [_AttributedRun]) {
    var plain = ""
    for run in runs { plain += run.text }
    if runs.count == 1 && runs[0].attributes.isEmpty {
      self.init(verbatim: plain)
      return
    }
    var children: [Text] = []
    for run in runs { children.append(Text._attributedSpan(run)) }
    self.init(verbatim: plain)
    _textRuns = children
    _textStyles.append(_TextStyleDeclaration(property: "aria-label", value: plain, isAttribute: true))
    _textStyles.append(_TextStyleDeclaration(property: "data-a11y-backend", value: "1", isAttribute: true))
  }

  static func _attributedSpan(_ run: _AttributedRun) -> Text {
    var text = Text(verbatim: run.text)
    let attributes = run.attributes
    if let styles = attributes.fontStyles { text = text.font(Font(cssStyles: styles)) }
    if let color = attributes.foregroundColor { text = text.foregroundColor(color) }
    if let color = attributes.backgroundColor { text = text._styled("background-color", color.cssValue) }
    if let spacing = attributes.kern ?? attributes.tracking {
      text = text._styled("letter-spacing", "\(_attributePixels(spacing))px")
    }
    if let offset = attributes.baselineOffset {
      text = text._styled("vertical-align", "\(_attributePixels(offset))px")
    }
    var lines = ""
    var decoration: Text.LineStyle?
    if let underline = attributes.underlineStyle { lines = "underline"; decoration = underline }
    if let strike = attributes.strikethroughStyle {
      lines += lines.isEmpty ? "line-through" : " line-through"
      if decoration == nil { decoration = strike }
    }
    if let decoration {
      text = text._styled("text-decoration-line", lines)
      text = text._styled("text-decoration-style", decoration._cssStyle)
      if let color = decoration.color { text = text._styled("text-decoration-color", color.cssValue) }
    }
    if let link = attributes.linkString {
      // `_renderRuns` wraps a run carrying this declaration in an anchor.
      text._textStyles.append(_TextStyleDeclaration(property: "data-text-href", value: link, isAttribute: true))
    }
    return text
  }
}
