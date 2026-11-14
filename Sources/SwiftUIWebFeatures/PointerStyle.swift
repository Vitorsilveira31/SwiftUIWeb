@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
/// The pointer appearance SwiftUI's `pointerStyle(_:)` requests while the
/// pointer is over a view. Browsers realize it as the CSS `cursor`, so it
/// costs no Swift work while the pointer moves.
public struct PointerStyle: Hashable, Sendable {
  let cursor: String
  init(cursor: String) { self.cursor = cursor }

  public static let `default` = PointerStyle(cursor: "default")
  public static let link = PointerStyle(cursor: "pointer")
  public static let grabIdle = PointerStyle(cursor: "grab")
  public static let grabActive = PointerStyle(cursor: "grabbing")
  public static let horizontalText = PointerStyle(cursor: "text")
  public static let verticalText = PointerStyle(cursor: "vertical-text")
  public static let zoomIn = PointerStyle(cursor: "zoom-in")
  public static let zoomOut = PointerStyle(cursor: "zoom-out")
  public static let columnResize = PointerStyle(cursor: "col-resize")
  public static let rowResize = PointerStyle(cursor: "row-resize")
}

nonisolated struct PointerStyleModifier: ViewModifier {
  public let style: PointerStyle?
  public init(style: PointerStyle?) { self.style = style }
  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    if let style { node.styles["cursor"] = style.cursor }
  }
}

public extension View {
  nonisolated func pointerStyle(_ style: PointerStyle?) -> some View {
    modifier(PointerStyleModifier(style: style))
  }
}
