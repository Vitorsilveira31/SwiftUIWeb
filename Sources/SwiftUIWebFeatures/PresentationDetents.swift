@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
/// `presentationDetents(_:)` / `presentationDetents(_:selection:)`.
///
/// A compact-width (bottom) sheet is sized to the selected detent; the
/// regular-width edge panel ignores detents like a regular-width iPad sheet.
/// `.medium` is half the
/// viewport, `.large` the viewport minus a 24pt top gap, `.fraction(f)` that
/// fraction of the viewport and `.height(h)` exactly `h` points (all capped
/// at `.large`). Without a selection binding the sheet starts at its
/// smallest detent, as SwiftUI does, and keeps the user's choice in
/// Fiber-scoped state. Dragging the sheet's grabber in the browser snaps to
/// the nearest detent and reports it through the `presentation-detent`
/// value event; clicking the grabber moves to the next larger detent.
package nonisolated struct PresentationDetentsModifier: ViewModifier {
  package let detents: Set<PresentationDetent>
  package let selection: Binding<PresentationDetent>?

  package init(detents: Set<PresentationDetent>, selection: Binding<PresentationDetent>?) {
    self.detents = detents
    self.selection = selection
  }

  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let ordered = detents.sorted { $0._nominalHeight < $1._nominalHeight }
    guard let smallest = ordered.first else { return }
    let current: PresentationDetent
    let select: (PresentationDetent) -> Void
    if let selection {
      current = detents.contains(selection.wrappedValue) ? selection.wrappedValue : smallest
      select = { value in if selection.wrappedValue != value { selection.wrappedValue = value } }
    } else {
      let key = context._fiberPath.description + "#presentation-detent"
      let box = context.stateStore.box(key, default: smallest._swiftUIWebIdentifier)
      box.onRead?()
      current = PresentationDetent(_swiftUIWebIdentifier: box.value).flatMap { detents.contains($0) ? $0 : nil } ?? smallest
      select = { value in if box.value != value._swiftUIWebIdentifier { box.value = value._swiftUIWebIdentifier } }
    }
    let detents = self.detents
    node.attributes["data-presentation-detents"] = detents.map { $0._swiftUIWebIdentifier }.sorted().joined(separator: ",")
    node.attributes["data-presentation-detent-selection"] = current._swiftUIWebIdentifier
    node.attributes["data-presentation-detent-height"] = current._cssHeight
    node.attributes["data-presentation-detent-heights"] = ordered.map { $0._swiftUIWebIdentifier + "=" + $0._cssHeight }.joined(separator: ";")
    node.events["presentation-detent"] = _EventHandler(name: "presentation-detent", action: { raw in
      guard let value = PresentationDetent(_swiftUIWebIdentifier: raw), detents.contains(value) else { return }
      select(value)
    })
  }
}

public extension View {
  nonisolated func presentationDetents(_ detents: Set<PresentationDetent>) -> some View {
    _modified(PresentationDetentsModifier(detents: detents, selection: nil))
  }
  nonisolated func presentationDetents(
    _ detents: Set<PresentationDetent>,
    selection: Binding<PresentationDetent>
  ) -> some View {
    _modified(PresentationDetentsModifier(detents: detents, selection: selection))
  }
}

extension PresentationDetent {
  /// CSS length of the sheet at this detent.
  var _cssHeight: String {
    switch kind {
    case .medium: return "50dvh"
    case .large: return "calc(100dvh - 24px)"
    // A NaN or infinite fraction or height is not a size: it takes the default detent, `.large`.
    case .fraction(let value): return value.isFinite ? "calc(100dvh * " + String(max(0, min(1, value))) + ")" : "calc(100dvh - 24px)"
    case .height(let value): return value.isFinite ? String(max(0, value)) + "px" : "calc(100dvh - 24px)"
    }
  }

  /// Ordering key on a nominal 800pt viewport, used to pick the smallest.
  var _nominalHeight: Double {
    switch kind {
    case .medium: return 400
    case .large: return 776
    case .fraction(let value): return value.isFinite ? 800 * value : 776
    case .height(let value): return value.isFinite ? value : 776
    }
  }
}
