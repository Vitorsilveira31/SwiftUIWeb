@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
/// The state of the pointer relative to a view, as reported to
/// `onContinuousHover(coordinateSpace:perform:)`.
public enum HoverPhase: Equatable, Sendable {
  case active(CGPoint)
  case ended
}

/// Reports every pointer movement over a view. Unlike `onHover`, which the
/// framework can realize entirely in CSS, the pointer position must reach
/// Swift; the browser host coalesces moves to one event per animation frame.
nonisolated struct ContinuousHoverModifier: ViewModifier {
  let action: @MainActor (HoverPhase) -> Void
  init(action: @escaping @MainActor (HoverPhase) -> Void) { self.action = action }

  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let action = self.action
    node.events["continuous-hover-move"] = _EventHandler(name: "continuous-hover-move", action: { (value: String) in
      let parts = value.split(separator: ",")
      guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else { return }
      action(.active(CGPoint(x: x, y: y)))
    })
    node.events["continuous-hover-end"] = _EventHandler(name: "continuous-hover-end", action: { action(.ended) })
  }
}

public extension View {
  nonisolated func onContinuousHover(
    coordinateSpace: some CoordinateSpaceProtocol = .local,
    perform action: @escaping (HoverPhase) -> Void
  ) -> some View {
    _modified(ContinuousHoverModifier(action: _mainActor(action)))
  }
}
