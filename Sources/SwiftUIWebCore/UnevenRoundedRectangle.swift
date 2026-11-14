
/// Describes the corner radius of each corner of a rectangle
/// (SwiftUI's `RectangleCornerRadii`).
public struct RectangleCornerRadii: Hashable, Sendable {
  public var topLeading: CGFloat
  public var bottomLeading: CGFloat
  public var bottomTrailing: CGFloat
  public var topTrailing: CGFloat

  public init(topLeading: CGFloat = 0, bottomLeading: CGFloat = 0, bottomTrailing: CGFloat = 0, topTrailing: CGFloat = 0) {
    self.topLeading = topLeading
    self.bottomLeading = bottomLeading
    self.bottomTrailing = bottomTrailing
    self.topTrailing = topTrailing
  }
}

/// A rectangle whose corners each have their own radius
/// (SwiftUI's `UnevenRoundedRectangle`).
///
/// The geometry is a real `Path` (fill, stroke, trim and custom clip masks
/// share it), and CSS-backed paths — `clipShape`, `background(_:in:)`,
/// `contentShape` — use logical per-corner `border-*-radius` properties so
/// leading/trailing follow the layout direction like SwiftUI.
public struct UnevenRoundedRectangle: InsettableShape, Hashable, Sendable {
  public typealias Body = Never
  public var cornerRadii: RectangleCornerRadii
  public var style: RoundedCornerStyle
  var _insetAmount: Double = 0

  public init(cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) {
    self.cornerRadii = cornerRadii
    self.style = style
  }

  public init(
    topLeadingRadius: CGFloat = 0,
    bottomLeadingRadius: CGFloat = 0,
    bottomTrailingRadius: CGFloat = 0,
    topTrailingRadius: CGFloat = 0,
    style: RoundedCornerStyle = .continuous
  ) {
    self.init(
      cornerRadii: RectangleCornerRadii(
        topLeading: topLeadingRadius,
        bottomLeading: bottomLeadingRadius,
        bottomTrailing: bottomTrailingRadius,
        topTrailing: topTrailingRadius
      ),
      style: style
    )
  }

  public nonisolated func inset(by amount: CGFloat) -> UnevenRoundedRectangle {
    var copy = self
    copy._insetAmount += max(0, Double(amount))
    return copy
  }

  public nonisolated func path(in rect: CGRect) -> Path {
    let inset = _insetAmount
    let insetRect = CGRect(
      origin: CGPoint(x: rect.origin.x + inset, y: rect.origin.y + inset),
      size: CGSize(width: max(0, rect.size.width - inset * 2), height: max(0, rect.size.height - inset * 2))
    )
    return Path(roundedRect: insetRect, cornerRadii: _insetRadii, style: style)
  }

  /// Radii after `inset(by:)`, as SwiftUI shrinks each corner by the inset.
  var _insetRadii: RectangleCornerRadii {
    RectangleCornerRadii(
      topLeading: CGFloat(max(0, Double(cornerRadii.topLeading) - _insetAmount)),
      bottomLeading: CGFloat(max(0, Double(cornerRadii.bottomLeading) - _insetAmount)),
      bottomTrailing: CGFloat(max(0, Double(cornerRadii.bottomTrailing) - _insetAmount)),
      topTrailing: CGFloat(max(0, Double(cornerRadii.topTrailing) - _insetAmount))
    )
  }

  /// Logical CSS corner radii for CSS-realized clips and backgrounds.
  var _cssCornerStyles: _NodeValues {
    let radii = _insetRadii
    var styles: _NodeValues = [:]
    styles["border-start-start-radius"] = _cssPixels(radii.topLeading)
    styles["border-start-end-radius"] = _cssPixels(radii.topTrailing)
    styles["border-end-end-radius"] = _cssPixels(radii.bottomTrailing)
    styles["border-end-start-radius"] = _cssPixels(radii.bottomLeading)
    return styles
  }

  /// Physical CSS `border-radius` shorthand (left-to-right) used in metadata.
  var _cssBorderRadius: String {
    let radii = _insetRadii
    let top = _cssPixels(radii.topLeading) + " " + _cssPixels(radii.topTrailing)
    let bottom = _cssPixels(radii.bottomTrailing) + " " + _cssPixels(radii.bottomLeading)
    return top + " " + bottom
  }
}

