
/// SwiftUI's contextual `ShapeStyle` members beyond the named colors (which
/// live in ShapeStyleColorMembers.swift): hierarchical levels, `.tint`,
/// `.foreground`, `.background`, `.separator` and gradient factories. They make
/// generic call sites such as `.foregroundStyle(.tertiary)`,
/// `.background(.tint, in: .capsule)` or
/// `.fill(.linearGradient(colors: [...], startPoint: .top, endPoint: .bottom))`
/// type-check. `Color`'s own statics (e.g. `Color.secondary`) shadow these
/// members for concrete `Color` contexts, as in SwiftUI.

/// A level of the current foreground style (`.primary` ... `.quinary`).
///
/// SwiftUI derives each level from the inherited foreground style. The
/// browser realization keeps that relationship by mixing `currentColor`, so
/// `.foregroundStyle(.secondary)` below a red foreground is a lighter red,
/// and a color-scheme change needs no Swift re-render.
public struct HierarchicalShapeStyle: ShapeStyle, Hashable, Sendable {
  let level: Int
  public static let primary = HierarchicalShapeStyle(level: 0)
  public static let secondary = HierarchicalShapeStyle(level: 1)
  public static let tertiary = HierarchicalShapeStyle(level: 2)
  public static let quaternary = HierarchicalShapeStyle(level: 3)
  public static let quinary = HierarchicalShapeStyle(level: 4)

  public var _swiftUIWebCSSValue: String {
    // Opacities follow the iOS label hierarchy (1, 0.6, 0.3, 0.18, 0.1).
    switch level {
    case 0: return "currentColor"
    case 1: return "color-mix(in srgb, currentColor 60%, transparent)"
    case 2: return "color-mix(in srgb, currentColor 30%, transparent)"
    case 3: return "color-mix(in srgb, currentColor 18%, transparent)"
    default: return "color-mix(in srgb, currentColor 10%, transparent)"
    }
  }
  public var _swiftUIWebSolidColor: Color? { Color(_swiftUIWebCSSValue) }
  /// The paint a rendered element takes. A secondary or tertiary level reads the style that
  /// `foregroundStyle(_:_:)` or `foregroundStyle(_:_:_:)` set on an ancestor, and falls back to its color mix, so
  /// `_swiftUIWebCSSValue` (the static value that is parsed as a Color) is not changed.
  package var _paintCSSValue: String {
    switch level {
    case 1: return "var(--secondary-style, \(_swiftUIWebCSSValue))"
    case 2: return "var(--tertiary-style, \(_swiftUIWebCSSValue))"
    default: return _swiftUIWebCSSValue
    }
  }
}

/// The CSS paint of a style as rendered: hierarchical levels 1 and 2 read the foreground styles set by
/// `foregroundStyle(_:_:)` and `foregroundStyle(_:_:_:)`; every other style is its own CSS value.
package func _foregroundPaintCSSValue<S: ShapeStyle>(_ style: S) -> String {
  if let level = style as? HierarchicalShapeStyle { return level._paintCSSValue }
  return style._swiftUIWebCSSValue
}

public extension ShapeStyle where Self == HierarchicalShapeStyle {
  static var primary: HierarchicalShapeStyle { .primary }
  static var secondary: HierarchicalShapeStyle { .secondary }
}

/// The view's tint (`.tint(_:)`), falling back to the accent color.
public struct TintShapeStyle: ShapeStyle, Hashable, Sendable {
  public init() {}
  public var _swiftUIWebCSSValue: String { Color._currentTint.cssValue }
  public var _swiftUIWebSolidColor: Color? { Color._currentTint }
}

/// The inherited foreground style.
public struct ForegroundStyle: ShapeStyle, Hashable, Sendable {
  public init() {}
  public var _swiftUIWebCSSValue: String { "currentColor" }
  public var _swiftUIWebSolidColor: Color? { Color(css: "currentColor") }
}

/// The environment's background style (the color-scheme aware canvas).
public struct BackgroundStyle: ShapeStyle, Hashable, Sendable {
  public init() {}
  /// The environment's background style (`backgroundStyle(_:)` sets it for the views inside, as a custom property they
  /// inherit), or the system background.
  public var _swiftUIWebCSSValue: String { "var(--swu-background-style, \(Color.systemBackground.cssValue))" }
  public var _swiftUIWebSolidColor: Color? { Color.systemBackground }
}

/// The platform separator color.
public struct SeparatorShapeStyle: ShapeStyle, Hashable, Sendable {
  public init() {}
  public var _swiftUIWebCSSValue: String { Color.separator.cssValue }
  public var _swiftUIWebSolidColor: Color? { Color.separator }
}

public extension ShapeStyle where Self == TintShapeStyle {
  static var tint: TintShapeStyle { TintShapeStyle() }
}

public extension ShapeStyle where Self == ForegroundStyle {
  static var foreground: ForegroundStyle { ForegroundStyle() }
}

public extension ShapeStyle where Self == BackgroundStyle {
  static var background: BackgroundStyle { BackgroundStyle() }
}

public extension ShapeStyle where Self == SeparatorShapeStyle {
  static var separator: SeparatorShapeStyle { SeparatorShapeStyle() }
}

public extension ShapeStyle where Self == LinearGradient {
  static func linearGradient(_ gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) -> LinearGradient {
    LinearGradient(gradient: gradient, startPoint: startPoint, endPoint: endPoint)
  }
  static func linearGradient(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) -> LinearGradient {
    LinearGradient(colors: colors, startPoint: startPoint, endPoint: endPoint)
  }
  static func linearGradient(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) -> LinearGradient {
    LinearGradient(stops: stops, startPoint: startPoint, endPoint: endPoint)
  }
  static func linearGradient(_ gradient: AnyGradient, startPoint: UnitPoint, endPoint: UnitPoint) -> LinearGradient {
    LinearGradient(gradient: gradient.gradient, startPoint: startPoint, endPoint: endPoint)
  }
}

public extension ShapeStyle where Self == RadialGradient {
  static func radialGradient(_ gradient: Gradient, center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) -> RadialGradient {
    RadialGradient(gradient: gradient, center: center, startRadius: Double(startRadius), endRadius: Double(endRadius))
  }
  static func radialGradient(colors: [Color], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) -> RadialGradient {
    RadialGradient(colors: colors, center: center, startRadius: Double(startRadius), endRadius: Double(endRadius))
  }
  static func radialGradient(stops: [Gradient.Stop], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) -> RadialGradient {
    RadialGradient(stops: stops, center: center, startRadius: Double(startRadius), endRadius: Double(endRadius))
  }
  static func radialGradient(_ gradient: AnyGradient, center: UnitPoint = .center, startRadius: CGFloat = 0, endRadius: CGFloat) -> RadialGradient {
    RadialGradient(gradient: gradient.gradient, center: center, startRadius: Double(startRadius), endRadius: Double(endRadius))
  }
}
