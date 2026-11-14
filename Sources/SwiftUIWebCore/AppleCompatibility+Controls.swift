@_spi(Renderer) import SwiftUIWebTransferable

// More SwiftUI spellings from Apple's own samples: List selection, the pre-iOS 15 `Alert`, hierarchical shape-style
// opacity, scaled shapes, and a handful of modifiers whose effect has no browser counterpart (they are accepted and
// ignored, so the source compiles unchanged).

// MARK: List selection

/// What a `List(selection:)` gives its rows: how to select a value, and whether it is selected. Values travel as
/// `_RuntimeValue` because Embedded Swift cannot erase them to `Any`.
@_spi(Renderer) public struct _ListSelection: @unchecked Sendable {
  package let select: (_RuntimeValue) -> Void
  package let isSelected: (_RuntimeValue) -> Bool
  package init(select: @escaping (_RuntimeValue) -> Void, isSelected: @escaping (_RuntimeValue) -> Bool) {
    self.select = select
    self.isSelected = isSelected
  }
}

/// True inside a `Form`: its navigation links read as disclosure rows (label, flexible space, chevron).
enum _GroupedListKey: EnvironmentKey {
  static let defaultValue = false
}

package enum _ListSelectionKey: EnvironmentKey {
  package static let defaultValue: _ListSelection? = nil
}

// MARK: Section

// MARK: Legacy Alert

/// The pre-iOS 15 `Alert`, presented with `.alert(isPresented:content:)`.
public struct Alert {
  public struct Button {
    let label: Text
    let action: (() -> Void)?
    let role: ButtonRole?

    public static func `default`(_ label: Text, action: (() -> Void)? = {}) -> Alert.Button {
      Button(label: label, action: action, role: nil)
    }

    public static func cancel(_ label: Text, action: (() -> Void)? = {}) -> Alert.Button {
      Button(label: label, action: action, role: .cancel)
    }

    public static func cancel(_ action: (() -> Void)? = {}) -> Alert.Button {
      Button(label: Text("Cancel"), action: action, role: .cancel)
    }

    public static func destructive(_ label: Text, action: (() -> Void)? = {}) -> Alert.Button {
      Button(label: label, action: action, role: .destructive)
    }
  }

  let title: Text
  let message: Text?
  let buttons: [Button]

  public init(title: Text, message: Text? = nil, dismissButton: Alert.Button? = nil) {
    self.title = title
    self.message = message
    buttons = [dismissButton ?? .default(Text("OK"))]
  }

  public init(title: Text, message: Text? = nil, primaryButton: Alert.Button, secondaryButton: Alert.Button) {
    self.title = title
    self.message = message
    buttons = [primaryButton, secondaryButton]
  }
}

public extension View {
  nonisolated func alert(isPresented: Binding<Bool>, content: @escaping () -> Alert) -> some View {
    let alert = content()
    return self.alert(alert.title, isPresented: isPresented, actions: {
      ForEach(Array(alert.buttons.enumerated()), id: { $0.offset }) { _, button in
        // SAFETY: the alert's buttons are only read by the main-actor presentation that renders them.
        nonisolated(unsafe) let button = button
        SwiftUIWebCore.Button(role: button.role, action: { button.action?() }) { button.label }
      }
    }, message: {
      if let message = alert.message { message }
    })
  }
}

// MARK: Shape styles

/// A shape style at a fraction of its strength: `.quaternary.opacity(0.5)`.
public struct _OpacityShapeStyle<Base: ShapeStyle>: ShapeStyle {
  let base: Base
  // Not named `opacity`: a stored member would shadow `ShapeStyle.opacity(_:)` for chained calls.
  let strength: Double

  public var _swiftUIWebCSSValue: String {
    // NaN (a ratio of zero to zero) is fully transparent; `max` and `min` would pass it on to Int(), which traps.
    let percent = strength.isNaN ? 0 : Int((min(max(strength, 0), 1) * 100).rounded())
    return "color-mix(in srgb, \(base._swiftUIWebCSSValue) \(percent)%, transparent)"
  }

  public var _swiftUIWebSolidColor: Color? { Color(css: _swiftUIWebCSSValue) }
}

public extension ShapeStyle {
  func opacity(_ opacity: Double) -> _OpacityShapeStyle<Self> { _OpacityShapeStyle(base: self, strength: opacity) }

