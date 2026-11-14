@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
public extension View {
  /// Calls `action` with `transform(proxy)` when the view first receives a
  /// geometry measurement and then whenever the transformed value changes.
  @preconcurrency nonisolated func onGeometryChange<Value: Equatable & Sendable>(
    for type: Value.Type,
    of transform: @escaping @Sendable (GeometryProxy) -> Value,
    action: @escaping (_ newValue: Value) -> Void
  ) -> some View {
    modifier(GeometryChangeModifier(transform: transform, action: _mainActor(action)))
  }

  /// Two-value form: `action(oldValue, newValue)`. The first call receives
  /// the initial value as both arguments.
  @preconcurrency nonisolated func onGeometryChange<Value: Equatable & Sendable>(
    for type: Value.Type,
    of transform: @escaping @Sendable (GeometryProxy) -> Value,
    action: @escaping (_ oldValue: Value, _ newValue: Value) -> Void
  ) -> some View {
    modifier(GeometryChangeModifier(transform: transform, pairAction: _mainActor(action)))
  }
}

/// Backs `onGeometryChange(for:of:action:)`. The browser host measures every
/// view carrying `data-geometry-change` after commits and on resize (and on
/// ancestor scroll when the transform reads a frame) and sends the frames
/// through the `geometryChange` value event. The transform runs here, at the
/// Core boundary, and the Equatable comparison is retained per Fiber path.
package nonisolated struct GeometryChangeModifier<Value: Equatable>: ViewModifier {
  private let transform: (GeometryProxy) -> Value
  private let pairAction: @MainActor (Value, Value) -> Void

  package init(transform: @escaping (GeometryProxy) -> Value, action: @escaping @MainActor (Value) -> Void) {
    self.transform = transform
    // SAFETY: the callback was handed over from the main actor and only runs there.
    pairAction = { _, new in action(new) }
  }

  init(transform: @escaping (GeometryProxy) -> Value, pairAction: @escaping @MainActor (Value, Value) -> Void) {
    self.transform = transform
    self.pairAction = pairAction
  }

  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let key = context._fiberPath.description + "#geometry-change"
    attach(to: node, key: key, stateStore: context.stateStore)
  }

  @MainActor private func attach(to node: _RenderNode, key: String, stateStore: StateStore) {
    // A fragment has no DOM host; as in SwiftUI the modifier applies to each
    // child view, each with its own change history.
    if case .fragment = node.kind {
      for (index, child) in node.children.enumerated() {
        attach(to: child, key: key + ".\(index)", stateStore: stateStore)
      }
      return
    }
    // Stacked onGeometryChange modifiers share one host measurement; each
    // keeps an independent history and all of them fire.
    let depth = Int(node.attributes["data-geometry-change"] ?? "") ?? 0
    node.attributes["data-geometry-change"] = String(depth + 1)
    let storageKey = depth == 0 ? key : key + ".\(depth)"
    let transform = self.transform
    // Transforms are pure. Probing one against an empty measurement tells
    // the host whether to re-measure this view while an ancestor scrolls.
    let access = _GeometryProxyAccess()
    _ = transform(GeometryProxy(measurement: .zero, access: access))
    if access.readsPosition { node.attributes["data-geometry-change-position"] = "true" }
    let pairAction = self.pairAction
    let previous = node.events["geometryChange"]?.valueAction
    node.events["geometryChange"] = _EventHandler(name: "geometryChange", action: { rawValue in
      previous?(rawValue)
      guard let measurement = _GeometryMeasurement(decoding: rawValue) else { return }
      let value = transform(GeometryProxy(measurement: measurement))
      let result = stateStore.rememberChange(storageKey, value: value)
      guard result.initial || result.changed else { return }
      pairAction(result.previous ?? value, value)
    })
  }
}
