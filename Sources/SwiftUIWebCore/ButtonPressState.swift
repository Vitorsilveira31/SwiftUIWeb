/// Pressed-state plumbing for custom `ButtonStyle`s and the trigger bridge
/// for custom `PrimitiveButtonStyle`s.
///
/// SwiftUI re-evaluates `ButtonStyle.makeBody(configuration:)` with
/// `isPressed == true` while a pointer or the Space/Return key holds the
/// button down. The browser host reports those transitions as the named
/// `pressed` event (`"true"`/`"false"`); Swift keeps the value in a
/// Fiber-scoped state slot so only the owning view re-renders.

private enum ButtonStyleIsPrimitiveEnvironmentKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
  /// True while a custom `PrimitiveButtonStyle` owns button interaction.
  @MainActor package var _buttonStyleIsPrimitive: Bool {
    get { self[ButtonStyleIsPrimitiveEnvironmentKey.self] }
    set { self[ButtonStyleIsPrimitiveEnvironmentKey.self] = newValue }
  }
}

/// Marker attribute emitted by `Button(configuration)` inside a primitive
/// style body. The enclosing native `<button>` adopts its trigger so pointer
/// and keyboard activation both reach `configuration.trigger()`.
let _primitiveTriggerAttribute = "data-primitive-trigger"

/// Renders the label of a button-like control, applying the inherited
/// `ButtonStyle` with a live `isPressed` value and wiring press events.
@MainActor func _renderButtonLabel<Label: View>(
  _ label: Label,
  role: ButtonRole?,
  action: @escaping @MainActor () -> Void,
  node: _RenderNode,
  context: _RenderContext,
  plainKey: _FiberKey? = nil
) -> _RenderNode {
  _renderButtonLabel(
    role: role, action: action, node: node, context: context, plainKey: plainKey,
    renderPlain: { label._render(in: $0) }, erased: { AnyView(label) })
}

/// The non-generic part of `_renderButtonLabel`, so it is not compiled once per label type: `renderPlain` renders the
/// label without a style, `erased` erases it for the style's configuration.
@MainActor private func _renderButtonLabel(
  role: ButtonRole?,
  action: @escaping @MainActor () -> Void,
  node: _RenderNode,
  context: _RenderContext,
  plainKey: _FiberKey?,
  renderPlain: (_RenderContext) -> _RenderNode,
  erased: () -> AnyView
) -> _RenderNode {
  var labelContext = context
  // A shortcut belongs to this control, not to controls inside its label.
  if labelContext.environment._keyboardShortcut != nil { labelContext.environment._keyboardShortcut = nil }
  guard let styleRenderer = context.environment.buttonStyleRenderer else {
    return renderPlain(plainKey.map { labelContext.child($0) } ?? labelContext)
  }
  let isPressed = _buttonPressedState(node: node, context: context)
  let configuration = ButtonStyleConfiguration(
    role: role,
    label: .init(body: erased()),
    isPressed: isPressed,
    action: action
  )
  // `@Environment` reads inside the style (for example `isEnabled`) observe
  // the button's own environment, including a `.disabled` applied to it.
  let previous = EnvironmentRuntime.current
  EnvironmentRuntime.current = labelContext.environment
  defer { EnvironmentRuntime.current = previous }
  let body = styleRenderer.render(configuration)
  let child = body._render(in: labelContext.child(_FiberKey("styled-label")))
  if context.environment._buttonStyleIsPrimitive {
    // The primitive style decides when the action runs (`trigger()`), so the
    // native button must not also run it on click.
    node.events.removeValue(forKey: "click")
    if context.environment.isEnabled, let trigger = _takePrimitiveTrigger(in: child) {
      node.events["click"] = trigger
    }
  }
  return child
}

/// Reads (and registers a dependency on) the Fiber-scoped pressed state and
/// attaches the browser `pressed` event when the button is enabled.
@MainActor private func _buttonPressedState(node: _RenderNode, context: _RenderContext) -> Bool {
  // `ButtonStyle` receives `isPressed`; primitive styles have no such value.
  guard !context.environment._buttonStyleIsPrimitive else { return false }
  let key = context._fiberPath.description + "#button-pressed"
  let box = context.stateStore.box(key, default: false)
  box.onRead?()
  guard context.environment.isEnabled else {
    if box.value { box.value = false }
    return false
  }
  node.attributes["data-press-tracking"] = "true"
  node.events["pressed"] = _EventHandler(name: "pressed", action: { raw in
    let next = raw == "true"
    if box.value != next { box.value = next }
  })
  return box.value
}

@MainActor private func _takePrimitiveTrigger(in node: _RenderNode) -> _EventHandler? {
  if node.attributes[_primitiveTriggerAttribute] != nil, let trigger = node.events["click"] {
    node.events.removeValue(forKey: "click")
    return trigger
  }
  for child in node.children {
    if let trigger = _takePrimitiveTrigger(in: child) { return trigger }
  }
  return nil
}

public extension Button where Label == PrimitiveButtonStyleConfiguration.Label {
  /// Creates a button from a primitive style configuration, as SwiftUI does
  /// inside `PrimitiveButtonStyle.makeBody(configuration:)`.
  nonisolated init(_ configuration: PrimitiveButtonStyleConfiguration) {
    // SAFETY: the configuration is only used by the main-actor trigger it was built for.
    nonisolated(unsafe) let configuration = configuration
    self.init(role: configuration.role, action: { configuration.trigger() }) { configuration.label }
    _isPrimitiveConfiguration = true
  }
}

/// `Button(configuration)` renders as the label of the enclosing native
/// button instead of a nested `<button>`, which HTML forbids.
@MainActor func _renderPrimitiveConfigurationButton<Label: View>(
  label: Label,
  action: @escaping @MainActor () -> Void,
  context: _RenderContext
) -> _RenderNode {
  let node = _RenderNode.element("span")
  node.classes = ["primitive-button-label"]
  node.attributes[_primitiveTriggerAttribute] = "true"
  if context.environment.isEnabled { node.events["click"] = _EventHandler(name: "click", action: action) }
  let child = label._render(in: context.child(_FiberKey("label")))
  node.children = child.isEmpty ? [] : [child]
  return node
}
