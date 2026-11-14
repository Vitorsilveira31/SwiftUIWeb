@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

/// iOS 26's Liquid Glass: a translucent, blurred, softly lit surface. The browser realization is a backdrop blur
/// with a light fill and a hairline highlight edge, clipped to the shape.
public struct Glass: Equatable, Sendable {
  var tintColor: Color?
  var isInteractive = false
  var isClear = false

  public static let regular = Glass()
  public static let clear = Glass(isClear: true)
  public static let identity = Glass()

  public func tint(_ color: Color?) -> Glass { var copy = self; copy.tintColor = color; return copy }
  public func interactive(_ isEnabled: Bool = true) -> Glass { var copy = self; copy.isInteractive = isEnabled; return copy }
}

private nonisolated struct _GlassBackground<S: Shape>: ViewModifier {
  let glass: Glass
  let shape: S

  nonisolated init(glass: Glass, shape: S) {
    self.glass = glass
    self.shape = shape
  }

  @MainActor func body(content: Content) -> some View {
    content
      .background(Material.thin, in: shape)
      .background(glass.tintColor ?? Color.white.opacity(glass.isClear ? 0.04 : 0.14), in: shape)
      .overlay(shape.stroke(Color.white.opacity(0.28), lineWidth: 1))
      .clipShape(shape)
  }
}

public extension View {
  // Nonisolated like SwiftUI's declarations (`glassEffectUnion` stays @MainActor there). These build the
  // wrapper directly instead of calling the MainActor-isolated `modifier(_:)`, which would send the
  // non-Sendable `self` across an isolation boundary.
  nonisolated func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View {
    ModifiedContent(content: self, modifier: _GlassBackground(glass: glass, shape: shape))
  }

  /// Glass elements close to each other blend into one; the browser draws each on its own.
  nonisolated func glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View { self }

  @MainActor @preconcurrency func glassEffectUnion(id: (some Hashable & Sendable)?, namespace: Namespace.ID) -> some View { self }

  @MainActor @preconcurrency func backgroundExtensionEffect() -> some View { self }
}

@MainActor @preconcurrency public struct GlassEffectContainer<Content: View>: View {
  let spacing: CGFloat?
  let content: Content
  @MainActor @preconcurrency public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
    self.spacing = spacing
    self.content = content()
  }
  @MainActor @preconcurrency public var body: some View { content }
}

/// SwiftUI's glass button style. The browser draws it as a bordered button, which is what `.bordered` maps to.
public nonisolated struct GlassButtonStyle: PrimitiveButtonStyle {
  public nonisolated init() {}
  public nonisolated func makeBody(configuration: GlassButtonStyle.Configuration) -> some View { configuration.label }
  public nonisolated var _swiftUIWebButtonStyleToken: String? { "bordered" }
}

/// SwiftUI's prominent glass button style, drawn as a prominent bordered button.
public nonisolated struct GlassProminentButtonStyle: PrimitiveButtonStyle {
  public nonisolated init() {}
  public nonisolated func makeBody(configuration: GlassProminentButtonStyle.Configuration) -> some View { configuration.label }
  public nonisolated var _swiftUIWebButtonStyleToken: String? { "bordered-prominent" }
}

public extension PrimitiveButtonStyle where Self == GlassButtonStyle {
  static nonisolated var glass: GlassButtonStyle { GlassButtonStyle() }
}

public extension PrimitiveButtonStyle where Self == GlassProminentButtonStyle {
  @MainActor @preconcurrency static var glassProminent: GlassProminentButtonStyle { GlassProminentButtonStyle() }
}

public enum ScrollEdgeEffectStyle: Sendable { case automatic, hard, soft }

public extension View {
  /// The soft fade where content scrolls under a bar; the browser keeps content crisp.
  nonisolated func scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle?, for edges: Edge.Set) -> some View { self }
}
