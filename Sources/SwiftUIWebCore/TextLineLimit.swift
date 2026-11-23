/// SwiftUI's `lineLimit(_:)` is an inherited environment value: applied to a
/// container (for example a button style applying it to its label) it limits
/// every `Text` inside, not the container box. CSS line clamping does not
/// inherit, so each `Text` leaf writes the clamp for the limit it resolves
/// from its environment.
private enum LineLimitEnvironmentKey: EnvironmentKey {
  static let defaultValue: Int? = nil
}

extension EnvironmentValues {
  /// The maximum number of lines that text can occupy in a view.
  public var lineLimit: Int? {
    get { self[LineLimitEnvironmentKey.self] }
    set { self[LineLimitEnvironmentKey.self] = newValue }
  }
}

/// The fewest lines a multi-line field keeps (`lineLimit(_:)` with a range). Text ignores it.
private enum LineLimitMinimumEnvironmentKey: EnvironmentKey {
  static let defaultValue: Int? = nil
}

extension EnvironmentValues {
  package var _lineLimitMinimum: Int? {
    get { self[LineLimitMinimumEnvironmentKey.self] }
    set { self[LineLimitMinimumEnvironmentKey.self] = newValue }
  }
}

extension View {
  /// Sets the maximum number of lines that text can occupy in this view.
  public nonisolated func lineLimit(_ number: Int?) -> some View {
    _modified(EnvironmentOverride(apply: { $0.lineLimit = number; $0._lineLimitMinimum = nil }))
  }

  /// SwiftUI's `lineLimit(_:)` with a range: a multi-line field keeps at least the lower bound of lines and grows to the
  /// upper bound, then scrolls. Text is limited to the upper bound.
  public nonisolated func lineLimit(_ limit: ClosedRange<Int>) -> some View {
    _modified(EnvironmentOverride(apply: { $0.lineLimit = limit.upperBound; $0._lineLimitMinimum = limit.lowerBound }))
  }

  /// SwiftUI's `lineLimit(_:)` from a lower bound: a multi-line field keeps at least that many lines and grows without a
  /// maximum.
  public nonisolated func lineLimit(_ limit: PartialRangeFrom<Int>) -> some View {
    _modified(EnvironmentOverride(apply: { $0.lineLimit = nil; $0._lineLimitMinimum = limit.lowerBound }))
  }

  /// SwiftUI's `lineLimit(_:)` up to an upper bound: a multi-line field grows to that many lines, then scrolls.
  public nonisolated func lineLimit(_ limit: PartialRangeThrough<Int>) -> some View {
    _modified(EnvironmentOverride(apply: { $0.lineLimit = limit.upperBound; $0._lineLimitMinimum = nil }))
  }
}

extension EnvironmentValues {
  /// Sizes a multi-line field (`TextField(axis: .vertical)`) from the inherited line limits. The bounds are in lines of text:
  /// the stylesheet turns `--lines-min` and `--lines-max` into heights that add the control's own padding and border, and
  /// `field-sizing: content` lets the field grow with its text in between. A field with a limit starts at one line (or at its
  /// lower bound), not at the stylesheet's base height, so a small maximum is not defeated by it.
  func _applyFieldLineLimit(to node: _RenderNode) {
    guard _lineLimitMinimum != nil || lineLimit != nil else { return }
    let minimum = Swift.max(1, _lineLimitMinimum ?? 1)
    node.attributes["rows"] = String(minimum)
    node.attributes["data-lines-min"] = String(minimum)
    node.styles["--lines-min"] = String(minimum)
    // The field grows with its text whenever it has a limit, a lower bound alone included (`lineLimit(2...)`): the
    // stylesheet's `.text-area` is `field-sizing: fixed`, which would keep it at its fewest rows and scroll inside.
    node.styles["field-sizing"] = "content"
    guard let maximum = lineLimit else { return }
    let lines = Swift.max(minimum, maximum)
    node.attributes["data-lines-max"] = String(lines)
    node.styles["--lines-max"] = String(lines)
  }
}

extension Text {
  /// Writes the browser clamp for the inherited line limit on a text leaf.
  /// Explicit per-leaf declarations win, so this never overrides a style the
  /// application already chose for the same property.
  ///
  /// One line is a block that does not wrap and ends in an ellipsis where it is cut, as SwiftUI truncates inside a word
  /// ("Resched…"): a line clamp only ends a line that wrapped with one, so a single word wider than its box was clipped.
  /// It keeps `-webkit-line-clamp: 1`, which draws nothing on a block and tells the layout host the text is one line.
  func _applyLineLimit(_ limit: Int?, to node: _RenderNode) {
    guard let limit else { return }
    let clamp = limit > 0 ? limit : 1
    let declarations = clamp == 1
      ? [
        ("display", "block"),
        ("-webkit-line-clamp", "1"),
        ("white-space", "nowrap"),
        ("overflow", "hidden"),
        ("text-overflow", "ellipsis"),
      ]
      : [
        ("display", "-webkit-box"),
        ("-webkit-line-clamp", String(clamp)),
        ("-webkit-box-orient", "vertical"),
        ("overflow", "hidden"),
      ]
    for (property, value) in declarations where node.styles[property] == nil {
      node.styles[property] = value
    }
  }
}
