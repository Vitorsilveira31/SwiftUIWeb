/// SwiftUI's `Text`-titled and data-presenting alert/confirmation-dialog
/// overloads. A `presenting` dialog is shown only while `isPresented` is true
/// and `data` is non-nil; the actions and message receive the unwrapped data.
public typealias _PresentingContent<Content: View> = _ConditionalContent<Content, EmptyView>

package func _presenting<T, Content: View>(_ data: T?, _ content: @escaping (T) -> Content) -> () -> _PresentingContent<Content> {
  { data.map { .trueContent(content($0)) } ?? .falseContent(EmptyView()) }
}

package func _presentingBinding<T>(_ isPresented: Binding<Bool>, _ data: T?) -> Binding<Bool> {
  let available = data != nil
  return Binding(get: { available && isPresented.wrappedValue }, set: { isPresented.wrappedValue = $0 })
}

public extension View {
  // MARK: Alert

  nonisolated func alert<Actions: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, @ViewBuilder actions: @escaping () -> Actions) -> some View {
    modifier(AlertModifier(title: titleKey.resolved, isPresented: isPresented, message: { EmptyView() }, actions: actions))
  }
  nonisolated func alert<Actions: View, Message: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, @ViewBuilder actions: @escaping () -> Actions, @ViewBuilder message: @escaping () -> Message) -> some View {
    modifier(AlertModifier(title: titleKey.resolved, isPresented: isPresented, message: message, actions: actions))
  }
  nonisolated func alert<Actions: View, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: @escaping (T) -> Actions) -> some View {
    modifier(AlertModifier(title: titleKey.resolved, isPresented: _presentingBinding(isPresented, data), message: { EmptyView() }, actions: _presenting(data, actions)))
  }
  nonisolated func alert<Actions: View, Message: View, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: @escaping (T) -> Actions, @ViewBuilder message: @escaping (T) -> Message) -> some View {
    modifier(AlertModifier(title: titleKey.resolved, isPresented: _presentingBinding(isPresented, data), message: _presenting(data, message), actions: _presenting(data, actions)))
  }

  @_disfavoredOverload nonisolated func alert<S: StringProtocol, Actions: View>(_ title: S, isPresented: Binding<Bool>, @ViewBuilder actions: @escaping () -> Actions) -> some View {
    modifier(AlertModifier(title: String(title), isPresented: isPresented, message: { EmptyView() }, actions: actions))
  }
  @_disfavoredOverload nonisolated func alert<S: StringProtocol, Actions: View, Message: View>(_ title: S, isPresented: Binding<Bool>, @ViewBuilder actions: @escaping () -> Actions, @ViewBuilder message: @escaping () -> Message) -> some View {
    modifier(AlertModifier(title: String(title), isPresented: isPresented, message: message, actions: actions))
  }
  @_disfavoredOverload nonisolated func alert<S: StringProtocol, Actions: View, T>(_ title: S, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: @escaping (T) -> Actions) -> some View {
    modifier(AlertModifier(title: String(title), isPresented: _presentingBinding(isPresented, data), message: { EmptyView() }, actions: _presenting(data, actions)))
  }
  @_disfavoredOverload nonisolated func alert<S: StringProtocol, Actions: View, Message: View, T>(_ title: S, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: @escaping (T) -> Actions, @ViewBuilder message: @escaping (T) -> Message) -> some View {
    modifier(AlertModifier(title: String(title), isPresented: _presentingBinding(isPresented, data), message: _presenting(data, message), actions: _presenting(data, actions)))
  }

  nonisolated func alert<Actions: View>(_ title: Text, isPresented: Binding<Bool>, @ViewBuilder actions: @escaping () -> Actions) -> some View {
    modifier(AlertModifier(title: title.value, isPresented: isPresented, message: { EmptyView() }, actions: actions))
  }
  nonisolated func alert<Actions: View, Message: View>(_ title: Text, isPresented: Binding<Bool>, @ViewBuilder actions: @escaping () -> Actions, @ViewBuilder message: @escaping () -> Message) -> some View {
    modifier(AlertModifier(title: title.value, isPresented: isPresented, message: message, actions: actions))
  }
  nonisolated func alert<Actions: View, T>(_ title: Text, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: @escaping (T) -> Actions) -> some View {
    modifier(AlertModifier(title: title.value, isPresented: _presentingBinding(isPresented, data), message: { EmptyView() }, actions: _presenting(data, actions)))
  }
  nonisolated func alert<Actions: View, Message: View, T>(_ title: Text, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: @escaping (T) -> Actions, @ViewBuilder message: @escaping (T) -> Message) -> some View {
    modifier(AlertModifier(title: title.value, isPresented: _presentingBinding(isPresented, data), message: _presenting(data, message), actions: _presenting(data, actions)))
  }

  // MARK: Confirmation dialog

}

/// Tracks a presentation's identity across renders and runs `onDismiss`
/// once when a presented value goes away (binding reset, `dismiss()`,
/// Escape, backdrop) or is replaced by a different item.
///
/// The returned closure is called by the presentation's own dismiss paths
/// right after they reset the binding, so `onDismiss` runs synchronously for
/// them and is not repeated by the next render. Programmatic binding changes
/// are detected on the next render.
///
/// The key is the Fiber path plus the number of presentation hosts already
/// wrapped around `host`, so chained presentation modifiers on one view keep
/// independent slots whether or not they are currently presented.
@MainActor func _trackPresentation<ID: Equatable>(_ identity: ID?, host: _RenderNode, context: _RenderContext, onDismiss: (@MainActor () -> Void)?) -> @MainActor () -> Void {
  guard let onDismiss else { return {} }
  var depth = 0
  var current: _RenderNode? = host
  while let node = current, node.classes.contains("presentation-host") {
    depth += 1
    current = node.children.first
  }
  let key = context._fiberPath.description + "#presentation-dismiss-\(depth)"
  let store = context.stateStore
  let change = store.rememberChange(key, value: identity)
  if !change.initial, change.changed, let previous = change.previous, previous != nil {
    // The application sees its dismissal callbacks in render order (see `_RenderStaging.ordered`).
    _RenderStaging.ordered { _ in onDismiss() }
  }
  return {
    let dismissed = store.rememberChange(key, value: Optional<ID>.none)
    if dismissed.changed { onDismiss() }
  }
}
