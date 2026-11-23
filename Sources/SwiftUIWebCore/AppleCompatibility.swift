// SwiftUI spellings an application written for Apple's platforms uses and the browser can honour: previews, image
// interpolation, a hierarchical border, `displayScale`, `ImageRenderer`. They are modifiers with a browser meaning
// (a CSS property) or no-ops where the concept has no browser counterpart (previews).

extension View {

  /// A border drawn with any shape style, as `.border(.quaternary)`.
  public nonisolated func border<S: ShapeStyle>(_ content: S, width: Double = 1) -> some View {
    _modified(_borderModifier(Color(css: content._swiftUIWebCSSValue), width: width))
  }
}

extension Image {
  public enum Interpolation: Hashable, Sendable {
    case none, low, medium, high
  }
}

/// A rendered image. In the browser it is the rendered view itself: the DOM already is the bitmap, so
/// `ImageRenderer` hands the view on and `Image(_:scale:label:)` draws it.
public struct CGImage: @unchecked Sendable {
  package let content: AnyView
}

/// Renders a view into an image. The result stays a live view (see `CGImage`), sized by `proposedSize`.
// As in SwiftUI the class itself is not isolated; its members are main-actor isolated.
public final class ImageRenderer<Content: View> {
  @MainActor public var content: Content
  @MainActor public var proposedSize = ProposedViewSize.unspecified
  @MainActor public var scale: CGFloat = 1
  @MainActor public var isOpaque = false

  @MainActor public init(content view: Content) { content = view }

  @MainActor public var cgImage: CGImage? {
    var view = AnyView(content)
    if let width = proposedSize.width, let height = proposedSize.height {
      view = AnyView(content.frame(width: Double(width), height: Double(height)))
    }
    return CGImage(content: view)
  }
}