private func _cssPixels(_ value: CGFloat) -> String { _pathNumber(Double(value)) + "px" }

public extension Path {
  /// Creates a rectangle path whose corners each have their own radius.
  init(roundedRect rect: CGRect, cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) {
    self.init()
    addRoundedRect(in: rect, cornerRadii: cornerRadii, style: style)
  }

  /// Adds a rectangle with individually rounded corners. Each radius is
  /// clamped to half of the rectangle's shorter side, and corners are drawn
  /// as circular quarter arcs with cubic Béziers (the same curve Core
  /// Graphics uses for `.circular` corners).
  mutating func addRoundedRect(
    in rect: CGRect,
    cornerRadii: RectangleCornerRadii,
    style: RoundedCornerStyle = .continuous,
    transform: CGAffineTransform = _swiftUIWebIdentityAffineTransform()
  ) {
    _ = style
    let x = Double(rect.origin.x), y = Double(rect.origin.y)
    let width = max(0, Double(rect.size.width)), height = max(0, Double(rect.size.height))
    let limit = min(width, height) / 2
    func clamped(_ value: CGFloat) -> Double { min(max(0, Double(value)), limit) }
    let tl = clamped(cornerRadii.topLeading), tr = clamped(cornerRadii.topTrailing)
    let br = clamped(cornerRadii.bottomTrailing), bl = clamped(cornerRadii.bottomLeading)
    // Distance of a cubic control point from the corner's tangent point
    // for a quarter circle.
    let k = 0.5522847498
    var path = Path()
    func point(_ px: Double, _ py: Double) -> CGPoint { CGPoint(x: CGFloat(px), y: CGFloat(py)) }
    path.move(to: point(x + tl, y))
    path.addLine(to: point(x + width - tr, y))
    if tr > 0 {
      path.addCurve(to: point(x + width, y + tr), control1: point(x + width - tr + tr * k, y), control2: point(x + width, y + tr - tr * k))
    }
    path.addLine(to: point(x + width, y + height - br))
    if br > 0 {
      path.addCurve(to: point(x + width - br, y + height), control1: point(x + width, y + height - br + br * k), control2: point(x + width - br + br * k, y + height))
    }
    path.addLine(to: point(x + bl, y + height))
    if bl > 0 {
      path.addCurve(to: point(x, y + height - bl), control1: point(x + bl - bl * k, y + height), control2: point(x, y + height - bl + bl * k))
    }
    path.addLine(to: point(x, y + tl))
    if tl > 0 {
      path.addCurve(to: point(x + tl, y), control1: point(x, y + tl - tl * k), control2: point(x + tl - tl * k, y))
    }
    path.closeSubpath()
    addPath(path, transform: transform)
  }
}

// MARK: - Contextual shape members (`.rect`, `.circle`, `.capsule`, ...)

public extension Shape where Self == Rectangle {
  static var rect: Rectangle { Rectangle() }
}

public extension Shape where Self == UnevenRoundedRectangle {
  static func rect(
    topLeadingRadius: CGFloat = 0,
    bottomLeadingRadius: CGFloat = 0,
    bottomTrailingRadius: CGFloat = 0,
    topTrailingRadius: CGFloat = 0,
    style: RoundedCornerStyle = .continuous
  ) -> UnevenRoundedRectangle {
    UnevenRoundedRectangle(
      topLeadingRadius: topLeadingRadius,
      bottomLeadingRadius: bottomLeadingRadius,
      bottomTrailingRadius: bottomTrailingRadius,
      topTrailingRadius: topTrailingRadius,
      style: style
    )
  }

  static func rect(cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) -> UnevenRoundedRectangle {
    UnevenRoundedRectangle(cornerRadii: cornerRadii, style: style)
  }
}

public extension Shape where Self == RoundedRectangle {
  static func rect(cornerSize: CGSize, style: RoundedCornerStyle = .continuous) -> RoundedRectangle {
    RoundedRectangle(cornerRadius: Double(min(cornerSize.width, cornerSize.height)), style: style)
  }
}

public extension Shape where Self == Circle {
  static var circle: Circle { Circle() }
}

public extension Shape where Self == Ellipse {
  static var ellipse: Ellipse { Ellipse() }
}