  // Apple's instance levels: the receiver at a hierarchical level. The strengths are those of the static
  // `HierarchicalShapeStyle` levels (secondary 60%, tertiary 30%, quaternary 18%, quinary 10%).
  var secondary: some ShapeStyle { opacity(0.6) }
}

/// `ShapeStyle.shadow(_:)`'s argument.
public struct ShadowStyle: Hashable, Sendable {
  let color: Color
  let radius: Double
  let x: Double
  let y: Double
  let isInner: Bool

  public static func drop(color: Color = Color.black.opacity(0.33), radius: Double, x: Double = 0, y: Double = 0) -> ShadowStyle {
    ShadowStyle(color: color, radius: radius, x: x, y: y, isInner: false)
  }

  public static func inner(color: Color = Color.black.opacity(0.55), radius: Double, x: Double = 0, y: Double = 0) -> ShadowStyle {
    ShadowStyle(color: color, radius: radius, x: x, y: y, isInner: true)
  }
}

// MARK: Shapes

/// A shape drawn at a fraction of its rectangle, around the center: `RoundedRectangle(...).scale(0.99)`.
public struct ScaledShape<Content: Shape>: Shape {
  public typealias Body = Never
  public var shape: Content
  public var scale: CGSize
  public var anchor: UnitPoint

  public init(shape: Content, scale: CGSize, anchor: UnitPoint = .center) {
    self.shape = shape
    self.scale = scale
    self.anchor = anchor
  }

  public nonisolated func path(in rect: CGRect) -> Path {
    let width = Double(rect.width) * Double(scale.width)
    let height = Double(rect.height) * Double(scale.height)
    let originX = Double(rect.minX) + (Double(rect.width) - width) * Double(anchor.x)
    let originY = Double(rect.minY) + (Double(rect.height) - height) * Double(anchor.y)
    return shape.path(in: CGRect(x: originX, y: originY, width: width, height: height))
  }
}

public extension Shape {
  nonisolated func scale(_ scale: CGFloat, anchor: UnitPoint = .center) -> ScaledShape<Self> {
    ScaledShape(shape: self, scale: CGSize(width: scale, height: scale), anchor: anchor)
  }
  nonisolated func scale(x: CGFloat = 1, y: CGFloat = 1, anchor: UnitPoint = .center) -> ScaledShape<Self> {
    ScaledShape(shape: self, scale: CGSize(width: x, height: y), anchor: anchor)
  }
}

// MARK: Modifiers without a browser effect

// MARK: Dynamic Type

extension DynamicTypeSize: Comparable {
  private static let order = [
    "xSmall", "small", "medium", "large", "xLarge", "xxLarge", "xxxLarge",
    "accessibility1", "accessibility2", "accessibility3", "accessibility4", "accessibility5"
  ]

  private var rank: Int { Self.order.firstIndex(of: rawValue) ?? 3 }

  public static func < (lhs: DynamicTypeSize, rhs: DynamicTypeSize) -> Bool { lhs.rank < rhs.rank }
}

// MARK: Toolbar

// MARK: Menus and text

/// SwiftUI's menu style. The browser menu is a disclosure; the styles differ only in chrome the
/// framework draws itself, so `menuStyle(_:)` accepts every style and leaves the view unchanged.
@MainActor @preconcurrency public protocol MenuStyle {
  var _swiftUIWebMenuStyle: String { get }
}

public extension MenuStyle {
  var _swiftUIWebMenuStyle: String { "automatic" }
}

public nonisolated struct DefaultMenuStyle: MenuStyle {
  public nonisolated init() {}
  public var _swiftUIWebMenuStyle: String { "automatic" }
}

public nonisolated struct ButtonMenuStyle: MenuStyle {
  public nonisolated init() {}
  public var _swiftUIWebMenuStyle: String { "button" }
}

public extension MenuStyle where Self == DefaultMenuStyle {
  @MainActor @preconcurrency static var automatic: DefaultMenuStyle { DefaultMenuStyle() }
}

public extension MenuStyle where Self == ButtonMenuStyle {
  static nonisolated var button: ButtonMenuStyle { ButtonMenuStyle() }
}

public extension View {
  /// `lineLimit(_:reservesSpace:)`: with `reservesSpace`, the text keeps room for `limit` lines even when it needs fewer.
  nonisolated func lineLimit(_ limit: Int, reservesSpace: Bool) -> some View {
    lineLimit(limit).modifier(StyleModifier(styles: reservesSpace ? ["min-height": "calc(\(limit) * 1lh)"] : [:]))
  }
}

