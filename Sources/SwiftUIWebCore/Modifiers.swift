@_spi(Renderer) import SwiftUIWebTransferable

@MainActor @preconcurrency
public protocol ViewModifier {
  associatedtype Body: View = AnyView
  typealias Content = _ViewModifier_Content<Self>
  @ViewBuilder func body(content: Self.Content) -> Body
  func _apply(to node: _RenderNode, context: inout _RenderContext)
  func _modifyContext(_ context: inout _RenderContext)
  /// The modifier as it renders now (its animatable data where an animation has it), and whether it is moving.
  func _swiftUIWebPresented(in context: _RenderContext) -> (modifier: Self, moving: Bool)
  /// How the modifier renders its content (`body(content:)`, or the content itself for a geometry effect).
  func _swiftUIWebRenderBody(content: Self.Content, in context: _RenderContext) -> _RenderNode
}

/// The modified view that a modifier's `body(content:)` receives (SwiftUI's `_ViewModifier_Content<Self>`).
/// It wraps the erased content, so it renders exactly as that content does.
public nonisolated struct _ViewModifier_Content<Modifier>: View where Modifier: ViewModifier {
  public typealias Body = Never
  fileprivate let view: AnyView

  package init(_ view: AnyView) { self.view = view }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    view._render(in: context)
  }
}

// Apple's ViewModifier has no default body. The framework's built-in modifiers draw through `_apply` and keep the
// `AnyView` body they always had (the default `Body`), so the identity default applies to that case only.
// The identity hands back the erased content itself. Wrapping `_ViewModifier_Content` in another `AnyView` added
// a renderer and two `AnyView._render` frames to every modifier level, which the WebKit Worker's small wasm stack
// paid for.
public extension ViewModifier where Body == AnyView {
  @ViewBuilder @MainActor @preconcurrency func body(content: Self.Content) -> Self.Body { content.view }
}

public extension ViewModifier {
  func _apply(to node: _RenderNode, context: inout _RenderContext) {}
  func _modifyContext(_ context: inout _RenderContext) {}
}

/// Modifier chains nest by type: `ModifiedContent<ModifiedContent<…>, M>`.
/// Holding the inner view by value made every level's copy, destroy and
/// closure-context witnesses copy the whole chain beneath it, so a chain of
/// depth N compiled to O(N²) outlined-copy code (about 1.5 MB in a 300-view
/// application). A box keeps each level's copy at one pointer retain.
public struct ModifiedContent<Content: View, Modifier: ViewModifier> {
  public typealias Body = Never
  // Written once in the initializer and only read on the main actor. The initializer is nonisolated, as in
  // SwiftUI, so a nonisolated API (`glassEffect`) can wrap a non-Sendable view without sending `self`.
  private nonisolated(unsafe) let storage: _ViewBox<Content>
  public var content: Content { storage.value }
  public var modifier: Modifier
  public nonisolated init(content: Content, modifier: Modifier) { storage = _ViewBox(content); self.modifier = modifier }
  @inline(__always) @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    // The modifier's `_apply` post-processes the rendered node, so the retained
    // owner must cover it: re-rendering only the inner content (a targeted
    // state update below this modifier) would otherwise return the node
    // without the modifier's effect (padding, presentation host, ...).
    // The boundary holds the modifier and the erased content, so it is generic over the modifier alone. Erasing is a
    // pure wrap of the immutable content, so erasing it once here is the same as erasing it on every boundary render.
    AnyView(_ownerBoundaryOf: _ModifierBoundary(modifier: modifier, content: AnyView._unowned(content)))._render(in: context)
  }
}
extension ModifiedContent: View {}

/// The owner boundary of a `ModifiedContent`: its modifier and its erased content. Generic over the modifier alone, so a
/// debug build compiles the render once per modifier type rather than once per modified view type.
private struct _ModifierBoundary<Modifier: ViewModifier>: _OwnerBoundaryContent {
  let modifier: Modifier
  let content: AnyView
  @inline(__always) @MainActor func _renderOwnerBoundary(in context: _RenderContext) -> _RenderNode {
    var next = context
    // An animatable modifier renders with the data its animation has reached (`Animator.swift`).
    let (modifier, moving) = self.modifier._swiftUIWebPresented(in: context)
    next._modifierDepth += 1
    let lazyApply = _modifyContextTracking(modifier, &next)
    let previous = _installModifierEnvironment(next)
    defer { _restoreModifierEnvironment(previous) }
    // Render through the SwiftUI-shaped modifier body first. Built-in
    // SwiftUIWeb modifiers inherit the identity default and apply their
    // compact metadata in `_apply`; application-defined modifiers can now
    // transform `Content` just like they do in SwiftUI.
    let rendered = modifier._swiftUIWebRenderBody(content: _ViewModifier_Content<Modifier>(content), in: next)
    // Deep in the render the content may be a node that stands in for a render that has not run (see
    // `_PendingRender`). A modifier waits for it, with the state its handlers capture.
    if lazyApply, let pending = _pendingTarget(rendered) {
      // The marking waits with the application: writing a timeline to the pending node would render it now, and the
      // operations kept for it (the modifier target, the modifier's `_apply`) would be dropped.
      return _postApply(modifier, to: pending, context: next, markKey: moving ? context._modifierStateKey("#modifier") : nil)
    }
    let node = _modifierTarget(rendered)
    modifier._apply(to: node, context: &next)
    if moving { _Animator.mark(node, key: context._modifierStateKey("#modifier"), moving: true) }
    return node
  }
}

/// Runs `modifier._modifyContext` and reports whether the modifier's `_apply` can run after the rest of the pass: it
/// can whenever the render stages at all (every `_apply` writes to the node it modifies, and what the application
/// observes in render order is ordered by position, see `_RenderStaging`). Out of line so the generic frame of
/// `ModifiedContent` stays small.
@inline(never)
@MainActor private func _modifyContextTracking<Modifier: ViewModifier>(_ modifier: Modifier, _ context: inout _RenderContext) -> Bool {
  modifier._modifyContext(&context)
  return _RenderStaging.budget > 0
}

/// Keeps `modifier`'s `_apply` for the pending `node`, to run when its render has (see `_PendingRender`).
@inline(never)
@MainActor private func _postApply<Modifier: ViewModifier>(_ modifier: Modifier, to node: _RenderNode, context: _RenderContext, markKey: String?) -> _RenderNode {
  node._keep(.modifierTarget)
  node._keep(.apply(_CapturedThreadState.capture()) { target in
    var applied = context
    modifier._apply(to: target, context: &applied)
    if let markKey { _Animator.mark(target, key: markKey, moving: true) }
  })
  return node
}

/// Installs `context`'s environment for a modifier's body and returns the one it replaces.
/// Non-generic so `ModifiedContent` specializations do not each carry the environment copies.
@inline(never)
@MainActor private func _installModifierEnvironment(_ context: _RenderContext) -> EnvironmentValues? {
  let previous = EnvironmentRuntime.installed
  EnvironmentRuntime.current = context.environment
  return previous
}

@inline(never)
private func _restoreModifierEnvironment(_ previous: EnvironmentValues?) {
  EnvironmentRuntime.installed = previous
}

// A modifier on a `Group` with one child is a modifier on that child. Applying it to the fragment's child
// in place would put the modifier layers (a frame wrapper, padding) on a node the enclosing owner never
// returned: a later targeted re-render of an inner owner would hand the retained wrapper a bare node and
// replace its whole subtree, restarting every task and state below it. Returning the child itself keeps
// the owner chain intact (see `_recordOuterOwner`).
@inline(never)
func _modifierTarget(_ node: _RenderNode) -> _RenderNode {
  if node.kind == .fragment, node.children.count == 1, node.key == nil { return node.children[0] }
  return node
}

// SwiftUI declares view callbacks as plain `() -> Void`, so a closure written in a view is isolated to the
// main actor by inference and a stored `@MainActor () -> Void` still converts to it. The framework keeps
// its storage `@MainActor`: these wrappers re-isolate a callback received by a nonisolated entry point
// (Apple's modifiers are nonisolated). That is sound because the callback was handed over from (and only
// ever runs on) the main actor; the wrapper is the only holder of it.
@inline(__always)
package func _mainActor(_ action: @escaping () -> Void) -> @MainActor () -> Void {
  nonisolated(unsafe) let action = action
  return { action() }
}
@inline(__always)
package func _mainActor<A>(_ action: @escaping (A) -> Void) -> @MainActor (A) -> Void {
  nonisolated(unsafe) let action = action
  return { action($0) }
}
@inline(__always)
package func _mainActor<A, B>(_ action: @escaping (A, B) -> Void) -> @MainActor (A, B) -> Void {
  nonisolated(unsafe) let action = action
  return { action($0, $1) }
}
/// As `_mainActor` for a callback that returns a value (`onDrop`'s `perform`, `onDrag`'s provider).
@inline(__always)
package func _mainActorReturning<R>(_ action: @escaping () -> R) -> @MainActor () -> R {
  nonisolated(unsafe) let action = action
  return { action() }
}
@inline(__always)
package func _mainActorReturning<A, R>(_ action: @escaping (A) -> R) -> @MainActor (A) -> R {
  nonisolated(unsafe) let action = action
  return { action($0) }
}
@inline(__always)
package func _mainActorReturning<A, B, R>(_ action: @escaping (A, B) -> R) -> @MainActor (A, B) -> R {
  nonisolated(unsafe) let action = action
  return { action($0, $1) }
}
@inline(__always)
package func _mainActor<A, B, C>(_ action: @escaping (A, B, C) -> Void) -> @MainActor (A, B, C) -> Void {
  nonisolated(unsafe) let action = action
  return { action($0, $1, $2) }
}
@inline(__always)
package func _mainActor(_ action: (() -> Void)?) -> (@MainActor () -> Void)? {
  guard let action else { return nil }
  nonisolated(unsafe) let held = action
  return { held() }
}
@inline(__always)
package func _mainActor<A>(_ action: ((A) -> Void)?) -> (@MainActor (A) -> Void)? {
  guard let action else { return nil }
  nonisolated(unsafe) let held = action
  return { held($0) }
}

public extension View {
  nonisolated func modifier<M: ViewModifier>(_ modifier: M) -> ModifiedContent<Self, M> { ModifiedContent(content: self, modifier: modifier) }
  nonisolated func id<ID: Hashable>(_ id: ID) -> some View { modifier(IDModifier(id: _FiberKey(id))) }
  /// `.id(account?.id)`: an optional identity. Written out so the optional is not cast as an unknown generic value.
  nonisolated func id<ID: Hashable>(_ id: ID?) -> some View { modifier(IDModifier(id: _FiberKey(id))) }
  nonisolated func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View {
    modifier(_onTapGestureModifier(count: count, perform: _mainActor(action)))
  }
  package nonisolated func onFocus(_ action: @escaping @MainActor () -> Void) -> some View {
    modifier(_onFocusModifier(action))
  }
  package nonisolated func onBlur(_ action: @escaping @MainActor () -> Void) -> some View {
    modifier(_onBlurModifier(action))
  }
  package nonisolated func focused<Value: Hashable>(_ binding: Binding<Value>, equals value: Value) -> some View { modifier(FocusedModifier(binding: binding, value: value, clear: nil)) }
  nonisolated func focused<Value: Hashable>(_ binding: FocusState<Value>.Binding, equals value: Value) -> some View { focused(binding.binding, equals: value) }
  nonisolated func focused(_ binding: FocusState<Bool>.Binding) -> some View { focused(binding.binding) }
  package nonisolated func focused(_ binding: Binding<Bool>) -> some View { modifier(FocusedModifier(binding: binding, value: true, clear: { binding.wrappedValue = false })) }
  nonisolated func onHover(perform action: @escaping (Bool) -> Void) -> some View {
    modifier(_onHoverModifier(perform: _mainActor(action)))
  }
  nonisolated func hoverEffect(_ effect: some CustomHoverEffect = .automatic, isEnabled: Bool = true) -> some View {
    modifier(HoverEffectModifier(effect: effect, isEnabled: isEnabled))
  }
  @_spi(Renderer) nonisolated func hoverEffect(
    _ effect: some CustomHoverEffect,
    in group: HoverEffectGroup?,
    isEnabled: Bool = true
  ) -> some View {
    modifier(HoverEffectModifier(effect: effect, group: group, isEnabled: isEnabled))
  }
  @_spi(Renderer) nonisolated func hoverEffect<Content: HoverEffectContent>(
    in group: HoverEffectGroup? = nil,
    isEnabled: Bool = true,
    body: @escaping (EmptyHoverEffectContent, Bool, GeometryProxy) -> Content
  ) -> some View {
    let effect = ContentHoverEffect(group: group, isEnabled: isEnabled, body: body)
    return modifier(HoverEffectModifier(effect: effect, group: group, isEnabled: isEnabled))
  }
  nonisolated func defaultHoverEffect(_ effect: HoverEffect?) -> some View {
    modifier(_defaultHoverEffectModifier(effect ?? HoverEffect(EmptyHoverEffect())))
  }
  nonisolated func defaultHoverEffect(_ effect: some CustomHoverEffect) -> some View {
    modifier(_defaultHoverEffectModifier(HoverEffect(effect)))
  }
  nonisolated func hoverEffectDisabled(_ disabled: Bool = true) -> some View {
    modifier(_hoverEffectDisabledModifier(disabled))
  }
  package nonisolated func hoverEffectGroup() -> some View {
    modifier(_hoverEffectGroupModifier())
  }
  package nonisolated func hoverEffectGroup(_ group: HoverEffectGroup?) -> some View {
    modifier(_hoverEffectGroupModifier(group))
  }
  package nonisolated func hoverEffectGroup(
    id: String? = nil,
    in namespace: Namespace.ID,
    behavior: HoverEffectGroup.Behavior = .activatesGroup
  ) -> some View {
    modifier(_hoverEffectGroupModifier(id: id, in: namespace, behavior: behavior))
  }
  package nonisolated func listRowHoverEffect(_ effect: HoverEffect?) -> some View {
    modifier(_listRowHoverEffectModifier(effect))
  }
  package nonisolated func listRowHoverEffectDisabled(_ disabled: Bool = true) -> some View {
    modifier(_listRowHoverEffectDisabledModifier(disabled))
  }
  nonisolated func onAppear(perform action: (() -> Void)? = nil) -> some View {
    modifier(_onAppearModifier(perform: _mainActor(action ?? {})))
  }
  nonisolated func onDisappear(perform action: (() -> Void)? = nil) -> some View {
    modifier(_onDisappearModifier(perform: _mainActor(action ?? {})))
  }
  nonisolated func foregroundColor(_ color: Color) -> some View {
    modifier(_foregroundColorModifier(color))
  }
  /// SwiftUI's `background(_:ignoresSafeAreaEdges:)`. The paint fills the
  /// view's bounds; the browser surface has no device safe area to extend into.
  nonisolated func background<S: ShapeStyle>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View { modifier(ShapeStyleBackgroundModifier(style: style)) }
  // The frame, padding and fixedSize modifiers build their style tables in
  // the non-generic `_*Modifier` functions below. Building them inside these
  // generic methods specialized the whole table construction (string
  // formatting, dictionary inserts) once per view type they were applied to,
  // about 5 KB each.
  nonisolated func padding(_ value: Double = 8) -> some View {
    modifier(_paddingModifier(value))
  }
  nonisolated func frame(width: Double? = nil, height: Double? = nil, alignment: Alignment = .center) -> some View {
    modifier(_frameModifier(width: width, height: height, alignment: alignment))
  }
  nonisolated func offset(x: Double = 0, y: Double = 0) -> some View {
    modifier(_offsetModifier(x: x, y: y))
  }
  nonisolated func opacity(_ value: Double) -> some View {
    modifier(_opacityModifier(value))
  }
  @_disfavoredOverload nonisolated func accessibilityLabel<S: StringProtocol>(_ label: S) -> some View {
    modifier(_accessibilityLabelModifier(String(label)))
  }
  nonisolated func accessibilityLabel(_ label: Text) -> some View { accessibilityLabel(label.value) }
  nonisolated func accessibilityIdentifier(_ identifier: String) -> some View {
    modifier(_accessibilityIdentifierModifier(identifier))
  }
  /// Sets a value for a plain `EnvironmentKey` type.  SwiftUI only spells
  /// environment injection with a key path, so this stays underscored and
  /// out of the SwiftUI-shaped surface.
  nonisolated func _environment<K: EnvironmentKey>(_ key: K.Type, _ value: K.Value) -> some View { modifier(EnvironmentOverride(apply: { $0[key] = value })) }
  nonisolated func environment<Value>(_ keyPath: WritableKeyPath<EnvironmentValues, Value>, _ value: Value) -> some View {
    modifier(EnvironmentOverride(apply: { $0[keyPath: keyPath] = value }, colorScheme: _environmentColorScheme(keyPath, value)))
  }
  /// SwiftUI's Observation-era environment injection.  This overload keeps
  /// model-based environment values distinct from key-path values and makes
  /// `@Environment(Model.self)` work without an app-specific router or
  /// object wrapper.
  nonisolated func environment<ObjectType: AnyObject>(_ object: ObjectType) -> some View {
    modifier(EnvironmentOverride(apply: { $0._setEnvironmentObject(object) }))
  }
  nonisolated func environmentObject<ObjectType: AnyObject>(_ object: ObjectType) -> some View { modifier(EnvironmentOverride(apply: { $0[EnvironmentObjectKey<ObjectType>.self] = object })) }
  /// Publishes a value from this subtree to an ancestor preference reader.
  nonisolated func preference<Key: PreferenceKey>(key: Key.Type = Key.self, value: Key.Value) -> some View {
    modifier(PreferenceWritingModifier<Key>(value: value))
  }
  /// Observes a reduced preference value after the modified subtree renders.
  /// The callback is invoked only when the reduced value changes, matching
  /// SwiftUI's invalidation semantics.
  nonisolated func onPreferenceChange<Key: PreferenceKey>(_ key: Key.Type = Key.self, perform action: @escaping (Key.Value) -> Void) -> some View where Key.Value: Equatable {
    modifier(PreferenceActionModifier<Key>(action: _mainActor(action)))
  }
  nonisolated func foregroundStyle<S: ShapeStyle>(_ style: S) -> some View { modifier(ShapeStyleForegroundModifier(style: style)) }
  nonisolated func font(_ font: Font) -> some View {
    modifier(_fontModifier(font))
  }
  nonisolated func bold() -> some View {
    modifier(_boldModifier())
  }
  nonisolated func italic() -> some View {
    modifier(_italicModifier())
  }
  nonisolated func disabled(_ disabled: Bool) -> some View {
    modifier(_disabledModifier(disabled))
  }
  nonisolated func hidden() -> some View {
    modifier(_hiddenModifier())
  }
  nonisolated func clipped() -> some View {
    modifier(_clippedModifier())
  }
  nonisolated func cornerRadius(_ radius: Double) -> some View {
    modifier(_cornerRadiusModifier(radius))
  }
  // The builder is not escaping, as in SwiftUI: a view may pass its own non-escaping content parameter straight in.
  nonisolated func background<Background: View>(alignment: Alignment = .center, @ViewBuilder content: () -> Background) -> some View {
    let background = content()
    return modifier(BackgroundModifier(content: { background }, alignment: alignment))
  }
  nonisolated func background<S: ShapeStyle, Clip: Shape>(_ style: S, in clip: Clip, fillStyle: FillStyle = FillStyle()) -> some View {
    modifier(ShapeBackgroundModifier(style: style, clip: clip))
  }
  nonisolated func clipShape<Clip: Shape>(_ clip: Clip, style: FillStyle = FillStyle()) -> some View {
    modifier(ClipShapeModifier(clip: clip, style: style))
  }
  nonisolated func overlay<Overlay: View>(alignment: Alignment = .center, @ViewBuilder content: () -> Overlay) -> some View {
    let overlay = content()
    return modifier(OverlayModifier(content: { overlay }, alignment: alignment))
  }
  /// Restricts the hit region of a view to a shape.  SwiftUIWeb keeps the
  /// SwiftUI spelling while expressing the geometry as CSS metadata that a
  /// browser host can apply consistently to both pointer events and focusable
  /// controls.  Unknown/custom shapes still receive a stable semantic marker
  /// instead of silently disappearing from the render tree.
  nonisolated func contentShape<S: Shape>(_ shape: S, eoFill: Bool = false) -> some View {
    modifier(ContentShapeModifier(shape: shape, eoFill: eoFill))
  }

  nonisolated func frame(maxWidth: Double? = nil, maxHeight: Double? = nil, alignment: Alignment = .center) -> some View {
    modifier(_frameModifier(maxWidth: maxWidth, maxHeight: maxHeight, alignment: alignment))
  }
  nonisolated func frame(minWidth: Double? = nil, idealWidth: Double? = nil, maxWidth: Double? = nil, minHeight: Double? = nil, idealHeight: Double? = nil, maxHeight: Double? = nil, alignment: Alignment = .center) -> some View {
    modifier(_frameModifier(minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth, minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight, alignment: alignment))
  }
  nonisolated func padding(_ edges: Edge.Set, _ length: Double? = nil) -> some View {
    modifier(_paddingModifier(edges, length))
  }
  nonisolated func multilineTextAlignment(_ alignment: TextAlignment) -> some View {
    modifier(_multilineTextAlignmentModifier(alignment))
  }
  nonisolated func fixedSize(horizontal: Bool, vertical: Bool) -> some View {
    modifier(_fixedSizeModifier(horizontal: horizontal, vertical: vertical))
  }
  nonisolated func fixedSize() -> some View {
    fixedSize(horizontal: true, vertical: true)
  }
  /// Sets the SwiftUI layout priority consumed by a parent `Layout`. The
  /// value is semantic metadata; the reusable layout engine decides how extra
  /// space is allocated rather than delegating that decision to CSS flexbox.
  nonisolated func layoutPriority(_ value: Double) -> some View {
    modifier(_layoutPriorityModifier(value))
  }
  nonisolated func onChange<Value: Equatable>(of value: Value, perform action: @escaping (Value) -> Void) -> some View { modifier(OnChangeModifier(value: value, action: _mainActor(action))) }
  // Apple's public `task` overloads take a `sending @isolated(any)` action and
  // the call-site `name`/`file`/`line`. The task runs on the main actor in
  // this runtime; `name` and the call site are accepted for source
  // compatibility and are not exposed to the browser host.
  nonisolated func task(
    name: String? = nil,
    priority: TaskPriority = .userInitiated,
    file: String = #fileID,
    line: Int = #line,
    @_inheritActorContext _ action: sending @escaping @isolated(any) () async -> Void
  ) -> some View {
    modifier(_taskModifier(priority: priority, _mainActorTask(action)))
  }
  // The ID participates in SwiftUI task cancellation/restart. The restart
  // decision is value-based (`StateStore` generation of the Equatable ID); the
  // description is only a diagnostic prefix, so opaque values in Embedded are
  // fine.
  nonisolated func task<ID: Equatable>(
    id: ID,
    name: String? = nil,
    priority: TaskPriority = .userInitiated,
    file: String = #fileID,
    line: Int = #line,
    @_inheritActorContext _ action: sending @escaping @isolated(any) () async -> Void
  ) -> some View {
    modifier(TaskModifier(priority: priority, action: _mainActorTask(action), value: id, description: _swiftUIWebDescribe(id)))
  }
  nonisolated func animation<Value: Equatable>(_ animation: Animation?, value: Value) -> some View {
    modifier(AnimationModifier(animation: animation, value: value))
  }
  nonisolated func tabItem<Label: View>(@ViewBuilder _ label: @escaping () -> Label) -> some View {
    modifier(TabItemModifier(label: label))
  }
  nonisolated func tag<TagValue: Hashable>(_ value: TagValue) -> some View {
    modifier(TagModifier(value: value))
  }
  nonisolated func badge(_ value: Int) -> some View {
    modifier(_badgeModifier(value))
  }
  /// SwiftUI's label badge: `nil` removes the badge.
  nonisolated func badge(_ label: Text?) -> some View {
    modifier(_badgeModifier(label))
  }
  nonisolated func badge(_ key: LocalizedStringKey?) -> some View {
    modifier(_badgeModifier(key.map { $0.resolved }))
  }
  @_disfavoredOverload nonisolated func badge<S: StringProtocol>(_ label: S?) -> some View {
    modifier(_badgeModifier(label.map { String($0) }))
  }
  package nonisolated func customizationID(_ identifier: String) -> some View {
    modifier(_customizationIDModifier(identifier))
  }
  nonisolated func tabViewCustomization(_ customization: Binding<TabViewCustomization>?) -> some View {
    modifier(_tabViewCustomizationModifier(customization))
  }
  nonisolated func tabViewStyle<S: TabViewStyle>(_ style: S) -> some View {
    modifier(TabViewStyleModifier(style: style))
  }
  /// SwiftUIWeb extension: bounds how many visited tabs a `TabView` keeps built.
  package nonisolated func tabViewMountPolicy(_ policy: TabViewMountPolicy) -> some View {
    modifier(_tabViewMountPolicyModifier(policy))
  }

  /// `onDismiss` runs once after the sheet is dismissed by any means: the
  /// binding becoming false, `dismiss()`, Escape or a backdrop click.
  nonisolated func sheet<Sheet: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Sheet) -> some View { modifier(SheetModifier(isPresented: isPresented, onDismiss: _mainActor(onDismiss), content: content)) }
  nonisolated func fullScreenCover<Cover: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Cover) -> some View { modifier(FullScreenCoverModifier(isPresented: isPresented, onDismiss: _mainActor(onDismiss), content: content)) }
  nonisolated func popover<Popover: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Popover) -> some View { modifier(PopoverModifier(isPresented: isPresented, content: content)) }
  @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
  nonisolated func sheet<Item: Identifiable, Sheet: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Sheet) -> some View {
    modifier(ItemSheetModifier(item: item, onDismiss: _mainActor(onDismiss), content: content))
  }
  @available(macOS 10.15, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
  nonisolated func fullScreenCover<Item: Identifiable, Cover: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Cover) -> some View {
    modifier(ItemFullScreenCoverModifier(item: item, onDismiss: _mainActor(onDismiss), content: content))
  }
  @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
  nonisolated func popover<Item: Identifiable, Popover: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Popover) -> some View {
    modifier(ItemPopoverModifier(item: item, onDismiss: nil, content: content))
  }
  nonisolated func toolbar<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View { modifier(ToolbarModifier(content: content)) }
  nonisolated func preferredColorScheme(_ scheme: ColorScheme?) -> some View {
    modifier(_preferredColorSchemeModifier(scheme))
  }
  /// A `nil` prompt shows the platform's "Search" placeholder.
  nonisolated func searchable(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil) -> some View {
    modifier(_searchableModifier(text: text, placement: placement, prompt: prompt?.value ?? "Search"))
  }
  nonisolated func searchable(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey) -> some View {
    modifier(_searchableModifier(text: text, placement: placement, prompt: prompt.resolved))
  }
  @_disfavoredOverload nonisolated func searchable<S: StringProtocol>(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: S) -> some View {
    modifier(_searchableModifier(text: text, placement: placement, prompt: String(prompt)))
  }
  /// `isPresented` reports whether the search field is active; the browser field is always shown.
  nonisolated func searchable(text: Binding<String>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil) -> some View {
    searchable(text: text, placement: placement, prompt: prompt)
  }
  nonisolated func searchable(text: Binding<String>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey) -> some View {
    searchable(text: text, placement: placement, prompt: prompt)
  }
  @_disfavoredOverload nonisolated func searchable<S: StringProtocol>(text: Binding<String>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: S) -> some View {
    searchable(text: text, placement: placement, prompt: prompt)
  }
}

/// Renderer metadata for SwiftUI's `layoutPriority(_:)` modifier. Keeping the
/// modifier as a normal `ViewModifier` means values flow through nested
/// custom layouts and remain available via `LayoutSubview.priority`.
package nonisolated struct LayoutPriorityModifier: ViewModifier {
  package let value: Double
  package init(value: Double) { self.value = value }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let normalized = value.isFinite ? value : 0
    node.attributes["data-layout-priority"] = normalized.clean
  }
}

package nonisolated struct IDModifier: ViewModifier {
  package let id: _FiberKey
  package init(id: _FiberKey) { self.id = id }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.key = id
    // Keep a DOM-visible identity marker for ScrollViewProxy and accessibility
    // tooling while preserving the Fiber key used by reconciliation.
    node.attributes["data-view-id"] = fiberKeyDescription(id)
  }
}

package nonisolated struct StyleModifier: ViewModifier {
  package let styles: _NodeValues
  let semantic: _NodeValues
  package init(styles: _NodeValues) { self.styles = styles; self.semantic = .init() }
  package init(styles: _NodeValues, semantic: _NodeValues) { self.styles = styles; self.semantic = semantic }
  @MainActor package func _modifyContext(_ context: inout _RenderContext) {
    guard semantic["data-layout-kind"] == "frame" else { return }
    let width = semantic["data-frame-w"].flatMap(Double.init)
    let height = semantic["data-frame-h"].flatMap(Double.init)
    if width != nil || height != nil {
      let inherited = context._layoutProposal
      context._layoutProposal = ProposedViewSize(width: width.map { CGFloat($0) } ?? inherited?.width, height: height.map { CGFloat($0) } ?? inherited?.height)
    }
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let layers = context._mergesLayoutLayers
    if node.kind == .fragment {
      // Each element of the group, looking through the groups inside it, in order. A loop: groups nest as deep as the
      // view tree does, and a recursion here costs a frame per level on top of the rest of the pass.
      var pending = Array(node.children.reversed())
      while let child = pending.popLast() {
        if child.kind == .fragment {
          pending.append(contentsOf: child.children.reversed())
        } else {
          _applyToElement(child, layers: layers)
        }
      }
      return
    }
    _applyToElement(node, layers: layers)
  }

  @MainActor private func _applyToElement(_ node: _RenderNode, layers: Bool) {
    let layoutKind = semantic["data-layout-kind"]
    if let kind = layoutKind {
      // Keep host-visible split metadata on the frame boundary as well as on
      // the retained layout child. This preserves the package root shape for
      // split-view hosts while the frame still owns its own proposal boundary.
      let originalClasses = node.classes
      // Only a split view's frame needs them, and reading the attributes of a node whose children have not
      // rendered would render them.
      let originalAttributes = originalClasses.contains("split-pane") ? node.attributes : .init()
      // Canvas is already a replaced/native element.  Keep its element
      // identity when a frame is applied so the browser adapter can retain
      // the drawing surface and its command stream.  Ordinary views still
      // receive a real wrapper boundary, which is required for nested frame
      // proposals and Fiber identity.
      let preservesCanvas = kind == "frame" && node.kind == .element("canvas")
      if !preservesCanvas {
        // A wrapper that is nothing but layout shares its element with the layer this modifier adds, instead of getting
        // an element inside it (see `_SemanticLayers`).
        switch _SemanticLayers.absorb(kind: kind, semantic: semantic, into: node, allowsLayers: layers) {
        case .folded: return
        case .layered: break
        case .no: _semanticWrap(node, kind: kind)
        }
      }
      for (name, value) in semantic { node.attributes[name] = value }
      if kind == "frame", originalClasses.contains("split-pane") {
        for className in originalClasses where !node.classes.contains(className) {
          node.classes.append(className)
        }
        for (name, value) in originalAttributes where name.hasPrefix("data-split-") {
          node.attributes[name] = value
        }
      }
      if preservesCanvas { node.classes.append("frame-box") }
      if kind == "frame", semantic["data-frame-max-w"] == "inf" {
        node.attributes["data-flexible-width"] = "true"
      }
      // Static HTML and the standard host retain a bounded fallback. Embedded
      // resolved geometry replaces these layout-only properties, never paint.
      if kind == "frame" || kind == "fixed" {
        node.styles["display"] = "grid"
        if let alignment = styles["--frame-alignment"] {
          applyFrameAlignment(alignment, to: node, contentClasses: originalClasses)
        } else {
          node.styles["place-items"] = "center"
        }
      }
    }
    for (key, value) in styles where key != "--frame-alignment" {
      if key == "transform", let existing = node.styles[key], !existing.isEmpty {
        node.styles[key] = "\(value) \(existing)"
      } else {
        node.styles[key] = value
      }
    }
  }
}

@MainActor private func applyFrameAlignment(
  _ alignment: String,
  to node: _RenderNode,
  contentClasses: [String]
) {
  // Keep a stable marker for browser/runtime adapters and for subsequent
  // nested frames. It is intentionally not part of the public API.
  node.attributes["data-frame-alignment"] = alignment

  if contentClasses.contains("zstack") {
    node.styles["place-items"] = alignment
    return
  }

  if contentClasses.contains("backdrop-layer") ||
      contentClasses.contains("overlay-layer") ||
      contentClasses.contains("presentation-host") {
    // These modifiers already use a grid layer for their children. Keep that
    // compositing model intact and let place-items express the frame's
    // alignment instead of replacing the grid with a flex leaf.
    node.styles["place-items"] = alignment
    return
  }

  if contentClasses.contains("vstack") ||
      contentClasses.contains("hstack") ||
      contentClasses.contains("grid-layout") ||
      contentClasses.contains("scroll-view") ||
      contentClasses.contains("navigation-stack") ||
      contentClasses.contains("navigation-view") ||
      contentClasses.contains("navigation-root") {
    // A stack's own alignment controls its children. Frame alignment instead
    // positions the stack's box in its parent, which CSS margins model without
    // disturbing the stack's cross-axis alignment.
    switch alignment {
    case "start", "end start", "center start":
      node.styles["margin-right"] = "auto"
    case "start end", "end", "center end":
      node.styles["margin-left"] = "auto"
    default:
      node.styles["margin-inline"] = "auto"
    }
    switch alignment {
    case "start", "start center", "start end":
      node.styles["margin-bottom"] = "auto"
    case "end start", "end center", "end":
      node.styles["margin-top"] = "auto"
    default:
      node.styles["margin-block"] = "auto"
    }
    return
  }

  // `_semanticWrap` gives every frame its own grid boundary. Keep it a grid
  // for leaf views as well; `place-items` expresses both alignment axes.
  node.styles["place-items"] = alignment
}

package nonisolated struct ForegroundModifier: ViewModifier {
  package let color: Color
  package init(color: Color) { self.color = color }
  @MainActor package func _modifyContext(_ context: inout _RenderContext) { context.environment.foregroundColor = color }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) { node.styles["color"] = color.cssValue }
}

package nonisolated struct ShapeStyleForegroundModifier<Style: ShapeStyle>: ViewModifier {
  package let style: Style
  package init(style: Style) { self.style = style }
  @MainActor package func _modifyContext(_ context: inout _RenderContext) {
    // Preserve a solid color in the environment when possible; gradients are
    // still emitted as paint metadata on the affected node.
    if let color = style._swiftUIWebSolidColor { context.environment.foregroundColor = color } else { context.environment._paintClipsToText = true }
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    if style._swiftUIWebSolidColor != nil {
      node.styles["color"] = _paintCSSValue(style)
    } else {
      // Text does not accept an SVG paint server directly. Use the browser's
      // background-clip primitive while retaining the original ShapeStyle
      // value in metadata for non-browser hosts.
      node.styles["background-image"] = _paintCSSValue(style)
      node.styles["background-clip"] = "text"
      node.styles["-webkit-background-clip"] = "text"
      node.styles["color"] = "transparent"
      _applyImagePaintMarkers(style, to: node)
    }
    node.attributes["data-foreground-style"] = style._swiftUIWebCSSValue
  }
}

package nonisolated struct FontModifier: ViewModifier {
  package let font: Font
  package init(font: Font) { self.font = font }
  @MainActor package func _modifyContext(_ context: inout _RenderContext) { context.environment.font = font }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) { for (key, value) in font.cssStyles { node.styles[key] = value } }
}

package nonisolated struct AttributeModifier: ViewModifier {
  package let attributes: _NodeValues
  package init(attributes: _NodeValues) { self.attributes = attributes }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node._forEachHost { node in
      for (key, value) in attributes {
        if key == "aria-label" {
          _AccessibilityBackend.setLabel(value, on: node)
          // A composite such as VideoPlayer keeps its media element named after the composite's label.
          for child in node.children where child.attributes["data-label-follows"] == "true" {
            child.attributes["aria-label"] = value
          }
        }
        else { node.attributes[key] = value }
      }
    }
  }
}

/// Carries a typed tag through the render tree.  Besides the stable textual
/// marker used by HTML, TabView installs a private event carrying the original
/// value so enum-backed selections update without a string decoder.
package nonisolated struct TagModifier<TagValue: Hashable>: ViewModifier {
  package let value: TagValue
  package init(value: TagValue) { self.value = value }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let tagIdentity = _FiberKey(value)
    node._tagIdentity = tagIdentity
    node._pickerSelectionValue = _RuntimeValue(value)
    node.attributes["data-tag"] = fiberKeyDescription(tagIdentity)
    if !context.environment.isEnabled {
      node.attributes["disabled"] = "disabled"
      node.attributes["aria-disabled"] = "true"
    }
    if let sink = context.environment.tabSelectionSink {
      _renderRegistersWithAncestors()
      sink.register(value)
      node.events["tab-select"] = _EventHandler(name: "tab-select", action: { sink.select(_RuntimeValue(value)) })
    }
  }
}

/// SwiftUI's badge modifier is also meaningful on tabs. Keeping it as a
/// normal view modifier lets badges participate in identity/reconciliation
/// while TabView extracts the compact value for its tab bar.
package nonisolated struct BadgeModifier: ViewModifier {
  package let value: String?
  package init(value: String?) { self.value = value }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    guard let value, !value.isEmpty else {
      node.attributes.removeValue(forKey: "data-badge")
      return
    }
    node.attributes["data-badge"] = value
    if node.attributes["aria-label"] == nil { _AccessibilityBackend.setLabel(value, on: node) }
  }
}

/// Stable customization identifier used by TabViewCustomization. This is a
/// metadata-only modifier and remains useful on dynamic tabs without changing
/// their selection tags or Fiber identity.
package nonisolated struct TabCustomizationIDModifier: ViewModifier {
  package let identifier: String
  package init(identifier: String) { self.identifier = identifier }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-tab-customization-id"] = identifier
  }
}

package nonisolated struct TabViewCustomizationModifier: ViewModifier {
  private let value: TabViewCustomization
  private let binding: Binding<TabViewCustomization>?

  package init(value: TabViewCustomization) {
    self.value = value
    self.binding = nil
  }

  package init(binding: Binding<TabViewCustomization>) {
    self.value = binding.wrappedValue
    self.binding = binding
  }

  @MainActor package func _modifyContext(_ context: inout _RenderContext) {
    context.environment.tabViewCustomization = binding?.wrappedValue ?? value
  }

  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-tab-customization"] = "true"
  }
}

package nonisolated struct TabViewMountPolicyModifier: ViewModifier {
  package let policy: TabViewMountPolicy
  package init(policy: TabViewMountPolicy) { self.policy = policy }
  @MainActor package func _modifyContext(_ context: inout _RenderContext) { context.environment.tabViewMountPolicy = policy }
}

/// Carries a SwiftUI `TabViewStyle` through the environment. The browser
/// stylesheet owns the viewport breakpoint, so this modifier never asks the
/// application to branch on device class.
package nonisolated struct TabViewStyleModifier<Style: TabViewStyle>: ViewModifier {
  package let style: Style

  package init(style: Style) { self.style = style }

  @MainActor package func _modifyContext(_ context: inout _RenderContext) {
    context.environment.tabViewStyle = style._swiftUIWebTabViewStyle
  }

  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-tab-style"] = style._swiftUIWebTabViewStyle
  }
}

/// Internal render metadata for SwiftUI's `contentShape` modifier.  The
/// generic parameter deliberately remains unconstrained so existing
/// SwiftUIWeb code that passed a project-defined shape continues to compile.
package nonisolated struct ContentShapeModifier<ShapeValue>: ViewModifier {
  package let shape: ShapeValue
  package let eoFill: Bool
  package init(shape: ShapeValue, eoFill: Bool = false) { self.shape = shape; self.eoFill = eoFill }

  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let descriptor = _contentShapeDescriptor(shape)
    // A hit region on a Group belongs to each of its children, as in SwiftUI.
    node._forEachHost { node in
      node.attributes["data-content-shape"] = descriptor.name
      if eoFill { node.attributes["data-content-shape-fill-rule"] = "evenodd" }
      for (key, value) in descriptor.styles { node.styles[key] = value }
      #if !hasFeature(Embedded)
      if let shape = shape as? any Shape {
        let rect = CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: 100, height: 100))
        let path = _shapePath(for: shape, in: rect)._svgPathData
        if !path.isEmpty {
          node.attributes["data-content-shape-path"] = path
          if descriptor.name != "circle" && descriptor.name != "capsule" &&
             descriptor.name != "rectangle" && descriptor.name != "rounded-rectangle" {
            node.styles["clip-path"] = "path('\(path)')"
          }
        }
      }
      #endif
    }
  }
}

/// A host-neutral SwiftUI `Shape`. Shapes are also Views: rendering them
/// directly produces retained vector geometry, while `fill`/`stroke` attach
/// paint metadata. Custom application shapes can continue to conform without
/// exposing DOM or browser types.
/// SwiftUI-compatible shape contract.  Shapes are primitive views whose
/// geometry is described by `path(in:)`; the browser backend may choose a CSS
/// or SVG realization.  Constraining `Body` to `Never` gives custom shapes the
/// same ergonomic behavior as SwiftUI without requiring a dummy `body`.
public nonisolated protocol Shape: Animatable, View where Body == Never {
  /// SwiftUI's geometry requirement. A default implementation below keeps
  /// older SwiftUIWeb primitive shapes source-compatible while allowing
  /// custom implementations to participate through protocol dispatch.
  nonisolated func path(in rect: CGRect) -> Path
  /// Renderer hook for shape adapters such as `trim(from:to:)`. It is a
  /// protocol requirement (statically dispatched after specialization), not a
  /// dynamic cast, so the adapter also works in Embedded Swift where casting
  /// a generic value to an existential is unavailable.
  nonisolated var _swiftUIWebShapeAdapter: _ShapeAdapter? { get }
  /// The stroke of an outline shape from `stroke(style:)`. Filling such a shape paints its stroke, so the
  /// fill path reads this requirement rather than the geometry alone.
  nonisolated var _swiftUIWebStrokeStyle: StrokeStyle? { get }
}

/// Renderer-only description of a shape adapter (currently `trim`). The base
/// shape's name and path are captured as values so no existential or dynamic
/// cast is needed to recover them.
public struct _ShapeAdapter {
  public let trimFrom: Double
  public let trimTo: Double
  let baseName: String
  let basePath: (CGRect) -> Path
  let baseRadiusStyles: _NodeValues
}

public extension Shape {
  nonisolated var _swiftUIWebShapeAdapter: _ShapeAdapter? { nil }
  nonisolated var _swiftUIWebStrokeStyle: StrokeStyle? { nil }
}

/// The outline of a shape, returned by `Shape.stroke(style:)`. Its geometry is the base path. As a view it strokes the
/// base with the default foreground paint (identical to the former `stroke(lineWidth:)` view), and a fill paints the
/// stroke with its paint.
nonisolated struct _StrokedShape<Base: Shape>: Shape {
  typealias Body = Never
  let base: Base
  let stroke: StrokeStyle
  nonisolated func path(in rect: CGRect) -> Path { base.path(in: rect) }
  nonisolated var _swiftUIWebStrokeStyle: StrokeStyle? { stroke }
  /// Drawn in the foreground style, as SwiftUI strokes a `stroke(style:)` shape: the colour of the surrounding text or
  /// of a `foregroundStyle` on it, not the page's text colour.
  @MainActor func _render(in context: _RenderContext) -> _RenderNode {
    _ShapeView(shape: base, style: ForegroundStyle(), stroke: stroke)._render(in: context)
  }
}

public enum RoundedCornerStyle: Hashable, Sendable {
  case circular
  case continuous

  /// The CSS spelling of each case; SwiftUI does not expose a raw value.
  var rawValue: String {
    switch self {
    case .circular: "circular"
    case .continuous: "continuous"
    }
  }
}

public struct StrokeStyle: Hashable, Sendable {
  public var lineWidth: Double
  public var lineCap: CGLineCap
  public var lineJoin: CGLineJoin
  public var miterLimit: Double
  public var dash: [Double]
  public var dashPhase: Double

  public init(
    lineWidth: Double = 1,
    lineCap: CGLineCap = .butt,
    lineJoin: CGLineJoin = .miter,
    miterLimit: Double = 10,
    dash: [Double] = [],
    dashPhase: Double = 0
  ) {
    self.lineWidth = lineWidth; self.lineCap = lineCap; self.lineJoin = lineJoin
    self.miterLimit = miterLimit; self.dash = dash; self.dashPhase = dashPhase
  }

  /// SVG and canvas name the cap and join; CoreGraphics only exposes raw values.
  var _svgLineCap: String {
    switch lineCap.rawValue {
    case 1: return "round"
    case 2: return "square"
    default: return "butt"
    }
  }

  var _svgLineJoin: String {
    switch lineJoin.rawValue {
    case 1: return "round"
    case 2: return "bevel"
    default: return "miter"
    }
  }
}

public struct FillStyle: Hashable, Sendable {
  public let isEOFilled: Bool
  public let isAntialiased: Bool
  public init(eoFill: Bool = false, antialiased: Bool = true) { self.isEOFilled = eoFill; self.isAntialiased = antialiased }
}

public struct Rectangle: InsettableShape, Hashable, Sendable {
  public typealias Body = Never
  fileprivate var _insetAmount: Double
  public init() { _insetAmount = 0 }
  public nonisolated func inset(by amount: CGFloat) -> Rectangle {
    var copy = self; copy._insetAmount = max(0, Double(amount)); return copy
  }
}

public struct Circle: InsettableShape, Hashable, Sendable {
  public typealias Body = Never
  fileprivate var _insetAmount: Double
  public init() { _insetAmount = 0 }
  public nonisolated func inset(by amount: CGFloat) -> Circle {
    var copy = self; copy._insetAmount = max(0, Double(amount)); return copy
  }
}

public struct Ellipse: InsettableShape, Hashable, Sendable {
  public typealias Body = Never
  fileprivate var _insetAmount: Double
  public init() { _insetAmount = 0 }
  public nonisolated func inset(by amount: CGFloat) -> Ellipse {
    var copy = self; copy._insetAmount = max(0, Double(amount)); return copy
  }
}

public struct Capsule: InsettableShape, Hashable, Sendable {
  public typealias Body = Never
  public let style: RoundedCornerStyle
  fileprivate var _insetAmount: Double
  public init(style: RoundedCornerStyle = .circular) { self.style = style; _insetAmount = 0 }
  public nonisolated func inset(by amount: CGFloat) -> Capsule {
    var copy = self; copy._insetAmount = max(0, Double(amount)); return copy
  }
}

public struct RoundedRectangle: InsettableShape, Hashable, Sendable {
  public typealias Body = Never
  package let cornerRadius: Double
  public let style: RoundedCornerStyle
  fileprivate var _insetAmount: Double
  public init(cornerRadius: Double, style: RoundedCornerStyle = .continuous) { self.cornerRadius = cornerRadius; self.style = style; _insetAmount = 0 }
  public nonisolated func inset(by amount: CGFloat) -> RoundedRectangle {
    var copy = self; copy._insetAmount = max(0, Double(amount)); return copy
  }
}

// Built-in shapes expose real paths through the public SwiftUI contract as
// well as through the renderer's fast path.  This matters when application
// code composes a built-in shape into another custom `Shape`.
public extension Rectangle {
  nonisolated func path(in rect: CGRect) -> Path {
    var path = Path(); path.addRect(_insetShapeRect(rect, by: _insetAmount)); return path
  }
}

public extension Circle {
  /// SwiftUI draws a circle with the shorter side as its diameter, centered in
  /// the proposed rect; it never degrades into an ellipse.
  nonisolated func path(in rect: CGRect) -> Path {
    var path = Path(); path.addEllipse(in: _centeredSquare(_insetShapeRect(rect, by: _insetAmount))); return path
  }
}

public extension Ellipse {
  nonisolated func path(in rect: CGRect) -> Path {
    var path = Path(); path.addEllipse(in: _insetShapeRect(rect, by: _insetAmount)); return path
  }
}

public extension Capsule {
  nonisolated func path(in rect: CGRect) -> Path {
    let insetRect = _insetShapeRect(rect, by: _insetAmount)
    let radius = min(insetRect.size.width, insetRect.size.height) / 2
    var path = Path()
    path.addRoundedRect(in: insetRect, cornerSize: CGSize(width: radius, height: radius), style: style)
    return path
  }
}

public extension RoundedRectangle {
  nonisolated func path(in rect: CGRect) -> Path {
    let insetRect = _insetShapeRect(rect, by: _insetAmount)
    let radius = max(0, cornerRadius - _insetAmount)
    var path = Path()
    path.addRoundedRect(in: insetRect, cornerSize: CGSize(width: radius, height: radius), style: style)
    return path
  }
}

public extension ContainerRelativeShape {
  nonisolated func path(in rect: CGRect) -> Path {
    var path = Path(); path.addRect(rect); return path
  }
}

/// Matches SwiftUI's container-relative shape spelling.  CSS uses the
/// container's own box, so this is represented as a rounded rectangle with a
/// zero radius marker rather than a browser-specific shape object.
public struct ContainerRelativeShape: Shape, Hashable, Sendable {
  public typealias Body = Never
  public init() {}
}

public extension Shape where Self == RoundedRectangle {
  /// Contextual SwiftUI shape factory used by expressions such as
  /// `.background(color, in: .rect(cornerRadius: 12))`. Like SwiftUI the
  /// radius is required, so `.rect(...)` with only defaulted arguments means
  /// `UnevenRoundedRectangle` and bare `.rect` means `Rectangle`.
  static func rect(cornerRadius: Double, style: RoundedCornerStyle = .continuous) -> Self {
    RoundedRectangle(cornerRadius: cornerRadius, style: style)
  }

}

public extension Shape {
  nonisolated func _render(in context: _RenderContext) -> _RenderNode {
    // A shape with animatable data draws the path of the data its animation has reached (`Animator.swift`).
    guard Self._swiftUIWebAnimates else { return _filledWithForeground(_svgShapeNode(shape: self, context: context)) }
    nonisolated(unsafe) let shape = self
    return _assumeMainActor {
      AnyView(_ownerBoundaryOf: _AnimatedShape(shape: shape) { shape, context in
        _filledWithForeground(_svgShapeNode(shape: shape, context: context))
      })
        ._render(in: context)
    }
  }

  /// Apple's `Shape.fill(_:style:)`: the shape painted with `content`, as a `ShapeView` that can take
  /// further `stroke`/`strokeBorder` paints over the same shape.
  nonisolated func fill<S: ShapeStyle>(_ content: S = .foreground, style: FillStyle = FillStyle()) -> _ShapeView<Self, S> {
    _ShapeView(shape: self, style: content, stroke: nil, fillStyle: style)
  }

  @_disfavoredOverload nonisolated func fill(style: FillStyle = FillStyle()) -> some View {
    fill(ForegroundStyle(), style: style)
  }

  nonisolated func stroke<S: ShapeStyle>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> StrokeShapeView<Self, S, EmptyView> {
    StrokeShapeView(shape: self, style: content, strokeStyle: style, isAntialiased: antialiased, background: EmptyView())
  }

  nonisolated func stroke<S: ShapeStyle>(_ content: S, lineWidth: Double = 1, antialiased: Bool = true) -> StrokeShapeView<Self, S, EmptyView> {
    stroke(content, style: StrokeStyle(lineWidth: lineWidth), antialiased: antialiased)
  }

  /// Apple's `Shape.stroke(style:)`: the outline of this shape, as a shape.
  nonisolated func stroke(style: StrokeStyle) -> some Shape {
    _StrokedShape(base: self, stroke: style)
  }

  /// Apple's `Shape.stroke(lineWidth:)`: the outline of this shape, as a shape.
  nonisolated func stroke(lineWidth: Double = 1) -> some Shape {
    stroke(style: StrokeStyle(lineWidth: lineWidth))
  }

  /// SwiftUI's trim operation is represented as geometry metadata and is
  /// applied by SVG/Canvas hosts at paint time. The underlying path remains
  /// intact so identity and animation interpolation are preserved.
  nonisolated func trim(from start: Double = 0, to end: Double = 1) -> _TrimmedShape<Self> {
    _TrimmedShape(base: self, from: start, to: end)
  }

}

/// Shapes that can move their geometry inward for an inside-aligned stroke.
/// SwiftUI uses `CGFloat`; SwiftUIWeb's public geometry APIs consistently use
/// `Double`, including `CGRect`-backed Path construction.
public protocol InsettableShape: Shape {
  nonisolated func inset(by amount: CGFloat) -> Self
}

public extension InsettableShape {
  /// Apple's `strokeBorder(_:style:antialiased:)`: the stroke lies inside the shape's bounds.
  func strokeBorder<S: ShapeStyle>(_ content: S = .foreground, style: StrokeStyle, antialiased: Bool = true) -> StrokeBorderShapeView<Self, S, EmptyView> {
    StrokeBorderShapeView(shape: self, style: content, strokeStyle: style, isAntialiased: antialiased, background: EmptyView())
  }

  func strokeBorder<S: ShapeStyle>(_ content: S = .foreground, lineWidth: Double = 1, antialiased: Bool = true) -> StrokeBorderShapeView<Self, S, EmptyView> {
    strokeBorder(content, style: StrokeStyle(lineWidth: lineWidth), antialiased: antialiased)
  }

  @_disfavoredOverload func strokeBorder(style: StrokeStyle, antialiased: Bool = true) -> some View {
    strokeBorder(ForegroundStyle(), style: style, antialiased: antialiased)
  }

  @_disfavoredOverload func strokeBorder(lineWidth: Double = 1, antialiased: Bool = true) -> some View {
    strokeBorder(ForegroundStyle(), lineWidth: lineWidth, antialiased: antialiased)
  }
}

public nonisolated struct _TrimmedShape<Base: Shape>: Shape {
  public typealias Body = Never
  public let base: Base
  public let from: Double
  public let to: Double

  public init(base: Base, from: Double, to: Double) {
    self.base = base
    self.from = min(1, max(0, from))
    self.to = min(1, max(0, to))
  }

  public func path(in rect: CGRect) -> Path { base.path(in: rect) }
}

extension _TrimmedShape {
  public var _swiftUIWebShapeAdapter: _ShapeAdapter? {
    // Built-in shapes do not need a public `path(in:)` implementation; the
    // shared SVG helper recognizes their concrete type before falling back to
    // the custom path.
    let base = self.base
    return _ShapeAdapter(
      trimFrom: from,
      trimTo: to,
      baseName: _shapeName(base),
      basePath: { _shapePath(for: base, in: $0) },
      baseRadiusStyles: _shapeRadiusStyles(base)
    )
  }
}

extension _TrimmedShape: InsettableShape where Base: InsettableShape {
  public func inset(by amount: CGFloat) -> _TrimmedShape<Base> {
    _TrimmedShape(base: base.inset(by: amount), from: from, to: to)
  }
}

private func _shapeName<S: Shape>(_ shape: S) -> String {
  if let adapter = shape._swiftUIWebShapeAdapter { return adapter.baseName }
  if shape is Path { return "path" }
  if shape is Rectangle { return "rectangle" }
  if shape is Circle { return "circle" }
  if shape is Ellipse { return "ellipse" }
  if shape is Capsule || shape is DefaultGlassEffectShape { return "capsule" }
  if let rounded = shape as? RoundedRectangle { return "rounded-rectangle-\(rounded.cornerRadius.clean)" }
  if shape is UnevenRoundedRectangle { return "uneven-rounded-rectangle" }
  if shape is ContainerRelativeShape { return "container-relative" }
  return "shape"
}

private func _finiteShapeDimension(_ value: CGFloat?, fallback: Double = 100) -> Double {
  guard let value, value.isFinite, value > 0 else { return fallback }
  return min(Double(value), 100_000)
}

private func _shapePath<S: Shape>(for shape: S, in rect: CGRect) -> Path {
  if let adapter = shape._swiftUIWebShapeAdapter { return adapter.basePath(rect) }
  if let path = shape as? Path { return path }
  if let insettable = shape as? Rectangle {
    var path = Path()
    let inset = insettable._insetAmount
    let insetRect = _insetShapeRect(rect, by: inset)
    path.addRect(insetRect)
    return path
  }
  if let insettable = shape as? Circle {
    var path = Path()
    let inset = insettable._insetAmount
    path.addEllipse(in: _centeredSquare(_insetShapeRect(rect, by: inset)))
    return path
  }
  if let insettable = shape as? Ellipse {
    var path = Path()
    let inset = insettable._insetAmount
    path.addEllipse(in: _insetShapeRect(rect, by: inset))
    return path
  }
  if let rounded = shape as? RoundedRectangle {
    var path = Path()
    let inset = rounded._insetAmount
    let insetRect = _insetShapeRect(rect, by: inset)
    let radius = max(0, rounded.cornerRadius - inset)
    path.addRoundedRect(in: insetRect, cornerSize: CGSize(width: radius, height: radius), style: rounded.style)
    return path
  }
  if let capsule = shape as? Capsule {
    var path = Path()
    let inset = capsule._insetAmount
    let insetRect = _insetShapeRect(rect, by: inset)
    let radius = min(insetRect.size.width, insetRect.size.height) / 2
    path.addRoundedRect(in: insetRect, cornerSize: CGSize(width: radius, height: radius), style: capsule.style)
    return path
  }
  if shape is ContainerRelativeShape {
    var path = Path(); path.addRect(rect); return path
  }
  return shape.path(in: rect)
}

/// The largest square centered in `rect` (Circle's geometry).
private func _centeredSquare(_ rect: CGRect) -> CGRect {
  let side = min(rect.size.width, rect.size.height)
  return CGRect(
    origin: CGPoint(x: rect.origin.x + (rect.size.width - side) / 2, y: rect.origin.y + (rect.size.height - side) / 2),
    size: CGSize(width: side, height: side)
  )
}

private func _insetShapeRect(_ rect: CGRect, by amount: Double) -> CGRect {
  let inset = max(0, amount)
  return CGRect(
    origin: CGPoint(x: rect.origin.x + inset, y: rect.origin.y + inset),
    size: CGSize(width: max(0, rect.size.width - inset * 2), height: max(0, rect.size.height - inset * 2))
  )
}

private func _shapeRenderSize(_ context: _RenderContext) -> (width: Double, height: Double) {
  (_finiteShapeDimension(context._layoutProposal?.width), _finiteShapeDimension(context._layoutProposal?.height))
}

/// Whether the shape has an explicit proposal. Without one the SVG is authored
/// in a nominal 100x100 space and the DOM size is only known after layout, so
/// geometry must be expressed in a way that survives a non-uniform stretch.
private func _shapeSizeIsKnown(_ context: _RenderContext) -> Bool {
  guard let proposal = context._layoutProposal, let width = proposal.width, let height = proposal.height else { return false }
  return width.isFinite && height.isFinite && width > 0 && height > 0
}

/// Circular-corner shapes whose geometry is realized with CSS `border-radius`.
/// CSS clamps all four radii by one common factor, so the corners stay
/// circular at any laid-out size (an SVG path stretched with
/// `preserveAspectRatio="none"` turns them elliptical).
private struct _CSSRoundedShape {
  let radius: String
  let outlineRadius: String
  let inset: Double
}

private func _cssRoundedShape<S: Shape>(_ shape: S) -> _CSSRoundedShape? {
  if shape._swiftUIWebShapeAdapter != nil { return nil }
  if let rounded = shape as? RoundedRectangle {
    let radius = "\(max(0, rounded.cornerRadius).clean)px"
    return _CSSRoundedShape(radius: radius, outlineRadius: radius, inset: rounded._insetAmount)
  }
  if let capsule = shape as? Capsule {
    return _CSSRoundedShape(radius: "9999px", outlineRadius: "9999px", inset: capsule._insetAmount)
  }
  return nil
}

/// SwiftUI's `.shadow` follows the alpha of what a view draws. A CSS
/// `box-shadow` follows the element's box instead, which for a non-rectangular
/// shape (or a shape-filled background) draws a rectangle. For those nodes the
/// same offset/blur/color is expressed as `filter: drop-shadow(...)`.
func _shapeShadowFilter(for node: _RenderNode, boxShadow value: String) -> String? {
  guard !_swiftUIWebContainsLiteral(value, "inset") else { return nil }
  let shapeName: String?
  if node.classes.contains("shape-layer") { shapeName = node.attributes["data-shape"] }
  else if node.classes.contains("backdrop-layer") {
    var layer = node.children.first
    while let current = layer, case .fragment = current.kind { layer = current.children.first }
    if let name = layer?.attributes["data-background-shape"] { shapeName = name }
    else if let layer, layer.classes.contains("shape-layer") { shapeName = layer.attributes["data-shape"] }
    else { shapeName = nil }
  } else { shapeName = nil }
  guard let shapeName, shapeName != "rectangle" else { return nil }
  let shadow = "drop-shadow(\(value))"
  guard let existing = node.styles["filter"], !existing.isEmpty, !_swiftUIWebContainsLiteral(existing, "drop-shadow") else { return shadow }
  return existing + " " + shadow
}

/// The `border-radius` of the clipped content that an overlay or background wrapper sits on, or nil. Both
/// wrappers take exactly the box of their base view, so a shadow on the wrapper can use the same radius.
func _wrappedClippedRadius(of node: _RenderNode) -> String? {
  var current = node
  for _ in 0..<4 {
    guard let kind = current.attributes["data-layout-kind"], kind == "overlay" || kind == "background" else { return nil }
    var base = current.children.first
    while let candidate = base, case .fragment = candidate.kind { base = candidate.children.first }
    guard let content = base else { return nil }
    if content.styles["overflow"] == "hidden", let radius = content.styles["border-radius"], !radius.isEmpty { return radius }
    current = content
  }
  return nil
}

private func _isCircleShape<S: Shape>(_ shape: S) -> Bool {
  if shape is Circle { return true }
  return shape._swiftUIWebShapeAdapter?.baseName == "circle"
}

/// Replaces the rounded SVG outline of a fill with the plain bounds rectangle
/// and lets CSS round (and clip) the corners at the real laid-out size.
private func _realizeRoundedFillInCSS(_ rounded: _CSSRoundedShape, on node: _RenderNode, size: (width: Double, height: Double)) {
  guard rounded.inset == 0 else { return }
  for child in node.children {
    if case .element("path") = child.kind {
      child.attributes["d"] = "M 0 0 L \(size.width.clean) 0 L \(size.width.clean) \(size.height.clean) L 0 \(size.height.clean) Z"
    }
  }
  node.styles["border-radius"] = rounded.radius
  node.styles["overflow"] = "hidden"
  node.attributes["data-shape-geometry"] = "css-radius"
}

/// A solid fill of a rectangle, rounded rectangle, capsule or circle is one element that CSS paints: `background`
/// on a box whose corners are `border-radius`, as a `Color` is painted. Everything else keeps the SVG path: gradients,
/// images, even-odd or unantialiased fills, insets, trims and other shapes, and a circle whose box is not known to be
/// square (CSS would make an unequal box an ellipse). The path stays in `data-shape-path`, which masks read.
@MainActor private func _cssSolidFillNode<S: Shape, Style: ShapeStyle>(shape: S, style: Style, fillStyle: FillStyle?, context: _RenderContext) -> _RenderNode? {
  guard style._swiftUIWebSolidColor != nil, _resolvedImagePaint(style) == nil, shape._swiftUIWebShapeAdapter == nil,
        fillStyle?.isEOFilled != true, fillStyle?.isAntialiased != false else { return nil }
  // Every insettable shape keeps its inset in `_insetAmount`, so an inset shape (an `inset(by:)` copy) takes the path.
  let radius: String?
  if let rectangle = shape as? Rectangle, rectangle._insetAmount == 0 {
    radius = nil
  } else if let rounded = _cssRoundedShape(shape), rounded.inset == 0 {
    radius = rounded.radius
  } else if let circle = shape as? Circle, circle._insetAmount == 0, _shapeSizeIsSquare(context) {
    radius = "9999px"
  } else {
    return nil
  }
  return _cssSolidFillNode(
    name: _shapeName(shape), path: _shapeSVGPathData(shape, context: context), paint: style._swiftUIWebCSSValue,
    background: _paintCSSValue(style), radius: radius)
}

/// The non-generic part of `_cssSolidFillNode`, so it is not compiled once per shape and style.
@MainActor private func _cssSolidFillNode(name: String, path: String, paint: String, background: String, radius: String?) -> _RenderNode {
  let node = _RenderNode.element("div")
  node.classes = ["shape-layer"]
  node.attributes["data-shape"] = name
  node.attributes["data-shape-path"] = path
  node.attributes["data-shape-style"] = "fill"
  node.attributes["data-shape-stroke-border"] = "false"
  node.attributes["data-shape-paint"] = paint
  node.styles["display"] = "block"
  node.styles["width"] = "100%"
  node.styles["height"] = "100%"
  node.styles["background"] = background
  if let radius {
    node.styles["border-radius"] = radius
    node.styles["overflow"] = "hidden"
    node.attributes["data-shape-geometry"] = "css-radius"
  }
  return node
}

private func _shapeSizeIsSquare(_ context: _RenderContext) -> Bool {
  guard _shapeSizeIsKnown(context), let proposal = context._layoutProposal else { return false }
  return proposal.width == proposal.height
}

private func _stableSVGIdentifier(_ value: String) -> String {
  // FNV-1a is deterministic across processes (unlike Swift's randomized
  // Hasher), which keeps gradient IDs stable through incremental updates.
  var hash: UInt64 = 14_695_981_039_346_656_037
  for scalar in value.unicodeScalars {
    hash ^= UInt64(scalar.value)
    hash &*= 1_099_511_628_211
  }
  return String(hash, radix: 16)
}

@MainActor func _svgGradientIdentifier<S: ShapeStyle>(_ style: S, attribute: String, context: _RenderContext) -> String {
  let path = context._compactPathID
  // Deliberately omit the gradient's changing values from the ID.  A stable
  // paint-server node lets Fiber update stop/geometry attributes in place,
  // which preserves browser interpolation for animated gradients.
  let kind = _swiftUIWebTypeName(type(of: style))
  return "paint-gradient-\(_stableSVGIdentifier(kind + "|" + attribute + "|" + path))"
}

private func _svgStopNodes(_ gradient: Gradient, into definition: _RenderNode) {
  for stop in gradient.stops {
    let node = _RenderNode.element("stop")
    node.attributes["offset"] = "\((max(0, min(1, stop.location)) * 100).clean)%"
    _setSVGPaint(node, "stop-color", stop.color.cssValue)
    definition.children.append(node)
  }
}

/// Writes an SVG paint (`fill`, `stroke`, `stop-color`) as a CSS declaration.
///
/// SwiftUI colors are unresolved CSS values here: semantic tokens
/// (`var(--…)`), `light-dark(…)` adaptive colors and `color-mix(…)` opacity
/// variants must be resolved against the element's cascade and active
/// `color-scheme`. SVG presentation attributes are only a CSS-like fallback
/// grammar: engines are not required to substitute `var()` in them, and any
/// stylesheet rule outranks them. The `style` channel is the one every engine
/// evaluates as real CSS, so every paint, including `none` and `url(#…)`
/// paint-server references, uses it consistently. Mixing channels would let a
/// stale attribute and a style disagree after an incremental update.
func _setSVGPaint(_ node: _RenderNode, _ property: String, _ value: String) {
  node.attributes[property] = nil
  node.styles[property] = value
}

@MainActor private func _applySVGShapePaint<S: ShapeStyle>(style: S, stroke: StrokeStyle?, strokeBorder: Bool, fillStyle: FillStyle? = nil, to node: _RenderNode, context: _RenderContext) {
  _applySVGShapePaint(
    paint: style._swiftUIWebCSSValue, stroke: stroke, strokeBorder: strokeBorder, fillStyle: fillStyle, to: node, context: context,
    rectangleBackground: { _resolvedImagePaint(style) == nil ? _paintCSSValue(style) : nil },
    angularGradient: { _angularGradientValue(style) },
    applyStyle: { attribute, path in _applySVGStyle(style, attribute: attribute, to: path, context: context) },
    isSolid: { style._swiftUIWebSolidColor != nil })
}

/// The non-generic part of `_applySVGShapePaint`, so it is not compiled once per style. The closures stand for the
/// style: `rectangleBackground` is its CSS background unless it is an image paint, `applyStyle` paints a path with it.
@MainActor private func _applySVGShapePaint(
  paint: String, stroke: StrokeStyle?, strokeBorder: Bool, fillStyle: FillStyle?, to node: _RenderNode, context: _RenderContext,
  rectangleBackground: () -> String?, angularGradient: () -> AngularGradient?,
  applyStyle: (_ attribute: String, _ path: _RenderNode) -> _RenderNode?, isSolid: () -> Bool
) {
  node.attributes["data-shape-style"] = stroke == nil ? "fill" : "stroke"
  node.attributes["data-shape-stroke-border"] = strokeBorder ? "true" : "false"
  // Preserve the resolved SwiftUI-style value as semantic metadata even when
  // SVG uses a local paint server. This keeps static hosts and diagnostics
  // able to inspect the same gradient/color value without relying on CSS.
  node.attributes["data-shape-paint"] = paint
  // Keep the long-standing rectangle fast path inspectable for static hosts
  // and existing snapshots. The SVG path remains authoritative; for a full
  // rectangle this CSS paint is equivalent and avoids a compatibility churn
  // for callers that inspect the semantic background value.
  // An image paint is painted by its SVG pattern only, so the rectangle never gets a second background image.
  if stroke == nil, node.attributes["data-shape"] == "rectangle", node.attributes["data-trim-from"] == nil, let background = rectangleBackground() {
    node.styles["background"] = background
  }
  guard let path = node.children.first(where: { if case .element("path") = $0.kind { return true }; return false }) else { return }
  if stroke == nil, let angular = angularGradient() {
    _applySVGAngularPaint(angular, path: path, to: node, context: context, fillRule: fillStyle?.isEOFilled == true ? "evenodd" : "nonzero")
    return
  }
  var definition: _RenderNode?
  if let stroke {
    _setSVGPaint(path, "fill", "none")
    path.attributes["stroke-width"] = stroke.lineWidth.clean
    path.attributes["stroke-linecap"] = stroke._svgLineCap
    path.attributes["stroke-linejoin"] = stroke._svgLineJoin
    path.attributes["stroke-miterlimit"] = stroke.miterLimit.clean
    if !stroke.dash.isEmpty { path.attributes["stroke-dasharray"] = stroke.dash.map { $0.clean }.joined(separator: " ") }
    path.attributes["stroke-dashoffset"] = stroke.dashPhase.clean
    if node.attributes["data-shape-fit"] == "intrinsic", node.attributes["data-trim-from"] == nil {
      // Nominal 100x100 viewBox scaled to the real size: keep the line width
      // in CSS pixels instead of scaling it with the circle.
      path.attributes["vector-effect"] = "non-scaling-stroke"
    }
    definition = applyStyle("stroke", path)
  } else {
    _setSVGPaint(path, "stroke", "none")
    path.attributes["fill-rule"] = fillStyle?.isEOFilled == true ? "evenodd" : "nonzero"
    if fillStyle?.isAntialiased == false { path.attributes["shape-rendering"] = "crispEdges" }
    definition = applyStyle("fill", path)
    // The rectangle fast path already paints a solid color as the element's CSS background. The path keeps the
    // paint value (the path stays authoritative for hosts that read it) but must not draw it a second time: a
    // translucent color would otherwise stack on itself (a 45% black comes out near 70%).
    if node.styles["background"] != nil, isSolid() { path.styles["fill-opacity"] = "0" }
  }
  if let definition { node.children.insert(definition, at: 0) }
  if let trimmed = node.attributes["data-trim-from"], let from = Double(trimmed), let to = node.attributes["data-trim-to"].flatMap(Double.init) {
    let span = max(0, to - from)
    path.attributes["pathLength"] = "1"
    path.attributes["stroke-dasharray"] = "\(span.clean) \((1 - span).clean)"
    path.attributes["stroke-dashoffset"] = "\((-from).clean)"
    // Mirror the dash geometry as inline style so a progress change can be
    // interpolated by the browser host (`withAnimation`/`.animation`), which
    // animates style declarations, not presentation attributes.
    path.styles["stroke-dasharray"] = "\(span.clean) \((1 - span).clean)"
    path.styles["stroke-dashoffset"] = "\((-from).clean)"
    _setSVGPaint(path, "fill", "none")
  }
}

@MainActor private func _applySVGStyle<S: ShapeStyle>(_ style: S, attribute: String, to path: _RenderNode, context: _RenderContext) -> _RenderNode? {
  if let paint = _resolvedImagePaint(style) {
    return _svgImagePaintDefinition(style, paint: paint, attribute: attribute, to: path, context: context)
  }
  if let erased = style as? AnyShapeStyle {
    if let linear = erased._linearGradient { return _applySVGStyle(linear, attribute: attribute, to: path, context: context) }
    if let radial = erased._radialGradient { return _applySVGStyle(radial, attribute: attribute, to: path, context: context) }
    if let angular = erased._angularGradient { return _applySVGStyle(angular, attribute: attribute, to: path, context: context) }
    if let elliptical = erased._ellipticalGradient { return _applySVGStyle(elliptical, attribute: attribute, to: path, context: context) }
  }
  if let gradient = style as? LinearGradient {
    let id = _svgGradientIdentifier(style, attribute: attribute, context: context)
    let defs = _RenderNode.element("defs")
    let definition = _RenderNode.element("linearGradient")
    definition.attributes["id"] = id
    definition.attributes["x1"] = "\((gradient.startPoint.x * 100).clean)%"
    definition.attributes["y1"] = "\((gradient.startPoint.y * 100).clean)%"
    definition.attributes["x2"] = "\((gradient.endPoint.x * 100).clean)%"
    definition.attributes["y2"] = "\((gradient.endPoint.y * 100).clean)%"
    _svgStopNodes(gradient.gradient, into: definition)
    defs.children = [definition]
    _setSVGPaint(path, attribute, "url(#\(id))")
    return defs
  }
  if let gradient = style as? RadialGradient {
    let id = _svgGradientIdentifier(style, attribute: attribute, context: context)
    let defs = _RenderNode.element("defs")
    let definition = _RenderNode.element("radialGradient")
    definition.attributes["id"] = id
    let size = _shapeRenderSize(context)
    // User-space coordinates preserve SwiftUI's circular radius when the
    // shape's bounds are not square.  Object-bounding-box percentages would
    // stretch the paint into an ellipse on wide/tall views.
    definition.attributes["gradientUnits"] = "userSpaceOnUse"
    definition.attributes["cx"] = "\((gradient.center.x * size.width).clean)"
    definition.attributes["cy"] = "\((gradient.center.y * size.height).clean)"
    definition.attributes["r"] = "\(max(0, gradient.endRadius).clean)"
    if gradient.startRadius > 0 { definition.attributes["fr"] = "\(gradient.startRadius.clean)" }
    _svgStopNodes(gradient.gradient, into: definition)
    defs.children = [definition]
    _setSVGPaint(path, attribute, "url(#\(id))")
    return defs
  }
  if let gradient = style as? EllipticalGradient {
    let id = _svgGradientIdentifier(style, attribute: attribute, context: context)
    let defs = _RenderNode.element("defs")
    let definition = _RenderNode.element("radialGradient")
    definition.attributes["id"] = id
    // Default objectBoundingBox units: a circle of radius r is an ellipse with radii r × width and r × height, so
    // the fractions scale with the shape's bounds just as SwiftUI's do.
    definition.attributes["cx"] = "\((gradient.center.x * 100).clean)%"
    definition.attributes["cy"] = "\((gradient.center.y * 100).clean)%"
    definition.attributes["r"] = "\(max(0, gradient.endRadiusFraction).clean)"
    if gradient.startRadiusFraction > 0 { definition.attributes["fr"] = "\(gradient.startRadiusFraction.clean)" }
    for stop in gradient.gradient.stops {
      let node = _RenderNode.element("stop")
      node.attributes["offset"] = "\((max(0, min(1, stop.location)) * 100).clean)%"
      _setSVGPaint(node, "stop-color", stop.color.cssValue)
      definition.children.append(node)
    }
    defs.children = [definition]
    _setSVGPaint(path, attribute, "url(#\(id))")
    return defs
  }
  // SVG 1.1 has no conic/AngularGradient primitive. Keep the CSS spelling as
  // a renderer fallback; modern engines can use it as a paint value while
  // Canvas remains the exact path for hosts that expose conic gradients.
  _setSVGPaint(path, attribute, _paintCSSValue(style))
  return nil
}

private func _angularGradientValue<S: ShapeStyle>(_ style: S) -> AngularGradient? {
  if let angular = style as? AngularGradient { return angular }
  return (style as? AnyShapeStyle)?._angularGradient
}

@MainActor private func _applySVGAngularPaint(_ gradient: AngularGradient, path: _RenderNode, to node: _RenderNode, context: _RenderContext, fillRule: String) {
  let size = _shapeRenderSize(context)
  let width = size.width
  let height = size.height
  let centerX = gradient.center.x * width
  let centerY = gradient.center.y * height
  let radius = max(width, height) * 1.5
  let rawSpan = gradient.endAngle.radians - gradient.startAngle.radians
  // SwiftUI treats equal start/end angles as a complete angular cycle for
  // the convenience initializer. Preserve that behavior rather than
  // producing zero-area SVG wedges.
  let span = abs(rawSpan) < 0.0001 ? Double.pi * 2 : rawSpan
  let segmentCount = max(24, min(144, gradient.gradient.stops.count * 24))
  let seed = (node.attributes["data-shape-path"] ?? "") + "|" + context._compactPathID
  let clipID = "angular-clip-\(_stableSVGIdentifier(seed))"
  let defs = _RenderNode.element("defs")
  let clip = _RenderNode.element("clipPath")
  clip.attributes["id"] = clipID
  let clipPath = _RenderNode.element("path")
  clipPath.attributes["d"] = node.attributes["data-shape-path"] ?? ""
  clipPath.attributes["fill-rule"] = fillRule
  clip.children = [clipPath]
  defs.children = [clip]
  node.children.insert(defs, at: 0)

  let group = _RenderNode.element("g")
  group.attributes["clip-path"] = "url(#\(clipID))"
  let direction = span >= 0 ? 1.0 : -1.0
  for index in 0..<segmentCount {
    let t0 = Double(index) / Double(segmentCount)
    let t1 = Double(index + 1) / Double(segmentCount)
    let angle0 = gradient.startAngle.radians + span * t0
    let angle1 = gradient.startAngle.radians + span * t1
    let p0 = (centerX + radius * _swiftUIWebCos(angle0), centerY + radius * _swiftUIWebSin(angle0))
    let p1 = (centerX + radius * _swiftUIWebCos(angle1), centerY + radius * _swiftUIWebSin(angle1))
    let wedge = _RenderNode.element("path")
    wedge.attributes["d"] = "M \(_pathNumber(centerX)) \(_pathNumber(centerY)) L \(_pathNumber(p0.0)) \(_pathNumber(p0.1)) A \(_pathNumber(radius)) \(_pathNumber(radius)) 0 0 \(direction > 0 ? 1 : 0) \(_pathNumber(p1.0)) \(_pathNumber(p1.1)) Z"
    _setSVGPaint(wedge, "fill", _angularColor(gradient.gradient, at: (t0 + t1) / 2))
    group.children.append(wedge)
  }
  // A finite angular span intentionally leaves the remaining region
  // transparent, matching SwiftUI's start/end angle semantics. Keep the
  // normalized span on all groups so hosts can animate it without rebuilding
  // the path list.
  group.attributes["data-angular-span"] = span.clean
  node.children.append(group)
  _setSVGPaint(path, "fill", "none")
  path.attributes["data-angular-gradient"] = gradient._swiftUIWebCSSValue
}

private func _angularColor(_ gradient: Gradient, at location: Double) -> String {
  let stops = gradient.stops.sorted { $0.location < $1.location }
  guard let first = stops.first else { return "transparent" }
  guard let upper = stops.first(where: { $0.location >= location }) else { return stops.last?.color.cssValue ?? first.color.cssValue }
  guard let lower = stops.last(where: { $0.location <= location }), upper.location > lower.location else { return upper.color.cssValue }
  let fraction = (location - lower.location) / (upper.location - lower.location)
  return "color-mix(in srgb, \(lower.color.cssValue) \(((1 - fraction) * 100).clean)%, \(upper.color.cssValue) \((fraction * 100).clean)%)"
}

/// The shape's path at the render size, in the form `data-shape-path` carries.
private func _shapeSVGPathData<S: Shape>(_ shape: S, context: _RenderContext) -> String {
  let size = _shapeRenderSize(context)
  let rect = CGRect(
    origin: CGPoint(x: 0, y: 0),
    size: CGSize(width: size.width, height: size.height)
  )
  return _shapePath(for: shape, in: rect)._svgPathData
}

private func _svgShapeNode<S: Shape>(shape: S, context: _RenderContext) -> _RenderNode {
  _svgShapeNode(
    path: _shapeSVGPathData(shape, context: context), name: _shapeName(shape), isCircle: _isCircleShape(shape),
    adapter: shape._swiftUIWebShapeAdapter, context: context)
}

/// The non-generic part of `_svgShapeNode`, so it is not compiled once per shape.
private func _svgShapeNode(path d: String, name: String, isCircle: Bool, adapter: _ShapeAdapter?, context: _RenderContext) -> _RenderNode {
  let size = _shapeRenderSize(context)
  let node = _RenderNode.element("svg")
  node.classes = ["shape-layer"]
  node.attributes["data-shape"] = name
  node.attributes["data-shape-path"] = d
  node.attributes["viewBox"] = "0 0 \(size.width.clean) \(size.height.clean)"
  if isCircle {
    // A circle fits the shorter side and is centered; "meet" keeps it round
    // when the element is later laid out at a non-square size.
    node.attributes["preserveAspectRatio"] = "xMidYMid meet"
    if !_shapeSizeIsKnown(context) { node.attributes["data-shape-fit"] = "intrinsic" }
  } else {
    node.attributes["preserveAspectRatio"] = "none"
  }
  node.styles["display"] = "block"
  node.styles["width"] = "100%"
  node.styles["height"] = "100%"
  node.styles["overflow"] = "visible"
  let pathNode = _RenderNode.element("path")
  pathNode.attributes["d"] = d
  _setSVGPaint(pathNode, "fill", "none")
  _setSVGPaint(pathNode, "stroke", "none")
  if let adapter {
    node.attributes["data-trim-from"] = adapter.trimFrom.clean
    node.attributes["data-trim-to"] = adapter.trimTo.clean
  }
  node.children = [pathNode]
  return node
}

/// A shape drawn as a view without `fill` or `stroke` is filled with the foreground style, as in SwiftUI (`Circle()` is a
/// filled disc in the text colour, a custom triangle in a label takes the label's colour).
private func _filledWithForeground(_ node: _RenderNode) -> _RenderNode {
  if let path = node.children.first { _setSVGPaint(path, "fill", "currentColor") }
  return node
}

/// Shape style is intentionally a compact CSS value protocol.  It keeps
/// gradients and custom styles extensible while avoiding the large runtime
/// reflection graph used by native SwiftUI's paint resolver.
public protocol ShapeStyle {
  var _swiftUIWebCSSValue: String { get }
  /// Renderer hook: the style as a single solid paint, when it is one
  /// (`Color`, hierarchical levels, `.tint`, ...). Solid styles become CSS
  /// `color`/SVG paint directly; other styles are treated as images.
  var _swiftUIWebSolidColor: Color? { get }
  /// Renderer hook: the shadow a shape painted with this style casts (`ShapeStyle.shadow(_:)`), if any.
  var _swiftUIWebShadow: ShadowStyle? { get }
}

public extension ShapeStyle {
  var _swiftUIWebShadow: ShadowStyle? { nil }
  /// SwiftUI's public protocol does not require application styles to expose
  /// a browser spelling.  Keep the renderer hook optional for third-party
  /// conformances; unknown styles resolve to the inherited current color
  /// while retaining their concrete type in the semantic view tree.
  var _swiftUIWebCSSValue: String { "currentColor" }
  var _swiftUIWebSolidColor: Color? { nil }
}

public struct AnyShapeStyle: ShapeStyle, Hashable, Sendable {
  public let _swiftUIWebCSSValue: String
  /// Renderer-only preservation of concrete paints when a style is erased.
  /// This keeps `AnyShapeStyle(mesh/gradient/color)` behavior equivalent to
  /// passing the original style directly while remaining invisible to
  /// application code.
  @_spi(Renderer) public let _meshGradient: MeshGradient?
  @_spi(Renderer) public let _color: Color?
  @_spi(Renderer) public let _linearGradient: LinearGradient?
  @_spi(Renderer) public let _radialGradient: RadialGradient?
  @_spi(Renderer) public let _angularGradient: AngularGradient?
  package let _imagePaint: _ImagePaintDescriptor?
  package let _ellipticalGradient: EllipticalGradient?
  public var _swiftUIWebSolidColor: Color? { _color }
  public init<S: ShapeStyle>(_ style: S) {
    _swiftUIWebCSSValue = style._swiftUIWebCSSValue
    _meshGradient = (style as? MeshGradient) ?? (style as? AnyShapeStyle)?._meshGradient
    _color = style._swiftUIWebSolidColor
    _linearGradient = (style as? LinearGradient) ?? (style as? AnyShapeStyle)?._linearGradient
    _radialGradient = (style as? RadialGradient) ?? (style as? AnyShapeStyle)?._radialGradient
    _angularGradient = (style as? AngularGradient) ?? (style as? AnyShapeStyle)?._angularGradient
    _ellipticalGradient = (style as? EllipticalGradient) ?? (style as? AnyShapeStyle)?._ellipticalGradient
    _imagePaint = (style as? ImagePaint).map { _ImagePaintDescriptor(source: $0.image.source, sourceRect: $0.sourceRect, scale: $0.scale, allowsRemoteSource: $0.image.allowsRemoteSource) } ?? (style as? AnyShapeStyle)?._imagePaint
  }
}

public struct Gradient: Hashable, Sendable {
  /// SwiftUI's interpolation color-space selector.  Browser hosts currently
  /// resolve both modes through the Canvas renderer (device uses the output
  /// color space; perceptual uses a smooth, gamma-aware interpolation), while
  /// static hosts retain the same semantic value.
  public struct ColorSpace: Hashable, Sendable {
    package let rawValue: String
    package init(_ rawValue: String) { self.rawValue = rawValue }
    public static let device = ColorSpace("device")
    public static let perceptual = ColorSpace("perceptual")
  }

  public struct Stop: Hashable, Sendable {
    public let color: Color
    public let location: Double
    public init(color: Color, location: Double) { self.color = color; self.location = location }
  }
  public let stops: [Stop]
  public init(colors: [Color]) {
    if colors.count < 2 { stops = colors.enumerated().map { Stop(color: $0.element, location: 0) } }
    else { stops = colors.enumerated().map { Stop(color: $0.element, location: Double($0.offset) / Double(colors.count - 1)) } }
  }
  public init(stops: [Gradient.Stop]) { self.stops = stops }

  /// Erases the color space of this gradient, as SwiftUI's `colorSpace(_:)` does.
  public func colorSpace(_ space: Gradient.ColorSpace) -> AnyGradient { AnyGradient(self, colorSpace: space) }
}

/// A gradient with its color space chosen, the value the `GraphicsContext` and
/// `ShapeStyle` gradient overloads take alongside a `Gradient`. The color space
/// is kept as the semantic value; the paint itself is the wrapped `Gradient`.
public struct AnyGradient: Hashable, Sendable {
  public typealias Resolved = Never
  package let gradient: Gradient
  package let space: Gradient.ColorSpace

  public init(_ gradient: Gradient) { self.init(gradient, colorSpace: .device) }

  package init(_ gradient: Gradient, colorSpace: Gradient.ColorSpace) {
    self.gradient = gradient
    self.space = colorSpace
  }

  public func colorSpace(_ space: Gradient.ColorSpace) -> AnyGradient { AnyGradient(gradient, colorSpace: space) }
}

public nonisolated struct LinearGradient: ShapeStyle, Hashable, Sendable {
  public typealias Body = Never
  package let gradient: Gradient
  package let startPoint: UnitPoint
  package let endPoint: UnitPoint
  public nonisolated init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) { self.gradient = gradient; self.startPoint = startPoint; self.endPoint = endPoint }
  public nonisolated init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) { self.init(gradient: Gradient(colors: colors), startPoint: startPoint, endPoint: endPoint) }
  public nonisolated init(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) { self.init(gradient: Gradient(stops: stops), startPoint: startPoint, endPoint: endPoint) }
  public var _swiftUIWebCSSValue: String { _linearGradientCSS(gradient, startPoint: startPoint, endPoint: endPoint) }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _svgShapeNode(shape: Rectangle(), context: context)
    node.classes.append("paint-gradient")
    _applySVGShapePaint(style: self, stroke: nil, strokeBorder: false, fillStyle: nil, to: node, context: context)
    return node
  }
}

public nonisolated struct RadialGradient: ShapeStyle, Hashable, Sendable {
  public typealias Body = Never
  package let gradient: Gradient
  package let center: UnitPoint
  package let startRadius: Double
  package let endRadius: Double
  public nonisolated init(gradient: Gradient, center: UnitPoint, startRadius: Double, endRadius: Double) { self.gradient = gradient; self.center = center; self.startRadius = startRadius; self.endRadius = endRadius }
  public nonisolated init(colors: [Color], center: UnitPoint, startRadius: Double, endRadius: Double) { self.init(gradient: Gradient(colors: colors), center: center, startRadius: startRadius, endRadius: endRadius) }
  public nonisolated init(stops: [Gradient.Stop], center: UnitPoint, startRadius: Double, endRadius: Double) { self.init(gradient: Gradient(stops: stops), center: center, startRadius: startRadius, endRadius: endRadius) }
  public var _swiftUIWebCSSValue: String {
    let center = "\((center.x * 100).clean)% \((center.y * 100).clean)%"
    let radius = endRadius.isFinite && endRadius > 0 ? " \(endRadius.clean)px" : ""
    return "radial-gradient(circle\(radius) at \(center), \(gradient.stops.map { _gradientStopCSS($0) }.joined(separator: ", ")))"
  }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _svgShapeNode(shape: Rectangle(), context: context)
    node.classes.append("paint-gradient")
    _applySVGShapePaint(style: self, stroke: nil, strokeBorder: false, fillStyle: nil, to: node, context: context)
    return node
  }
}

/// Angular (conic) gradients retain the browser's CSS `conic-gradient`
/// spelling as semantic metadata. SVG hosts realize shape fills with a clipped
/// set of retained wedges (Canvas hosts can use the native conic primitive),
/// while static/WASI renderers keep the same SwiftUI-shaped value.
public nonisolated struct AngularGradient: ShapeStyle, Hashable, Sendable {
  public typealias Body = Never
  package let gradient: Gradient
  package let center: UnitPoint
  package let startAngle: Angle
  package let endAngle: Angle

  public nonisolated init(gradient: Gradient, center: UnitPoint, startAngle: Angle = .zero, endAngle: Angle = .zero) {
    self.gradient = gradient
    self.center = center
    self.startAngle = startAngle
    self.endAngle = endAngle
  }

  public nonisolated init(colors: [Color], center: UnitPoint, startAngle: Angle, endAngle: Angle) {
    self.init(gradient: Gradient(colors: colors), center: center, startAngle: startAngle, endAngle: endAngle)
  }

  public nonisolated init(stops: [Gradient.Stop], center: UnitPoint, startAngle: Angle, endAngle: Angle) {
    self.init(gradient: Gradient(stops: stops), center: center, startAngle: startAngle, endAngle: endAngle)
  }

  public nonisolated init(gradient: Gradient, center: UnitPoint, angle: Angle = .zero) {
    self.init(gradient: gradient, center: center, startAngle: angle, endAngle: angle + .degrees(360))
  }

  public nonisolated init(colors: [Color], center: UnitPoint, angle: Angle = .zero) {
    self.init(gradient: Gradient(colors: colors), center: center, angle: angle)
  }

  public nonisolated init(stops: [Gradient.Stop], center: UnitPoint, angle: Angle = .zero) {
    self.init(gradient: Gradient(stops: stops), center: center, angle: angle)
  }

  public var _swiftUIWebCSSValue: String {
    let startDegrees = startAngle.radians * 180 / 3.141592653589793
    let centerValue = "\((center.x * 100).clean)% \((center.y * 100).clean)%"
    return "conic-gradient(from \(startDegrees.clean)deg at \(centerValue), \(gradient.stops.map(_gradientStopCSS).joined(separator: ", ")))"
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _svgShapeNode(shape: Rectangle(), context: context)
    node.classes.append("paint-gradient")
    _applySVGShapePaint(style: self, stroke: nil, strokeBorder: false, fillStyle: nil, to: node, context: context)
    return node
  }
}

/// SwiftUI's elliptical gradient. The ellipse is inscribed in the shape's
/// bounds and centered at `center`; the start and end radii are fractions of
/// the bounds' size, so 0.5 touches the edges. CSS spells the radii as
/// percentages of the box, which keeps the value independent of the layout.
public nonisolated struct EllipticalGradient: ShapeStyle, Hashable, Sendable {
  public typealias Body = Never
  package let gradient: Gradient
  package let center: UnitPoint
  package let startRadiusFraction: Double
  package let endRadiusFraction: Double

  public nonisolated init(gradient: Gradient, center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) {
    self.gradient = gradient
    self.center = center
    self.startRadiusFraction = Double(startRadiusFraction)
    self.endRadiusFraction = Double(endRadiusFraction)
  }

  public nonisolated init(colors: [Color], center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) {
    self.init(gradient: Gradient(colors: colors), center: center, startRadiusFraction: startRadiusFraction, endRadiusFraction: endRadiusFraction)
  }

  public nonisolated init(stops: [Gradient.Stop], center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) {
    self.init(gradient: Gradient(stops: stops), center: center, startRadiusFraction: startRadiusFraction, endRadiusFraction: endRadiusFraction)
  }

  /// A stop's position on the CSS ray, in percent of the end radius. The
  /// start radius maps to 0%, and the first color pads the ray before it.
  private var _cssStopList: [String] {
    var list: [String] = []
    if let first = gradient.stops.first, startRadiusFraction > 0 { list.append("\(first.color.cssValue) 0%") }
    for stop in gradient.stops {
      let fraction = startRadiusFraction + stop.location * (endRadiusFraction - startRadiusFraction)
      let position = endRadiusFraction > 0 ? fraction / endRadiusFraction * 100 : stop.location * 100
      list.append("\(stop.color.cssValue) \(position.clean)%")
    }
    return list
  }

  public var _swiftUIWebCSSValue: String {
    let radius = max(0, endRadiusFraction * 100).clean
    let centerValue = "\((center.x * 100).clean)% \((center.y * 100).clean)%"
    return "radial-gradient(ellipse \(radius)% \(radius)% at \(centerValue), \(_cssStopList.joined(separator: ", ")))"
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _svgShapeNode(shape: Rectangle(), context: context)
    node.classes.append("paint-gradient")
    _applySVGShapePaint(style: self, stroke: nil, strokeBorder: false, fillStyle: nil, to: node, context: context)
    return node
  }
}

public extension ShapeStyle where Self == EllipticalGradient {
  static func ellipticalGradient(_ gradient: Gradient, center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) -> EllipticalGradient {
    EllipticalGradient(gradient: gradient, center: center, startRadiusFraction: startRadiusFraction, endRadiusFraction: endRadiusFraction)
  }

  static func ellipticalGradient(colors: [Color], center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) -> EllipticalGradient {
    EllipticalGradient(colors: colors, center: center, startRadiusFraction: startRadiusFraction, endRadiusFraction: endRadiusFraction)
  }

  static func ellipticalGradient(stops: [Gradient.Stop], center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) -> EllipticalGradient {
    EllipticalGradient(stops: stops, center: center, startRadiusFraction: startRadiusFraction, endRadiusFraction: endRadiusFraction)
  }

  static func ellipticalGradient(_ gradient: AnyGradient, center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) -> EllipticalGradient {
    EllipticalGradient(gradient: gradient.gradient, center: center, startRadiusFraction: startRadiusFraction, endRadiusFraction: endRadiusFraction)
  }
}

public extension ShapeStyle where Self == AngularGradient {
  static func angularGradient(_ gradient: Gradient, center: UnitPoint, startAngle: Angle, endAngle: Angle) -> AngularGradient {
    AngularGradient(gradient: gradient, center: center, startAngle: startAngle, endAngle: endAngle)
  }

  static func angularGradient(colors: [Color], center: UnitPoint, startAngle: Angle, endAngle: Angle) -> AngularGradient {
    AngularGradient(colors: colors, center: center, startAngle: startAngle, endAngle: endAngle)
  }

  static func angularGradient(stops: [Gradient.Stop], center: UnitPoint, startAngle: Angle, endAngle: Angle) -> AngularGradient {
    AngularGradient(stops: stops, center: center, startAngle: startAngle, endAngle: endAngle)
  }

  static func conicGradient(_ gradient: Gradient, center: UnitPoint, angle: Angle = .zero) -> AngularGradient {
    AngularGradient(gradient: gradient, center: center, angle: angle)
  }

  static func conicGradient(colors: [Color], center: UnitPoint, angle: Angle = .zero) -> AngularGradient {
    AngularGradient(colors: colors, center: center, angle: angle)
  }

  static func conicGradient(stops: [Gradient.Stop], center: UnitPoint, angle: Angle = .zero) -> AngularGradient {
    AngularGradient(stops: stops, center: center, angle: angle)
  }

  static func angularGradient(_ gradient: AnyGradient, center: UnitPoint = .center, startAngle: Angle, endAngle: Angle) -> AngularGradient {
    AngularGradient(gradient: gradient.gradient, center: center, startAngle: startAngle, endAngle: endAngle)
  }

  static func conicGradient(_ gradient: AnyGradient, center: UnitPoint = .center, angle: Angle = .zero) -> AngularGradient {
    AngularGradient(gradient: gradient.gradient, center: center, angle: angle)
  }
}

/// Apple's `ShapeView`: a view that is a painted shape. `Shape.fill(_:style:)` returns one, and the
/// `stroke`/`strokeBorder` members of `ShapeView` stack a further paint over the same shape.
public nonisolated protocol ShapeView<Content>: View {
  associatedtype Content: Shape
  nonisolated var shape: Content { get }
}

public extension ShapeView {
  /// Fills the shape again, painting it over this view's paint.
  nonisolated func fill<S: ShapeStyle>(_ content: S = .foreground, style: FillStyle = FillStyle()) -> FillShapeView<Content, S, Self> {
    FillShapeView(shape: shape, style: content, fillStyle: style, background: self)
  }

  nonisolated func stroke<S: ShapeStyle>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> StrokeShapeView<Content, S, Self> {
    StrokeShapeView(shape: shape, style: content, strokeStyle: style, isAntialiased: antialiased, background: self)
  }

  nonisolated func stroke<S: ShapeStyle>(_ content: S, lineWidth: Double = 1, antialiased: Bool = true) -> StrokeShapeView<Content, S, Self> {
    stroke(content, style: StrokeStyle(lineWidth: lineWidth), antialiased: antialiased)
  }
}

public extension ShapeView where Content: InsettableShape {
  nonisolated func strokeBorder<S: ShapeStyle>(_ content: S = .foreground, style: StrokeStyle, antialiased: Bool = true) -> StrokeBorderShapeView<Content, S, Self> {
    StrokeBorderShapeView(shape: shape, style: content, strokeStyle: style, isAntialiased: antialiased, background: self)
  }

  nonisolated func strokeBorder<S: ShapeStyle>(_ content: S = .foreground, lineWidth: Double = 1, antialiased: Bool = true) -> StrokeBorderShapeView<Content, S, Self> {
    strokeBorder(content, style: StrokeStyle(lineWidth: lineWidth), antialiased: antialiased)
  }
}

/// The paint of one shape: a fill, or a stroke when `stroke` is set. Apple's `Shape.fill` returns it.
public nonisolated struct _ShapeView<S: Shape, Style: ShapeStyle>: ShapeView {
  public typealias Body = Never
  // Internal storage. The name must not be `stroke`: a stored member would shadow
  // `View.stroke(_:lineWidth:)`, which Apple's `.fill(_:).stroke(_:lineWidth:)` chain uses.
  public nonisolated let shape: S
  let style: Style
  let strokeStyle: StrokeStyle?
  let strokeBorder: Bool
  let fillStyle: FillStyle?
  public init(shape: S, style: Style, stroke: StrokeStyle?, strokeBorder: Bool = false, fillStyle: FillStyle? = nil) {
    self.shape = shape; self.style = style; self.strokeStyle = stroke; self.strokeBorder = strokeBorder; self.fillStyle = fillStyle
  }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    guard S._swiftUIWebAnimates else { return _renderShape(in: context) }
    let (style, stroke, border, fill) = (self.style, strokeStyle, strokeBorder, fillStyle)
    return AnyView(_ownerBoundaryOf: _AnimatedShape(shape: shape) { shape, context in
      _ShapeView(shape: shape, style: style, stroke: stroke, strokeBorder: border, fillStyle: fill)._renderShape(in: context)
    })._render(in: context)
  }

  @MainActor func _renderShape(in context: _RenderContext) -> _RenderNode {
    // A stroked outline (`stroke(style:)`) paints its stroke when it is filled.
    let effectiveStroke = strokeStyle ?? shape._swiftUIWebStrokeStyle
    if effectiveStroke == nil, let mesh = _meshGradientValue(style) {
      let node = mesh._render(in: context)
      node.attributes["data-shape"] = _shapeName(shape)
      node.attributes["data-shape-style"] = "fill"
      node.styles["border-radius"] = _shapeRadius(shape)
      node.styles["overflow"] = "hidden"
      return node
    }
    if effectiveStroke == nil, let solid = _cssSolidFillNode(shape: shape, style: style, fillStyle: fillStyle, context: context) {
      return solid
    }
    let node = _svgShapeNode(shape: shape, context: context)
    _applySVGShapePaint(style: style, stroke: effectiveStroke, strokeBorder: strokeBorder, fillStyle: fillStyle, to: node, context: context)
    // A rounded shape's corners are realized in CSS. A stretched fallback SVG
    // viewBox scales both the corner radius and the line width after layout.
    if let rounded = _cssRoundedShape(shape) {
      _realizeRoundedShapeInCSS(rounded, solidColor: style._swiftUIWebSolidColor, stroke: effectiveStroke, on: node, context: context)
    }
    if let probe = context._strokeOverlayProbe, let stroke = effectiveStroke,
       let record = _solidStrokeRecord(shape, style: style, stroke: stroke, isBorder: strokeBorder, path: node.attributes["data-shape-path"]) {
      probe.strokes.append(record)
    }
    return node
  }
}

/// Realizes a rounded shape's corners in CSS: the end of `_ShapeView._render`, out of the generic type so it is compiled
/// once rather than once per shape and style.
@MainActor private func _realizeRoundedShapeInCSS(_ rounded: _CSSRoundedShape, solidColor: Color?, stroke effectiveStroke: StrokeStyle?, on node: _RenderNode, context: _RenderContext) {
  if effectiveStroke == nil {
    _realizeRoundedFillInCSS(rounded, on: node, size: _shapeRenderSize(context))
  } else if let stroke = effectiveStroke, let solidColor, stroke.dash.isEmpty, stroke.lineWidth.isFinite, stroke.lineWidth >= 0 {
    // A centered stroke is a CSS outline offset by half its width (plus
    // the strokeBorder inset): layout-neutral, with circular corners.
    let offset = (rounded.inset + stroke.lineWidth / 2).clean
    node.styles["border-radius"] = rounded.radius
    node.styles["outline"] = "\(stroke.lineWidth.clean)px solid \(solidColor._swiftUIWebCSSValue)"
    node.styles["outline-offset"] = "-\(offset)px"
    node.attributes["data-shape-geometry"] = "css-radius"
    for child in node.children {
      if case .element("path") = child.kind { child.styles["display"] = "none" }
    }
  }
}

/// Apple's `FillShapeView`: a fill painted over `background`.
public nonisolated struct FillShapeView<Content: Shape, Style: ShapeStyle, Background: View>: ShapeView {
  public typealias Body = Never
  public nonisolated var shape: Content
  public nonisolated var style: Style
  public nonisolated var fillStyle: FillStyle
  public nonisolated var background: Background
  public nonisolated init(shape: Content, style: Style, fillStyle: FillStyle, background: Background) {
    self.shape = shape; self.style = style; self.fillStyle = fillStyle; self.background = background
  }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    _ShapeView(shape: shape, style: style, stroke: nil, fillStyle: fillStyle)._stackOver(background)._render(in: context)
  }
}

/// Apple's `StrokeShapeView`: a stroke centered on the shape's path, painted over `background`.
public nonisolated struct StrokeShapeView<Content: Shape, Style: ShapeStyle, Background: View>: ShapeView {
  public typealias Body = Never
  public nonisolated var shape: Content
  public nonisolated var style: Style
  public nonisolated var strokeStyle: StrokeStyle
  public nonisolated var isAntialiased: Bool
  public nonisolated var background: Background
  public nonisolated init(shape: Content, style: Style, strokeStyle: StrokeStyle, isAntialiased: Bool, background: Background) {
    self.shape = shape; self.style = style; self.strokeStyle = strokeStyle; self.isAntialiased = isAntialiased; self.background = background
  }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    _ShapeView(shape: shape, style: style, stroke: strokeStyle)._stackOver(background)._render(in: context)
  }
}

/// Apple's `StrokeBorderShapeView`: a stroke drawn inside the shape's bounds, painted over `background`.
public nonisolated struct StrokeBorderShapeView<Content: InsettableShape, Style: ShapeStyle, Background: View>: ShapeView {
  public typealias Body = Never
  public var shape: Content
  public nonisolated var style: Style
  public nonisolated var strokeStyle: StrokeStyle
  public nonisolated var isAntialiased: Bool
  public nonisolated var background: Background
  public nonisolated init(shape: Content, style: Style, strokeStyle: StrokeStyle, isAntialiased: Bool, background: Background) {
    self.shape = shape; self.style = style; self.strokeStyle = strokeStyle; self.isAntialiased = isAntialiased; self.background = background
  }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let inset = shape.inset(by: CGFloat(max(0, strokeStyle.lineWidth) / 2))
    return _ShapeView(shape: inset, style: style, stroke: strokeStyle, strokeBorder: true)._stackOver(background)._render(in: context)
  }
}

private extension View {
  /// The paint over `background`. An `EmptyView` background leaves the paint alone.
  @MainActor func _stackOver<Background: View>(_ background: Background) -> some View {
    _ShapeOverBackground(paint: self, background: background)
  }
}

/// Stacks a shape paint over a background paint; an `EmptyView` background renders the paint alone.
private nonisolated struct _ShapeOverBackground<Paint: View, Background: View>: View {
  typealias Body = Never
  let paint: Paint
  let background: Background
  @MainActor func _render(in context: _RenderContext) -> _RenderNode {
    if background is EmptyView { return paint._render(in: context) }
    return ZStack {
      background
      paint
    }._render(in: context)
  }
}

private func _shapeRadius<S: Shape>(_ shape: S) -> String {
  if shape is Circle || shape is Capsule || shape is DefaultGlassEffectShape { return "9999px" }
  if let rounded = shape as? RoundedRectangle { return "\(max(0, rounded.cornerRadius - rounded._insetAmount).clean)px" }
  if let uneven = shape as? UnevenRoundedRectangle { return uneven._cssBorderRadius }
  return "0"
}

/// CSS corner declarations for a CSS-realized shape boundary. Uneven
/// rectangles use logical per-corner properties so leading/trailing follow
/// the layout direction.
func _shapeRadiusStyles<S: Shape>(_ shape: S) -> _NodeValues {
  if let adapter = shape._swiftUIWebShapeAdapter { return adapter.baseRadiusStyles }
  if let uneven = shape as? UnevenRoundedRectangle { return uneven._cssCornerStyles }
  return ["border-radius": _shapeRadius(shape)]
}

private func _applyShapeRadius<S: Shape>(_ shape: S, to node: _RenderNode) {
  for (key, value) in _shapeRadiusStyles(shape) { node.styles[key] = value }
}

private func _paintNode(style: String, shape: String) -> _RenderNode {
  let node = _RenderNode.element("div"); node.classes = ["shape-layer"]
  node.attributes["data-shape"] = shape; node.attributes["data-shape-style"] = "fill"
  node.styles["background"] = style
  return node
}

private func _materialValue<Style: ShapeStyle>(_ style: Style) -> Material? {
  if let material = style as? Material { return material }
  guard let erased = style as? AnyShapeStyle else { return nil }
  return [Material.ultraThin, .thin, .regular, .thick, .ultraThick]
    .first { $0._swiftUIWebCSSValue == erased._swiftUIWebCSSValue }
}

private func _applyMaterialBackdrop<Style: ShapeStyle>(_ style: Style, to node: _RenderNode) {
  guard let material = _materialValue(style) else { return }
  let backdropFilter = _materialBackdropFilter(material)
  node.styles["backdrop-filter"] = backdropFilter
  node.styles["-webkit-backdrop-filter"] = backdropFilter
  node.attributes["data-background-material"] = material.rawValue
}

private func _gradientStopCSS(_ stop: Gradient.Stop) -> String {
  "\(stop.color.cssValue) \((stop.location * 100).clean)%"
}

private func _linearGradientCSS(_ gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) -> String {
  let direction: String
  if startPoint == .top && endPoint == .bottom { direction = "to bottom" }
  else if startPoint == .bottom && endPoint == .top { direction = "to top" }
  else if startPoint == .leading && endPoint == .trailing { direction = "to right" }
  else if startPoint == .trailing && endPoint == .leading { direction = "to left" }
  else if startPoint == .topLeading && endPoint == .bottomTrailing { direction = "to bottom right" }
  else if startPoint == .topTrailing && endPoint == .bottomLeading { direction = "to bottom left" }
  else {
    let dx = endPoint.x - startPoint.x
    let dy = endPoint.y - startPoint.y
    let degrees = _swiftUIWebAtan2(dy, dx) * 180 / 3.141592653589793 + 90
    direction = "\(degrees.clean)deg"
  }
  return "linear-gradient(\(direction), \(gradient.stops.map(_gradientStopCSS).joined(separator: ", ")))"
}

/// The content layer of a painted background. The modified view (including a
/// `.padding()` boundary) is kept intact: `.padding().background(_:in:)` must
/// paint the padded bounds, and the layout only honors padding
/// through its semantic padding node, not through CSS padding moved onto the
/// background container.
private func _backgroundContent(_ node: _RenderNode) -> (content: _RenderNode, styles: _NodeValues, attributes: _NodeValues) {
  let original = node.cloneSharingChildren()
  original.key = nil
  return (original, .init(), .init())
}

/// Group/ForEach are transparent: a modifier that restructures its content applies to each element. Returns whether
/// `node` was such a group (and the modifier has therefore already been applied to its elements).
@MainActor func _applyPerElement(_ node: _RenderNode, context: _RenderContext, _ body: (_RenderNode, inout _RenderContext) -> Void) -> Bool {
  guard node.kind == .fragment else { return false }
  for (index, child) in node.children.enumerated() where !child.isEmpty {
    var childContext = context.child(_FiberKey("element-\(index)"))
    body(child, &childContext)
  }
  return true
}

package nonisolated struct ShapeBackgroundModifier<Style: ShapeStyle, Clip: Shape>: ViewModifier {
  package let style: Style
  package let clip: Clip
  package init(style: Style, clip: Clip) { self.style = style; self.clip = clip }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    if _applyPerElement(node, context: context, { self._apply(to: $0, context: &$1) }) { return }
    let content = _backgroundContent(node)
    let original = content.content
    let background: _RenderNode
    if let mesh = _meshGradientValue(style) {
      background = _meshBackgroundNode(mesh, context: context.child(_FiberKey("background-mesh-gradient")))
    } else {
      let backgroundContext = _decoratedLayerContext(original, context, key: "background-shape")
      background = _svgShapeNode(shape: clip, context: backgroundContext)
      _applySVGShapePaint(style: style, stroke: nil, strokeBorder: false, fillStyle: nil, to: background, context: backgroundContext)
      if let rounded = _cssRoundedShape(clip) {
        _realizeRoundedFillInCSS(rounded, on: background, size: _shapeRenderSize(backgroundContext))
      }
    }
    _applyShapeRadius(clip, to: background)
    _applyMaterialBackdrop(style, to: background)
    if let shadow = style._swiftUIWebShadow, !shadow.isInner {
      background.styles["filter"] = "drop-shadow(\(shadow.x)px \(shadow.y)px \(shadow.radius)px \(shadow.color.cssValue))"
    }
    background.attributes["data-background-shape"] = _shapeName(clip)
    node.kind = .element("div")
    node.text = nil
    node.attributes = content.attributes
    node.styles = content.styles
    node.classes = ["backdrop-layer"]
    node.children = [background, original]
    node.events = .init()
  }
}

/// ShapeStyle background without an explicit clipping shape.  The content is
/// retained as the second layer so state/event metadata stays attached to the
/// original Fiber rather than being replaced by a CSS-only wrapper.
package nonisolated struct ShapeStyleBackgroundModifier<Style: ShapeStyle>: ViewModifier {
  package let style: Style
  package init(style: Style) { self.style = style }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    if _applyPerElement(node, context: context, { self._apply(to: $0, context: &$1) }) { return }
    if let mesh = _meshGradientValue(style) {
      let content = _backgroundContent(node)
      let original = content.content
      let background = _meshBackgroundNode(mesh, context: context.child(_FiberKey("background-mesh-gradient")))
      node.kind = .element("div")
      node.text = nil
      node.attributes = content.attributes
      node.styles = content.styles
      node.classes = ["backdrop-layer"]
      node.children = [background, original]
      node.events = .init()
      return
    }
    // A background already on the element was applied inside this one: SwiftUI draws this one behind it. The inner paint
    // becomes an image layer over this one, which takes the element's color (or the bottom image layer).
    if let inner = node.styles["background-color"] ?? node.styles["background"], !inner.isEmpty {
      let layer = { (paint: String) in _isCSSImage(paint) ? paint : "linear-gradient(\(paint), \(paint))" }
      let innerLayer = layer(inner)
      node.styles["background"] = nil
      node.styles["background-color"] = nil
      if style._swiftUIWebSolidColor != nil {
        node.styles["background-image"] = innerLayer
        node.styles["background-color"] = _paintCSSValue(style)
      } else {
        node.styles["background-image"] = "\(innerLayer), \(layer(_paintCSSValue(style)))"
      }
      _applyMaterialBackdrop(style, to: node)
      return
    }
    // A solid paint (`Color`, hierarchical levels, `.tint`) is a background color, as `background(_:)` always was;
    // other styles use the `background` shorthand for their image or gradient paint.
    if style._swiftUIWebSolidColor != nil {
      node.styles["background-color"] = _paintCSSValue(style)
    } else {
      node.styles["background"] = _paintCSSValue(style)
      _applyImagePaintMarkers(style, to: node)
    }
    node.attributes["data-background-style"] = style._swiftUIWebCSSValue
    _applyMaterialBackdrop(style, to: node)
  }
}

/// Whether a CSS paint is an image (a gradient or a URL), which a background layer takes as it is; a color is not. Byte
/// matching, as the Embedded build has no Foundation substring search.
func _isCSSImage(_ paint: String) -> Bool {
  let bytes = Array(paint.utf8)
  for needle in [Array("gradient(".utf8), Array("url(".utf8)] where bytes.count >= needle.count {
    for start in 0...(bytes.count - needle.count) where bytes[start] == needle[0] {
      if Array(bytes[start..<(start + needle.count)]) == needle { return true }
    }
  }
  return false
}

private func _meshBackgroundNode(_ mesh: MeshGradient, context: _RenderContext) -> _RenderNode {
  let node = mesh._render(in: context)
  node.styles["width"] = "100%"
  node.styles["height"] = "100%"
  node.styles["min-width"] = "0"
  node.styles["min-height"] = "0"
  node.styles["pointer-events"] = "none"
  node.attributes["data-background-mesh-gradient"] = "true"
  return node
}

private func _meshGradientValue<Style: ShapeStyle>(_ style: Style) -> MeshGradient? {
  if let mesh = style as? MeshGradient { return mesh }
  return (style as? AnyShapeStyle)?._meshGradient
}

package nonisolated struct ClipShapeModifier<Clip: Shape>: ViewModifier {
  package let clip: Clip
  package let style: FillStyle
  package init(clip: Clip, style: FillStyle = FillStyle()) { self.clip = clip; self.style = style }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.styles["overflow"] = "hidden"
    _applyShapeRadius(clip, to: node)
    node.attributes["data-clip-shape"] = _shapeName(clip)
    let rect = CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: 100, height: 100))
    let path = _shapePath(for: clip, in: rect)._svgPathData
    if !path.isEmpty {
      node.attributes["data-clip-path"] = path
      if clip is Path || _shapeName(clip) == "shape" {
        // CSS `path()` uses CSS-pixel coordinates and therefore does not
        // scale with a responsive element. A data SVG mask has a normalized
        // viewBox, preserving custom Shape geometry across resizing while
        // retaining the path in metadata for non-browser hosts.
        let maskURI = _svgMaskDataURI(path: path, fillRule: style.isEOFilled ? "evenodd" : "nonzero")
        node.styles["mask-image"] = "url(\"\(maskURI)\")"
        node.styles["-webkit-mask-image"] = "url(\"\(maskURI)\")"
        node.styles["mask-size"] = "100% 100%"
        node.styles["-webkit-mask-size"] = "100% 100%"
        node.styles["mask-repeat"] = "no-repeat"
        node.styles["-webkit-mask-repeat"] = "no-repeat"
        node.attributes["data-clip-backend"] = "svg-mask"
      }
    }
    if style.isEOFilled { node.attributes["data-clip-fill-rule"] = "evenodd" }
  }
}

private struct _ContentShapeDescriptor {
  let name: String
  let styles: _NodeValues
}

private func _contentShapeDescriptor<ShapeValue>(_ shape: ShapeValue) -> _ContentShapeDescriptor {
  if shape is Circle {
    return _ContentShapeDescriptor(name: "circle", styles: ["clip-path": "circle(50% at 50% 50%)"])
  }
  if shape is Capsule || shape is DefaultGlassEffectShape {
    return _ContentShapeDescriptor(name: "capsule", styles: ["clip-path": "inset(0 round 9999px)"])
  }
  if shape is Rectangle {
    return _ContentShapeDescriptor(name: "rectangle", styles: .init())
  }
  if let rounded = shape as? RoundedRectangle {
    return _ContentShapeDescriptor(
      name: "rounded-rectangle",
      styles: [
        "border-radius": "\(rounded.cornerRadius.clean)px",
        "clip-path": "inset(0 round \(rounded.cornerRadius.clean)px)"
      ]
    )
  }
  if let uneven = shape as? UnevenRoundedRectangle {
    var styles = uneven._cssCornerStyles
    styles["clip-path"] = "inset(0 round \(uneven._cssBorderRadius))"
    return _ContentShapeDescriptor(name: "uneven-rounded-rectangle", styles: styles)
  }
  #if hasFeature(Embedded)
  return _ContentShapeDescriptor(name: "custom", styles: .init())
  #else
  return _ContentShapeDescriptor(name: _swiftUIWebTypeName(ShapeValue.self), styles: .init())
  #endif
}

/// Propagates enabled state to descendants and emits native disabled
/// attributes on controls and semantic elements.
package nonisolated struct DisabledModifier: ViewModifier {
  package let disabled: Bool
  package init(disabled: Bool) { self.disabled = disabled }
  @MainActor package func _modifyContext(_ context: inout _RenderContext) {
    // Disabled state is inherited. A child may opt out of disabling itself,
    // but it must not re-enable interaction that an ancestor disabled.
    if disabled { context.environment.isEnabled = false }
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    guard disabled else { return }
    node.attributes["disabled"] = "disabled"
    node.attributes["aria-disabled"] = "true"
    if case .element("a") = node.kind {
      node.attributes.removeValue(forKey: "href")
      node.attributes["tabindex"] = "-1"
      node.events["click"] = _EventHandler(name: "click", action: {}, preventsDefault: true)
    }
  }
}

/// The placement values intentionally describe semantic regions rather than
/// browser widgets.  A host stylesheet can position the same search field in
/// a navigation drawer, sidebar, or its automatic location.
public enum SearchFieldPlacement: Hashable, Sendable {
  case automatic
  case navigationBarDrawer
  case sidebar

  public static func navigationBarDrawer(displayMode: SearchFieldPlacement.NavigationBarDrawerDisplayMode) -> Self {
    _ = displayMode
    return .navigationBarDrawer
  }

  /// SwiftUI's `SearchFieldPlacement.NavigationBarDrawerDisplayMode`.
  public struct NavigationBarDrawerDisplayMode: Hashable, Sendable {
    private let value: UInt8
    private init(_ value: UInt8) { self.value = value }
    public static let automatic = NavigationBarDrawerDisplayMode(0)
    public static let always = NavigationBarDrawerDisplayMode(1)
  }

  /// The CSS spelling of each case; SwiftUI does not expose a raw value.
  var rawValue: String {
    switch self {
    case .automatic: "automatic"
    case .navigationBarDrawer: "navigationBarDrawer"
    case .sidebar: "sidebar"
    }
  }
}

package nonisolated struct SearchableModifier: ViewModifier {
  package let text: Binding<String>
  package let placement: SearchFieldPlacement
  package let prompt: String

  package init(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: String = "Search") {
    self.text = text
    self.placement = placement
    self.prompt = prompt
  }

  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let original = node.cloneSharingChildren()
    let field = _RenderNode.element("input")
    field.classes = ["field-input", "search-input"]
    field.attributes["type"] = "search"
    field.attributes["placeholder"] = prompt
    field.attributes["aria-label"] = prompt
    field.attributes["data-search-placement"] = placement.rawValue
    field.attributes["value"] = text.wrappedValue
    if context.environment.isEnabled {
      field.events["input"] = _EventHandler(name: "input", action: { text.wrappedValue = $0 })
    } else {
      field.attributes["disabled"] = "disabled"
      field.attributes["aria-disabled"] = "true"
    }

    // In a navigation stack the field is an item of the bar, at its trailing end after the screen's own items, as iPadOS
    // places an automatic search field (Food Truck's Orders and Donuts). The stack collects it with the screen's
    // toolbars; when only the screen renders again, the field it placed stays and keeps the text the input holds.
    if placement == .automatic, let navigation = context.navigationContext {
      field.attributes["role"] = "searchbox"
      let item = _RenderNode.element("div")
      item.classes = ["toolbar-item", "search-toolbar-item"]
      item.attributes["data-toolbar-placement"] = ToolbarItemPlacement.navigationBarTrailing.rawValue
      item.children = [field]
      let toolbar = _RenderNode.fragment()
      toolbar.attributes["role"] = "toolbar"
      toolbar.children = [item]
      _renderRegistersWithAncestors()
      if navigation.collectingToolbars { navigation.toolbarSink.append(toolbar) }
      return
    }
    node.kind = .element("div")
    node.text = nil
    node.attributes = ["role": "search", "data-searchable": "true"]
    node.styles = .init()
    node.classes = ["searchable"]
    node.children = [field, original]
    node.events = .init()
  }
}

/// The context a background or overlay renders its content in. SwiftUI offers that content the size of the view it
/// decorates; a frame applied before the modifier records its size on its node (`data-frame-w`/`data-frame-h`), not in
/// the modifier's context, so the content of `.background(Circle())` on a 64-point frame must take the 64-point size here.
/// The node that carries the frame of a decorated view: the view itself, or the content inside the background and
/// overlay wrappers already around it (`.frame(...).background(..., in: Circle()).overlay(...)` decorates the
/// background's wrapper, whose content is the frame).
@MainActor private func _framedContent(_ node: _RenderNode) -> _RenderNode {
  var current = node
  while current.attributes["data-frame-w"] == nil, current.attributes["data-frame-h"] == nil {
    if current.classes.contains("backdrop-layer"), let content = current.children.last {
      current = content
    } else if current.classes.contains("overlay-layer"), let content = current.children.first {
      current = content
    } else {
      break
    }
  }
  return current
}

@MainActor private func _decoratedLayerContext(_ node: _RenderNode, _ context: _RenderContext, key: String) -> _RenderContext {
  var layer = context.child(_FiberKey(key))
  // A background or overlay is offered the size of the view it decorates, as in SwiftUI: a shape in it is drawn at
  // the frame's size, not at the window's.
  let framed = _framedContent(node)
  let width = framed.attributes["data-frame-w"].flatMap(Double.init)
  let height = framed.attributes["data-frame-h"].flatMap(Double.init)
  if width != nil || height != nil {
    let inherited = context._layoutProposal
    layer._layoutProposal = ProposedViewSize(width: width.map { CGFloat($0) } ?? inherited?.width, height: height.map { CGFloat($0) } ?? inherited?.height)
  }
  return layer
}

package nonisolated struct BackgroundModifier<Background: View>: ViewModifier {
  package let content: () -> Background
  package let alignment: Alignment
  /// `listRowBackground`: on a `Section` the background fills the rows' group, not the header and footer.
  package let isListRowBackground: Bool
  package init(content: @escaping () -> Background, alignment: Alignment = .center) {
    self.init(content: content, alignment: alignment, isListRowBackground: false)
  }
  package init(content: @escaping () -> Background, alignment: Alignment, isListRowBackground: Bool) {
    self.content = content; self.alignment = alignment; self.isListRowBackground = isListRowBackground
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    if isListRowBackground, let card = Self.sectionCard(in: node) { decorate(card, key: "background", context: context); return }
    // On a Group/ForEach the background decorates each element, as in SwiftUI.
    if node.kind == .fragment {
      for (index, child) in node.children.enumerated() where !child.isEmpty { decorate(child, key: "background-\(index)", context: context) }
      return
    }
    decorate(node, key: "background", context: context)
  }

  @MainActor private static func sectionCard(in node: _RenderNode) -> _RenderNode? {
    for child in node.children {
      if child.classes.contains("section-card") { return child }
      if child.classes.contains("section-block"), let card = child.children.first(where: { $0.classes.contains("section-card") }) { return card }
    }
    return nil
  }

  @MainActor private func decorate(_ node: _RenderNode, key: String, context: _RenderContext) {
    let layer = AnyView(content())._render(in: _decoratedLayerContext(node, context, key: key))
    // Preserve the base slot even when conditional decoration is empty.
    // Removing this wrapper shifts Fiber identity and cancels base tasks.
    let original = _semanticWrap(node, kind: "background")
    node.styles["display"] = "grid"
    node.styles["place-items"] = alignment.cssValue
    for (key, value) in _semanticAlignment(alignment) { node.attributes[key] = value }
    node.children = [layer, original]
  }
}

/// A solid stroke of a rectangle, rounded rectangle or capsule that fills the shape's bounds, as an overlay paints it.
struct _SolidStrokeRecord {
  /// The SVG path the stroke was painted with, which identifies the stroke layer in the overlay's render.
  let path: String
  let lineWidth: Double
  /// `strokeBorder`: the line lies inside the bounds. Otherwise it is centered on them.
  let isBorder: Bool
  /// The corner radius of the stroked shape (nil for a rectangle).
  let radius: String?
  let color: String
}

/// Collects the solid strokes that an overlay paints while it renders its content.
@MainActor final class _StrokeOverlayProbe {
  var strokes: [_SolidStrokeRecord] = []
}

/// The stroke as a solid CSS color on the shape's bounds, or nil. Dashes, gradients, trims, other shapes and any inset
/// beyond what `strokeBorder` adds keep the SVG path.
@MainActor private func _solidStrokeRecord<S: Shape, Style: ShapeStyle>(_ shape: S, style: Style, stroke: StrokeStyle, isBorder: Bool, path: String?) -> _SolidStrokeRecord? {
  guard let path, let color = style._swiftUIWebSolidColor, _resolvedImagePaint(style) == nil,
        _angularGradientValue(style) == nil, _meshGradientValue(style) == nil,
        shape._swiftUIWebShapeAdapter == nil, stroke.dash.isEmpty,
        stroke.lineWidth.isFinite, stroke.lineWidth > 0,
        // A whole-pixel width keeps the half-width whole too. A box shadow antialiases a fractional spread differently
        // from the SVG stroke (a 1.5 pt ring comes out lighter), so those strokes keep the SVG.
        stroke.lineWidth == stroke.lineWidth.rounded() else { return nil }
  let radius: String?
  let inset: Double
  if let rectangle = shape as? Rectangle {
    radius = nil
    inset = rectangle._insetAmount
  } else if let rounded = _cssRoundedShape(shape) {
    radius = rounded.radius
    inset = rounded.inset
  } else {
    return nil
  }
  // `strokeBorder` insets the shape by half its line width; any other inset means the stroke does not fill the bounds.
  guard abs(inset - (isBorder ? stroke.lineWidth / 2 : 0)) < 0.000_001 else { return nil }
  return _SolidStrokeRecord(path: path, lineWidth: stroke.lineWidth, isBorder: isBorder, radius: radius, color: color._swiftUIWebCSSValue)
}

/// The stroke that an overlay's content is, when the content is exactly that one stroke layer: a single-child
/// fragment may wrap it, nothing else may.
@MainActor private func _soleStrokeRecord(_ layer: _RenderNode, probe: _StrokeOverlayProbe) -> _SolidStrokeRecord? {
  guard probe.strokes.count == 1, let record = probe.strokes.first else { return nil }
  var node = layer
  while node.kind == .fragment, node.children.count == 1, node.classes.isEmpty, node.styles.isEmpty, node.attributes.isEmpty {
    node = node.children[0]
  }
  guard node.kind == .element("svg"), node.classes == ["shape-layer"], node.children.count == 1,
        node.attributes["data-shape-style"] == "stroke", node.attributes["data-shape-path"] == record.path else { return nil }
  return record
}

/// Styles that paint, clip or move a box, so that a stroke drawn on the box would change with them.
private func _isBoxPaintingStyle(_ property: String) -> Bool {
  if property.hasPrefix("border") || property.hasPrefix("outline") { return property != "border-radius" }
  return ["box-shadow", "filter", "opacity", "clip-path", "mask", "-webkit-mask", "transform", "mix-blend-mode",
          "backdrop-filter", "-webkit-backdrop-filter", "zoom", "translate", "rotate", "scale", "perspective"]
    .contains { property.hasPrefix($0) }
}

/// Paints a solid stroke on the base element as a box shadow: the inner half of a centered stroke and the outer half,
/// or the whole inside line of a `strokeBorder`. An inset shadow is drawn over the base's background and children,
/// as an overlay is, and its ring has the stroke's corner radius (the radius less the inset, which is what SwiftUI's
/// inset path has). Returns false, leaving the base untouched, when the base does not take the stroke as its own box
/// decoration.
@MainActor private func _paintStrokeOnBase(_ record: _SolidStrokeRecord, on node: _RenderNode) -> Bool {
  guard case .element(let tag) = node.kind, tag == "div" || tag == "button", node.text == nil else { return false }
  let styles = node.styles
  if let display = styles["display"], !["block", "flex", "grid", "inline-block", "inline-flex", "inline-grid"].contains(display) { return false }
  guard !styles.keys.contains(where: { _isBoxPaintingStyle($0) || $0 == "box-shadow" }) else { return false }
  // The base's own radius must be the stroke's radius, or the stroke would follow the wrong corners.
  if let radius = record.radius {
    guard styles["border-radius"] == nil || styles["border-radius"] == radius else { return false }
  } else {
    guard styles["border-radius"] == nil || styles["border-radius"] == "0px" else { return false }
  }
  let half = (record.lineWidth / 2).clean
  if record.isBorder {
    node.styles["box-shadow"] = "inset 0 0 0 \(record.lineWidth.clean)px \(record.color)"
  } else {
    node.styles["box-shadow"] = "inset 0 0 0 \(half)px \(record.color), 0 0 0 \(half)px \(record.color)"
  }
  if let radius = record.radius { node.styles["border-radius"] = radius }
  return true
}

package nonisolated struct OverlayModifier<Overlay: View>: ViewModifier {
  package let content: () -> Overlay
  package let alignment: Alignment
  package init(content: @escaping () -> Overlay, alignment: Alignment = .center) { self.content = content; self.alignment = alignment }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    // On a Group/ForEach the overlay decorates each element, as in SwiftUI.
    if node.kind == .fragment {
      for (index, child) in node.children.enumerated() where !child.isEmpty { decorate(child, key: "overlay-\(index)", context: context) }
      return
    }
    decorate(node, key: "overlay", context: context)
  }

  @MainActor private func decorate(_ node: _RenderNode, key: String, context: _RenderContext) {
    let probe = _StrokeOverlayProbe()
    var layerContext = _decoratedLayerContext(node, context, key: key)
    layerContext._strokeOverlayProbe = probe
    // The owners this layer's render registers are its own: if the layer is discarded below, they go with it.
    let registry = context._renderOwnerRegistry
    registry?._beginRecordingRegistrations()
    let layer = AnyView(content())._render(in: layerContext)
    let registered = registry?._endRecordingRegistrations() ?? []
    // A centered overlay that is exactly one solid stroke of its base's shape is painted on the base (no wrapper, no SVG).
    if alignment == .center, let record = _soleStrokeRecord(layer, probe: probe), _paintStrokeOnBase(record, on: node) {
      registry?._retireRegistrations(registered)
      return
    }
    // The overlay may appear/disappear without remounting the base subtree.
    let original = _semanticWrap(node, kind: "overlay")
    node.styles["display"] = "grid"
    node.styles["place-items"] = alignment.cssValue
    for (key, value) in _semanticAlignment(alignment) { node.attributes[key] = value }
    node.children = [original, layer]
  }
}

package nonisolated struct SheetModifier<Sheet: View>: ViewModifier {
  package let isPresented: Binding<Bool>
  package let onDismiss: (@MainActor () -> Void)?
  package let content: () -> Sheet
  package init(isPresented: Binding<Bool>, content: @escaping () -> Sheet) { self.init(isPresented: isPresented, onDismiss: nil, content: content) }
  package init(isPresented: Binding<Bool>, onDismiss: (@MainActor () -> Void)?, content: @escaping () -> Sheet) {
    self.isPresented = isPresented; self.onDismiss = onDismiss; self.content = content
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let dismissed = _trackPresentation(isPresented.wrappedValue ? true : nil, host: node, context: context, onDismiss: onDismiss)
    preparePresentationHost(node, context: context)
    guard isPresented.wrappedValue else { return }
    let dismiss: @MainActor () -> Void = { isPresented.wrappedValue = false; dismissed() }
    let sheet = renderPresentationContent(content, key: _FiberKey("sheet"), dismiss: dismiss, context: context)
    appendPresentation(makePresentationNode(style: "sheet", title: nil, content: [sheet], dismiss: dismiss), to: node)
  }
}

package nonisolated struct PopoverModifier<Popover: View>: ViewModifier {
  package let isPresented: Binding<Bool>
  package let content: () -> Popover
  package init(isPresented: Binding<Bool>, content: @escaping () -> Popover) { self.isPresented = isPresented; self.content = content }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    preparePresentationHost(node, context: context)
    guard isPresented.wrappedValue else { return }
    let popover = renderPresentationContent(content, key: _FiberKey("popover"), dismiss: { isPresented.wrappedValue = false }, context: context)
    appendPresentation(makePresentationNode(style: "popover", title: nil, content: [popover], dismiss: { isPresented.wrappedValue = false }), to: node)
  }
}

package nonisolated struct FullScreenCoverModifier<Cover: View>: ViewModifier {
  package let isPresented: Binding<Bool>
  package let onDismiss: (@MainActor () -> Void)?
  package let content: () -> Cover
  package init(isPresented: Binding<Bool>, content: @escaping () -> Cover) { self.init(isPresented: isPresented, onDismiss: nil, content: content) }
  package init(isPresented: Binding<Bool>, onDismiss: (@MainActor () -> Void)?, content: @escaping () -> Cover) {
    self.isPresented = isPresented; self.onDismiss = onDismiss; self.content = content
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let dismissed = _trackPresentation(isPresented.wrappedValue ? true : nil, host: node, context: context, onDismiss: onDismiss)
    preparePresentationHost(node, context: context)
    guard isPresented.wrappedValue else { return }
    let dismiss: @MainActor () -> Void = { isPresented.wrappedValue = false; dismissed() }
    let cover = renderPresentationContent(content, key: _FiberKey("full-screen-cover"), dismiss: dismiss, context: context)
    appendPresentation(makePresentationNode(style: "full-screen-cover", title: nil, content: [cover], dismiss: dismiss), to: node)
  }
}

/// Item-driven presentation matches SwiftUI's `.sheet(item:onDismiss:content:)`
/// shape while keeping the item storage and dismissal action in the caller's
/// binding. The runtime only renders the item while it is non-nil.
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
package nonisolated struct ItemSheetModifier<Item: Identifiable, Sheet: View>: ViewModifier {
  package let item: Binding<Item?>
  package let onDismiss: (@MainActor () -> Void)?
  package let content: (Item) -> Sheet
  package init(item: Binding<Item?>, onDismiss: (@MainActor () -> Void)?, content: @escaping (Item) -> Sheet) {
    self.item = item; self.onDismiss = onDismiss; self.content = content
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let dismissed = _trackPresentation(item.wrappedValue?.id, host: node, context: context, onDismiss: onDismiss)
    preparePresentationHost(node, context: context)
    guard let value = item.wrappedValue else { return }
    let sheet = renderPresentationContent({ content(value) }, key: _FiberKey("sheet"), dismiss: {
      item.wrappedValue = nil; dismissed()
    }, context: context)
    appendPresentation(makePresentationNode(style: "sheet", title: nil, content: [sheet], dismiss: {
      item.wrappedValue = nil; dismissed()
    }), to: node)
  }
}

@available(macOS 10.15, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
package nonisolated struct ItemFullScreenCoverModifier<Item: Identifiable, Cover: View>: ViewModifier {
  package let item: Binding<Item?>
  package let onDismiss: (@MainActor () -> Void)?
  package let content: (Item) -> Cover
  package init(item: Binding<Item?>, onDismiss: (@MainActor () -> Void)?, content: @escaping (Item) -> Cover) {
    self.item = item; self.onDismiss = onDismiss; self.content = content
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let dismissed = _trackPresentation(item.wrappedValue?.id, host: node, context: context, onDismiss: onDismiss)
    preparePresentationHost(node, context: context)
    guard let value = item.wrappedValue else { return }
    let cover = renderPresentationContent({ content(value) }, key: _FiberKey("full-screen-cover"), dismiss: {
      item.wrappedValue = nil; dismissed()
    }, context: context)
    appendPresentation(makePresentationNode(style: "full-screen-cover", title: nil, content: [cover], dismiss: {
      item.wrappedValue = nil; dismissed()
    }), to: node)
  }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
package nonisolated struct ItemPopoverModifier<Item: Identifiable, Popover: View>: ViewModifier {
  package let item: Binding<Item?>
  package let onDismiss: (@MainActor () -> Void)?
  package let content: (Item) -> Popover
  package init(item: Binding<Item?>, onDismiss: (@MainActor () -> Void)?, content: @escaping (Item) -> Popover) {
    self.item = item; self.onDismiss = onDismiss; self.content = content
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let dismissed = _trackPresentation(item.wrappedValue?.id, host: node, context: context, onDismiss: onDismiss)
    preparePresentationHost(node, context: context)
    guard let value = item.wrappedValue else { return }
    let popover = renderPresentationContent({ content(value) }, key: _FiberKey("popover"), dismiss: {
      item.wrappedValue = nil; dismissed()
    }, context: context)
    appendPresentation(makePresentationNode(style: "popover", title: nil, content: [popover], dismiss: {
      item.wrappedValue = nil; dismissed()
    }), to: node)
  }
}

package nonisolated struct AlertModifier<Message: View, Actions: View>: ViewModifier {
  package let title: String
  package let isPresented: Binding<Bool>
  package let message: () -> Message
  package let actions: () -> Actions
  package init(title: String, isPresented: Binding<Bool>, message: @escaping () -> Message, actions: @escaping () -> Actions) {
    self.title = title; self.isPresented = isPresented; self.message = message; self.actions = actions
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    preparePresentationHost(node, context: context)
    guard isPresented.wrappedValue else { return }
    let dismiss: @MainActor () -> Void = { isPresented.wrappedValue = false }
    let messageNode = renderPresentationContent(message, key: _FiberKey("message"), dismiss: dismiss, context: context)
    var actionsNode = renderPresentationContent(actions, key: _FiberKey("actions"), dismiss: dismiss, context: context)
    // SwiftUI supplies an OK button when an alert declares no actions.
    if actionsNode.isEmpty {
      actionsNode = renderPresentationContent({ Button("OK", action: dismiss).keyboardShortcut(.defaultAction) }, key: _FiberKey("actions"), dismiss: dismiss, context: context)
    }
    appendPresentation(makePresentationNode(style: "alert", title: title, content: [messageNode, actionsNode], dismiss: dismiss), to: node)
  }
}

package nonisolated struct ConfirmationDialogModifier<Actions: View>: ViewModifier {
  package let title: String
  package let isPresented: Binding<Bool>
  package let titleVisibility: Visibility
  package let actions: () -> Actions
  package init(title: String, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, actions: @escaping () -> Actions) {
    self.title = title; self.isPresented = isPresented; self.titleVisibility = titleVisibility; self.actions = actions
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    preparePresentationHost(node, context: context)
    guard isPresented.wrappedValue else { return }
    let actionsNode = renderPresentationContent(actions, key: _FiberKey("actions"), dismiss: { isPresented.wrappedValue = false }, context: context)
    appendPresentation(makePresentationNode(style: "confirmation-dialog", title: title, showsTitle: titleVisibility == .visible, content: [actionsNode], dismiss: { isPresented.wrappedValue = false }), to: node)
  }
}

package nonisolated struct ConfirmationDialogModifierWithMessage<Actions: View, Message: View>: ViewModifier {
  package let title: String
  package let isPresented: Binding<Bool>
  package let titleVisibility: Visibility
  package let actions: () -> Actions
  package let message: () -> Message
  package init(title: String, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, actions: @escaping () -> Actions, message: @escaping () -> Message) {
    self.title = title; self.isPresented = isPresented; self.titleVisibility = titleVisibility; self.actions = actions; self.message = message
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    preparePresentationHost(node, context: context)
    guard isPresented.wrappedValue else { return }
    let dismiss: @MainActor () -> Void = { isPresented.wrappedValue = false }
    let messageNode = renderPresentationContent(message, key: _FiberKey("message"), dismiss: dismiss, context: context)
    let actionsNode = renderPresentationContent(actions, key: _FiberKey("actions"), dismiss: dismiss, context: context)
    appendPresentation(makePresentationNode(style: "confirmation-dialog", title: title, showsTitle: titleVisibility == .visible, content: [messageNode, actionsNode], dismiss: dismiss), to: node)
  }
}

package nonisolated struct ToolbarModifier<Content: View>: ViewModifier {
  package let content: () -> Content
  package init(content: @escaping () -> Content) { self.content = content }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let toolbar = _toolbarItemsOfLooseViews(AnyView(content())._render(in: context.child(_FiberKey("toolbar"))))
    guard !toolbar.isEmpty else { return }
    toolbar.attributes["role"] = "toolbar"
    if let navigation = context.navigationContext {
      // The stack owns its toolbar. When only this screen re-renders the stack is not collecting, and the toolbar
      // it already placed stays; the node must not land in the screen's own tree either way.
      _renderRegistersWithAncestors()
      if navigation.collectingToolbars { navigation.toolbarSink.append(toolbar) }
      return
    }
    node.children.insert(toolbar, at: 0)
  }
}

/// A view written in a toolbar without a `ToolbarItem` (`.toolbar { Button(...) }`) is an item of its own, placed
/// automatically, as in SwiftUI: without the item it would be laid out as one more screen of the stack.
@MainActor private func _toolbarItemsOfLooseViews(_ node: _RenderNode) -> _RenderNode {
  if node.kind == .fragment {
    node.children = node.children.map(_toolbarItemsOfLooseViews)
    return node
  }
  if node.isEmpty || node.classes.contains("toolbar-item") || node.classes.contains("toolbar-group") { return node }
  let item = _RenderNode.element("div")
  item.classes = ["toolbar-item"]
  item.attributes["data-toolbar-placement"] = ToolbarItemPlacement.automatic.rawValue
  item.key = node.key
  item.children = [node]
  return item
}

package nonisolated struct ColorSchemeModifier: ViewModifier {
  package let scheme: ColorScheme?
  package init(scheme: ColorScheme?) { self.scheme = scheme }
  @MainActor package func _modifyContext(_ context: inout _RenderContext) { if let scheme { context.environment.colorScheme = scheme } }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    if let scheme { node.attributes["data-color-scheme"] = scheme.rawValue }
  }
}

/// CSS class of a presentation style; the generic style names get a distinctive class.
private func presentationClass(_ style: String) -> String {
  switch style {
  case "sheet": return "sheet-panel"
  case "popover": return "popover-card"
  case "alert": return "alert-panel"
  default: return style
  }
}

@MainActor private func makePresentationNode(style: String, title: String?, showsTitle: Bool = true, content: [_RenderNode], dismiss: @escaping @MainActor () -> Void) -> _RenderNode {
  let node = _RenderNode.element("div")
  node.classes = ["presentation-root", presentationClass(style)]
  node.attributes["role"] = style == "alert" || style == "confirmation-dialog" ? "alertdialog" : "dialog"
  node.attributes["data-presentation"] = style
  if let title {
    node.attributes["aria-label"] = title
  } else if let label = presentationMetadataValue(in: content, key: "aria-label") {
    node.attributes["aria-label"] = label
  }
  // The browser host uses this semantic event to synchronize a backdrop
  // dismissal with the original SwiftUI binding. Keeping the closure in the
  // _RenderNode means outside-click dismissal follows the same contextual
  // `dismiss` action as buttons inside the presentation.
  node.events["presentation-dismiss"] = _EventHandler(name: "presentation-dismiss", action: dismiss)

  // Keep presentation markup predictable for the browser design system. The
  // SwiftUI modifiers remain responsible for semantics and dismissal; this
  // small structure gives sheets/dialogs a stable header, scrollable content,
  // and action area that follows the same native semantic composition on
  // every viewport.
  //
  // Presentation modifiers are normally written on the content closure (as
  // they are in SwiftUI), so their semantic attributes initially live on the
  // rendered child. Mirror the values onto the sheet wrapper as well. This
  // gives browser hosts one stable surface to size and gesture while keeping
  // the original child node/event identity intact for selection bindings.
  // `presentationBackground(_:)`: the sheet's or the cover's surface, not an alert's.
  if style != "alert", style != "confirmation-dialog",
     let background = presentationMetadataValue(in: content, key: "data-presentation-background") {
    node.styles["background"] = background
  }
  if style == "sheet" {
    let metadataKeys = [
      "data-presentation-detents",
      "data-presentation-detent-selection",
      "data-presentation-detent-heights",
      "data-presentation-drag-indicator",
      "data-interactive-dismiss-disabled",
      "data-presentation-background-interaction"
    ]
    for key in metadataKeys {
      if let value = presentationMetadataValue(in: content, key: key) {
        node.attributes[key] = value
      }
    }
    // Size the sheet to its selected detent (see PresentationDetentsModifier).
    // The stylesheet applies it to compact-width bottom sheets; like SwiftUI
    // on a regular-width iPad, the wide edge-panel presentation ignores it.
    if let height = presentationMetadataValue(in: content, key: "data-presentation-detent-height") {
      node.styles["--presentation-detent-height"] = height
      if node.attributes["data-presentation-detents"]?.contains(",") == true {
        node.attributes["data-presentation-resizable"] = "true"
      }
    }
    // A detent modifier may be applied to a `Group`/fragment, which has no
    // concrete DOM element for the browser to annotate. Mirror its value
    // event onto the presentation wrapper as a safe fallback; ordinary
    // element content keeps its original event identity as well.
    if let event = presentationDetentEvent(in: content) {
      node.events["presentation-detent"] = event
    }
  }
  if let title, showsTitle {
    let header = _RenderNode.element("div")
    header.classes = ["presentation-header", "\(style)-header"]
    let heading = _RenderNode.element("h2")
    heading.classes = ["presentation-title", "\(style)-title"]
    heading.children = [.text(title)]
    header.children = [heading]
    node.children.append(header)
  }

  let renderedContent = content.filter { !$0.isEmpty }
  guard !renderedContent.isEmpty else { return node }

  let contentContainer = _RenderNode.element("div")
  contentContainer.classes = ["presentation-content", "\(style)-content"]
  if style == "alert" || style == "confirmation-dialog", renderedContent.count > 1 {
    let message = _RenderNode.element("div")
    message.classes = ["presentation-message", "\(style)-message"]
    message.children = [renderedContent[0]]

    let actions = _RenderNode.element("div")
    actions.classes = ["presentation-actions", "\(style)-actions"]
    actions.children = Array(renderedContent.dropFirst())
    contentContainer.children = [message, actions]
  } else {
    contentContainer.children = renderedContent
  }
  node.children.append(contentContainer)
  return node
}

private func presentationMetadataValue(in nodes: [_RenderNode], key: String) -> String? {
  for node in nodes {
    if let value = node.attributes[key] { return value }
    if let value = presentationMetadataValue(in: node.children, key: key) { return value }
  }
  return nil
}

@MainActor private func presentationDetentEvent(in nodes: [_RenderNode]) -> _EventHandler? {
  for node in nodes {
    if let event = node.events["presentation-detent"] { return event }
    if let event = presentationDetentEvent(in: node.children) { return event }
  }
  return nil
}

@MainActor private func renderPresentationContent<Content: View>(
  _ content: @escaping () -> Content,
  key: _FiberKey,
  dismiss: @escaping @MainActor () -> Void,
  context: _RenderContext
) -> _RenderNode {
  var childContext = context.child(key)
  childContext.environment.dismiss = DismissAction(dismiss)
  // The presenting control's shortcut does not apply inside its presentation.
  if childContext.environment._keyboardShortcut != nil { childContext.environment._keyboardShortcut = nil }
  return AnyView(content())._render(in: childContext)
}

@MainActor private func preparePresentationHost(_ node: _RenderNode, context: _RenderContext) {
  // Keep this boundary even while dismissed. The source button/input remains
  // the same child; a dialog can never become an invalid descendant of it.
  _semanticWrap(node, kind: "zstack")
  node.classes = ["presentation-host"]
  node.attributes["data-presentation-host"] = "true"
  node.attributes["data-presentation-owner-id"] = context._compactPathID
}

private func appendPresentation(_ presentation: _RenderNode, to node: _RenderNode) {
  let owner = node.attributes["data-presentation-owner-id"] ?? "root"
  let kind = presentation.attributes["data-presentation"] ?? "presentation"
  let ordinal = node.children.filter { $0.classes.contains("presentation-root") }.count
  presentation.attributes["data-presentation-owner-id"] = owner
  presentation.attributes["data-presentation-id"] = "\(owner):\(kind):\(ordinal)"
  presentation.attributes["data-presentation-phase"] = "presented"
  // A stable key keeps the presentation (and the state of its content) when siblings around it come and go.
  presentation.key = _FiberKey("presentation-\(kind)-\(ordinal)")
  node.children.append(presentation)
}

package nonisolated struct EventModifier: ViewModifier {
  package let name: String
  package let action: @MainActor () -> Void
  package init(name: String, action: @escaping @MainActor () -> Void) {
    self.name = name; self.action = action
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    // A gesture on a Group belongs to each of its children, as in SwiftUI.
    node._forEachHost { host in
      host.events[name] = _EventHandler(name: name, action: action, preventsDefault: name == "submit")
    }
  }
}

/// Bridges SwiftUI's `focused` modifier to host-neutral focus events. The
/// browser adapter turns these events into DOM listeners, while static/WASI
/// rendering still exposes deterministic focus metadata.
package nonisolated struct FocusedModifier<Value: Hashable>: ViewModifier {
  package let binding: Binding<Value>
  package let value: Value
  private let clear: (@MainActor () -> Void)?

  package init(binding: Binding<Value>, value: Value, clear: (@MainActor () -> Void)? = nil) {
    self.binding = binding
    self.value = value
    self.clear = clear
  }

  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    #if hasFeature(Embedded)
    node.attributes["data-focus-value"] = "focused"
    #else
    node.attributes["data-focus-value"] = _swiftUIWebDescribe(value)
    #endif
    if binding.wrappedValue == value {
      node.attributes["data-focused"] = "true"
      // BrowserIO treats this as a semantic focus request. The attribute is
      // removed by the next Swift render when the FocusState value changes.
      node.attributes["data-focus-request"] = "true"
    } else {
      node.attributes.removeValue(forKey: "data-focused")
      node.attributes.removeValue(forKey: "data-focus-request")
    }
    guard context.environment.isEnabled else { return }
    node.events["focus"] = _EventHandler(name: "focus", action: { binding.wrappedValue = value })
    if let clear { node.events["blur"] = _EventHandler(name: "blur", action: clear) }
  }
}

/// The callback is evaluated after the first render only when a subsequent
/// Fiber render observes a real Equatable change. Controls already send their
/// value through input/change events, so no second native listener is needed.
package nonisolated struct OnChangeModifier<Value: Equatable>: ViewModifier {
  package let value: Value
  package let action: @MainActor (Value) -> Void
  package init(value: Value, action: @escaping @MainActor (Value) -> Void) {
    self.value = value
    self.action = action
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let key = context._fiberPath.description + "#onChange\(node._onChangeCount)"
    node._onChangeCount += 1
    if context._speculative { return }
    if context.stateStore.remember(key, value: value) {
      let action = self.action, value = self.value, store = context.stateStore
      // Registered where plain recursion would have registered it, so the callbacks fire in render order.
      _RenderStaging.ordered { _ in store._runAfterCommit { action(value) } }
    }
  }
}

/// SwiftUI's hover callback has both enter and leave transitions. Keeping the
/// pair in one modifier avoids exposing browser event names to application
/// code and works for any renderable node.
package nonisolated struct HoverModifier: ViewModifier {
  package let action: @MainActor (Bool) -> Void
  package init(action: @escaping @MainActor (Bool) -> Void) {
    self.action = action
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node._forEachHost { node in
      node.events["mouseenter"] = _EventHandler(name: "mouseenter", action: { action(true) })
      node.events["mouseleave"] = _EventHandler(name: "mouseleave", action: { action(false) })
    }
  }
}

/// Runs a SwiftUI-style task once when the modified Fiber enters the tree.
/// The host renderer owns scheduling. Native builds use Swift's normal
/// executor; the Embedded browser host supplies its event-loop executor so
/// application code keeps the same async API on every target.
package nonisolated struct TaskModifier: ViewModifier {
  package let priority: TaskPriority
  package let action: @MainActor () async -> Void
  package let id: String?
  /// Typed identity for `task(id:)`. SwiftUI restarts the task when the ID is
  /// no longer equal to the previous one; descriptions cannot decide that for
  /// arbitrary Equatable values in Embedded Swift (no reflection), so the
  /// value itself is compared through the owning store.
  private let identity: (@MainActor (StateStore, String) -> UInt64)?
  package init(priority: TaskPriority, action: @escaping @MainActor () async -> Void, id: String? = nil) {
    self.priority = priority
    self.action = action
    self.id = id
    identity = nil
  }
  init<ID: Equatable>(priority: TaskPriority, action: @escaping @MainActor () async -> Void, value: ID, description: String?) {
    nonisolated(unsafe) let value = value
    self.priority = priority
    self.action = action
    self.id = description
    identity = { store, key in store._identityGeneration(key: key, value: value) }
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    // Keep a compact marker for hosts that inspect serialized output. Multiple
    // tasks use an ordinal so a later modifier cannot overwrite an earlier
    // task's marker.
    let ordinal = node.taskRegistrations.count
    if ordinal == 0, let id { node.attributes["data-task-id"] = id }
    // Tasks are owned by the same StateStore as the Fiber subtree. Store a
    // separate registration for each modifier; Fiber invokes all registrations
    // on appearance and cancels each one on disappearance.
    let stateStore = context.stateStore
    let key = context._fiberPath.description + "#task\(ordinal)"
    let taskID: String?
    if let identity {
      taskID = (id ?? "") + "#generation-" + String(identity(stateStore, key + "#identity"))
    } else {
      taskID = id
    }
    // The task body runs after the render pass. Carry the environment of the
    // modified view into the task (and every task it creates) like SwiftUI,
    // which resolves the view's environment before starting `.task`.
    let environment = _EnvironmentSnapshot(context.environment)
    let action = self.action
    node.taskRegistrations.append(.init(
      key: key,
      id: taskID,
      start: {
        stateStore.startTask(key: key, id: taskID) {
          await EnvironmentRuntime.taskEnvironmentValue.withValue(environment) { await action() }
        }
      },
      cancel: { stateStore.cancelTask(key: key) },
    ))
  }
}

package nonisolated struct AnimationModifier<Value: Equatable>: ViewModifier {
  package let animation: Animation?
  package let value: Value
  package init(animation: Animation?, value: Value) {
    self.animation = animation
    self.value = value
  }
  @MainActor package func _modifyContext(_ context: inout _RenderContext) {
    // A speculative render must not advance the history of the real one.
    guard !context._speculative else { return }
    let key = context._modifierStateKey("#animation-value")
    let previous = context.stateStore._animatorValues.value(for: key, as: Value.self)
    context.stateStore._animatorValues.set(value, for: key)
    guard let previous, previous != value else { return }
    // The commit in which `value` changed animates the subtree with `animation`, whatever an ancestor's `withAnimation` or
    // value-scoped animation asked (the modifier closest to the data wins), or, for `nil`, does not animate it at all. A
    // disabled transaction already decided this commit and keeps its say; a `.transaction` below still changes it.
    let committed = context._transaction ?? Transaction()
    guard !committed.disablesAnimations else { return }
    if animation == nil { guard committed.animation != nil else { return } }
    var transaction = committed
    transaction.animation = animation
    transaction.completions = []
    context._transactionOverride = transaction
    context._animationCleared = animation == nil
  }

  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    guard let animation else {
      // An opt-out: what the page plays for this subtree in the commit in which `value` changed is nothing.
      if context._animationCleared { node.attributes["data-transaction-timing"] = "none" }
      return
    }
    // SwiftUI animates under `.animation(_:value:)` only in the transaction where `value` changed. The node carries
    // the timing and a generation that advances when `value` stops being equal to the one rendered here before;
    // the page animates the publication in which the generation changed and lets every other change snap. A
    // permanent inline `transition` would animate every later change below the view, a resize included. Several
    // modifiers on one node each add their own generation. A speculative render (the hovered look of a hover
    // effect) must not advance the history of the real one.
    if !context._speculative {
      let previous = node.attributes["data-animation-value"]
      let ordinal = previous.map { $0.split(separator: ".").count } ?? 0
      let key = context._fiberPath.description + "#animation\(ordinal)"
      let generation = String(context.stateStore._identityGeneration(key: key, value: value))
      node.attributes["data-animation-value"] = previous.map { $0 + "." + generation } ?? generation
    }
    // A transaction that disables animations decides this subtree: the history above advanced (the next real change must be
    // told from this one), but the page is given no timing to arm, so it eases nothing here, and what Swift animates agrees
    // with what the page does.
    if context._transaction?.disablesAnimations == true {
      node.attributes["data-transaction-timing"] = "none"
      return
    }
    node.attributes["data-animation"] = animation.name
    node.attributes["data-animation-timing"] = animation._transitionTiming
    node.attributes["data-animation-iterations"] = animation._browserIterations
    node.attributes["data-animation-direction"] = animation._browserDirection
    propagateMeshGradientAnimation(animation.cssValue, to: node)
    // A custom Layout expresses placement through absolute child geometry.
    // Marking the positioned descendants lets the page give them the same
    // timing when the value changes. This is renderer metadata only; the
    // layout remains authoritative for every interpolated frame and the
    // package modifier stays SwiftUI-shaped.
    if node.classes.contains("layout-box") {
      propagateLayoutAnimation(to: node)
    }
  }
}

/// Both walks below are loops with an explicit stack: an `.animation` can sit above a subtree of any depth, and a
/// call per level would put a limit on it (the WebKit Worker's call stack is small and fixed). The writes are
/// independent of the visiting order.
package func propagateLayoutAnimation(to node: _RenderNode) {
  var pending = [node]
  while let current = pending.popLast() {
    for child in current.children {
      if child.styles["position"] == "absolute" {
        child.attributes["data-layout-animation"] = "true"
      }
      pending.append(child)
    }
  }
}

package func propagateMeshGradientAnimation(_ cssValue: String, to node: _RenderNode) {
  var pending = [node]
  while let current = pending.popLast() {
    if current.attributes["data-mesh-gradient"] == "true" {
      current.attributes["data-mesh-gradient-animation"] = cssValue
    }
    for child in current.children { pending.append(child) }
  }
}

/// Puts the declarations of `css` (`opacity:0.5;filter:blur(2px)`) on `node`: an opacity multiplies the one it has, a transform
/// or filter follows its own, anything else is set.
@MainActor package func _applyRestingLook(_ css: String, to node: _RenderNode) {
  guard !css.isEmpty else { return }
  var depth = 0, start = css.startIndex
  var declarations: [Substring] = []
  for index in css.indices {
    switch css[index] {
    case "(": depth += 1
    case ")": depth -= 1
    case ";" where depth == 0:
      declarations.append(css[start..<index])
      start = css.index(after: index)
    default: break
    }
  }
  declarations.append(css[start...])
  for declaration in declarations {
    guard let colon = declaration.firstIndex(of: ":") else { continue }
    let key = String(declaration[..<colon]), value = String(declaration[declaration.index(after: colon)...])
    guard !key.isEmpty, !value.isEmpty else { continue }
    switch key {
    case "opacity":
      if let existing = node.styles[key], let base = Double(existing), let next = Double(value) { node.styles[key] = String(base * next) } else { node.styles[key] = value }
    case "transform", "filter":
      if let existing = node.styles[key], !existing.isEmpty, existing != "none" { node.styles[key] = existing + " " + value } else { node.styles[key] = value }
    default:
      node.styles[key] = value
    }
  }
}

package nonisolated struct TransitionModifier: ViewModifier {
  package let transition: AnyTransition
  package init(transition: AnyTransition) { self.transition = transition }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    // What the view looks like before it is inserted and after it is removed; the host plays it when the view enters or
    // leaves the page in an animated commit (Tools/embedded-dom.js, TransitionHost).
    node.attributes["data-transition"] = transition.name
    var states = transition.resolved(in: context)
    // The leading edge is on the right in a right-to-left layout: a move, a slide or a push comes from there.
    if context.environment.layoutDirection == .rightToLeft { states = (states.insertion.mirrored(), states.removal.mirrored()) }
    node.attributes["data-transition-insert"] = states.insertion.isIdentity ? "identity" : states.insertion.css
    node.attributes["data-transition-remove"] = states.removal.isIdentity ? "identity" : states.removal.css
    // How the identity phase leaves the view is how it rests.
    _applyRestingLook(states.insertion.restingCSS, to: node)
    if !states.insertion.restingCSS.isEmpty { node.attributes["data-transition-rest"] = states.insertion.restingCSS }
    // A symbol effect's options: how many times faster the transition plays, and how many times it repeats.
    if let options = transition.playback {
      if options.speedValue != 1 { node.attributes["data-transition-speed"] = String(options.speedValue) }
      if let count = options.repeatCount, count > 1 { node.attributes["data-transition-repeat"] = String(count) }
    }
    if let animation = transition.animation { node.attributes["data-transition-timing"] = animation._transitionPlayback }
    // The sides of an asymmetric transition each have their own animation, or the commit's.
    if let animation = transition.insertionAnimation { node.attributes["data-transition-insert-timing"] = animation._transitionPlayback }
    if let animation = transition.removalAnimation { node.attributes["data-transition-remove-timing"] = animation._transitionPlayback }
  }
}

/// SwiftUI-compatible tab metadata. TabView consumes the rendered label to
/// build a native tablist when a selection binding and tagged children are
/// present; keeping it as a modifier also lets applications provide their own
/// tab chrome without losing the declaration.
package nonisolated struct TabItemModifier<Label: View>: ViewModifier {
  package let label: () -> Label
  package init(label: @escaping () -> Label) { self.label = label }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let labelNode = AnyView(label())._render(in: context.child(_FiberKey("tab-item")))
    node.attributes["data-tab-item"] = "true"
    let text = _tabLabelText(labelNode)
    if !text.isEmpty { node.attributes["data-tab-label"] = text }
    if let systemImage = _tabItemSystemImage(labelNode) {
      node.attributes["data-tab-system-image"] = systemImage
    }
  }
}

/// The title of a `.tabItem` label: its text, without the fallback glyph an `Image(systemName:)` carries for browsers
/// that cannot draw the symbol (`Label("Home", systemImage: "house")` is titled "Home", not "⌂Home").
private func _tabLabelText(_ node: _RenderNode) -> String {
  if node.attributes["data-symbol"] != nil { return "" }
  if case .text = node.kind { return node.text ?? "" }
  return node.children.map(_tabLabelText).joined()
}

private func _tabItemSystemImage(_ node: _RenderNode) -> String? {
  if let symbol = node.attributes["data-symbol"] { return symbol }
  for child in node.children {
    if let symbol = _tabItemSystemImage(child) { return symbol }
  }
  return nil
}

package nonisolated struct LifecycleModifier: ViewModifier {
  package let appear: (@MainActor () -> Void)?
  package let disappear: (@MainActor () -> Void)?
  package init(appear: (@MainActor () -> Void)?, disappear: (@MainActor () -> Void)?) {
    self.appear = appear; self.disappear = disappear
  }
  /// Several `onAppear` / `onDisappear` on one view all run, innermost first, as in SwiftUI.
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    if let appear { node.events["appear"] = Self.chained("appear", existing: node.events["appear"]?.action, appear) }
    if let disappear { node.events["disappear"] = Self.chained("disappear", existing: node.events["disappear"]?.action, disappear) }
  }
  @MainActor private static func chained(_ name: String, existing: (@MainActor () -> Void)?, _ action: @escaping @MainActor () -> Void) -> _EventHandler {
    guard let existing else { return _EventHandler(name: name, action: action) }
    return _EventHandler(name: name, action: { existing(); action() })
  }
}

public enum ColorScheme: Hashable, Sendable {
  case light, dark

  /// The CSS spelling of each case; SwiftUI does not expose a raw value.
  package var rawValue: String {
    switch self {
    case .light: "light"
    case .dark: "dark"
    }
  }
}

/// Host-neutral system color-scheme state. Browser hosts install the value
/// from `prefers-color-scheme`; native/WASI hosts may install their own system
/// preference. Applications continue to read the normal
/// `@Environment(\.colorScheme)` value.
package enum ColorSchemeRuntime {
  private static let scheme = _Locked(ColorScheme.light)
  package static var current: ColorScheme {
    get { scheme.withLock { $0 } }
    set { scheme.withLock { $0 = newValue } }
  }

  package static func install(_ scheme: ColorScheme) {
    current = scheme
  }
}

public struct Color: Hashable, Sendable {
  public enum RGBColorSpace: Hashable, Sendable {
    case sRGB
    case sRGBLinear
    case displayP3
  
    /// The CSS spelling of each case; SwiftUI does not expose a raw value.
    var rawValue: String {
      switch self {
      case .sRGB: "sRGB"
      case .sRGBLinear: "sRGBLinear"
      case .displayP3: "displayP3"
      }
    }
  }

  package let cssValue: String
  /// `Color("Name")` is SwiftUI's asset-catalog lookup. A plain identifier
  /// resolves to the custom property `Tools/compile-assets.mjs` generates from
  /// the catalog's color set, falling back to the identifier itself so CSS
  /// keywords such as `red` keep working; any other string is a CSS value.
  public init(_ cssValue: String) {
    self.cssValue = Self._isAssetName(cssValue) ? "var(--asset-color-\(Self._cssIdentifier(cssValue)), \(cssValue))" : Self._declarationSafeCSS(cssValue)
  }
  /// Drops the characters that could end the declaration, the rule or the
  /// style attribute, or open a string, from a raw CSS value. A color value
  /// never needs them, so valid colors keep their bytes.
  private static func _declarationSafeCSS(_ value: String) -> String {
    var result = ""
    for scalar in value.unicodeScalars {
      // { } ; < > " ' and backslash, by value.
      switch scalar.value {
      case 0x7B, 0x7D, 0x3B, 0x3C, 0x3E, 0x22, 0x27, 0x5C: continue
      case ..<0x20, 0x7F: continue
      default: result.unicodeScalars.append(scalar)
      }
    }
    // A value that loads a resource or adds a background layer is not a color: use clear, as for unknown values.
    return _isUnsafeCSSColor(result) ? "transparent" : result
  }
  /// The CSS functions that load a resource: none of them belongs in a color.
  private static let _resourceFunctions: Set<String> = [
    "url", "src", "image", "image-set", "-webkit-image-set", "cross-fade", "-webkit-cross-fade", "element", "-moz-element", "paint",
  ]

  /// True for a CSS value that calls a function that fetches a resource (`url(`, `image-set(`, `element(`...) or has
  /// unbalanced parentheses, which would let it close the enclosing `background` or `color-mix` function early. Only
  /// function names count: `var(--image-accent, red)` names a custom property and is a color.
  private static func _isUnsafeCSSColor(_ value: String) -> Bool {
    let lowered = Array(value.lowercased().utf8)
    func isNameByte(_ byte: UInt8) -> Bool {
      (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x30 && byte <= 0x39) || byte == 0x2D || byte == 0x5F || byte >= 0x80
    }
    for (index, byte) in lowered.enumerated() where byte == 0x28 {
      var start = index
      while start > 0, isNameByte(lowered[start - 1]) { start -= 1 }
      if _resourceFunctions.contains(String(decoding: lowered[start..<index], as: UTF8.self)) { return true }
    }
    var depth = 0
    for byte in value.utf8 {
      if byte == 0x28 { depth += 1 } else if byte == 0x29 {
        depth -= 1
        if depth < 0 { return true }
      }
    }
    return depth != 0
  }
  /// A CSS color value used as written (keywords and system colors included).
  package init(css cssValue: String) { self.cssValue = cssValue }

  static func _isAssetName(_ value: String) -> Bool {
    guard let first = value.utf8.first, (first >= 65 && first <= 90) || (first >= 97 && first <= 122) else { return false }
    for byte in value.utf8 {
      let isLetter = (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
      let isDigit = byte >= 48 && byte <= 57
      // Asset names may be namespaced ("header/Sky Start") or contain spaces; CSS values never look like that.
      if !(isLetter || isDigit || byte == 45 || byte == 95 || byte == 32 || byte == 47) { return false }
    }
    return true
  }

  /// The custom-property name of an asset color: characters CSS does not allow in an identifier are escaped, so
  /// "header/Sky Start" is `header\/Sky\ Start`. `Tools/compile-assets.mjs` writes the same spelling.
  static func _cssIdentifier(_ name: String) -> String {
    var result = ""
    for byte in name.utf8 {
      let isLetter = (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
      let isDigit = byte >= 48 && byte <= 57
      if !(isLetter || isDigit || byte == 45 || byte == 95) { result.append("\\") }
      result.append(Character(Unicode.Scalar(byte)))
    }
    return result
  }
  public init(red: Double, green: Double, blue: Double, opacity: Double = 1) { self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity) }
  /// Creates a grayscale color. SwiftUI treats `white` and `opacity` as
  /// normalized components; values outside that range are clipped by the
  /// browser color model in the same way as the RGB initializer.
  public init(white: Double, opacity: Double = 1) {
    self.init(.sRGB, red: white, green: white, blue: white, opacity: opacity)
  }

  /// Creates a color from hue, saturation and brightness components. Hue is
  /// cyclic while saturation and brightness are normalized. Keeping the
  /// conversion here (rather than introducing a second web color type) means
  /// the resulting value continues to work everywhere a `Color`/`ShapeStyle`
  /// is accepted.
  public init(hue: Double, saturation: Double, brightness: Double, opacity: Double = 1) {
    let rgb = Self._hsvToRGB(hue: hue, saturation: saturation, brightness: brightness)
    self.init(.sRGB, red: rgb.0, green: rgb.1, blue: rgb.2, opacity: opacity)
  }

  /// Asset-backed colors have no portable bundle lookup on the web. The name
  /// is intentionally retained as the CSS value so an application stylesheet
  /// (or a host renderer) can provide the matching token without changing its
  /// SwiftUI source.
  public init(_ name: String, bundle: Bundle? = nil) {
    _ = bundle
    self.init(name)
  }

  public init(_ colorSpace: Color.RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) {
    let red = Self._unit(red)
    let green = Self._unit(green)
    let blue = Self._unit(blue)
    let opacity = Self._unit(opacity)
    switch colorSpace {
    case .displayP3:
      self.cssValue = "color(display-p3 \(red) \(green) \(blue) / \(opacity))"
    case .sRGBLinear:
      self.cssValue = "color(srgb-linear \(red) \(green) \(blue) / \(opacity))"
    case .sRGB:
      self.cssValue = "rgba(\(Int(red * 255)), \(Int(green * 255)), \(Int(blue * 255)), \(opacity))"
    }
  }
  public static let red = Color(css: "light-dark(#FF3B30, #FF453A)"); public static let blue = Color(css: "light-dark(#007AFF, #0A84FF)"); public static let green = Color(css: "light-dark(#34C759, #30D158)"); public static let black = Color(css: "black"); public static let white = Color(css: "white"); public static let gray = Color(css: "light-dark(#8E8E93, #8E8E93)"); public static let clear = Color(css: "transparent"); public static let orange = Color(css: "light-dark(#FF9500, #FF9F0A)"); public static let purple = Color(css: "light-dark(#AF52DE, #BF5AF2)"); public static let yellow = Color(css: "light-dark(#FFCC00, #FFD60A)"); public static let indigo = Color(css: "light-dark(#5856D6, #5E5CE6)"); public static let mint = Color(css: "light-dark(#00C7BE, #63E6E2)"); public static let teal = Color(css: "light-dark(#30B0C7, #40C8E0)"); public static let cyan = Color(css: "light-dark(#32ADE6, #64D2FF)"); public static let pink = Color(css: "light-dark(#FF2D55, #FF375F)"); public static let brown = Color(css: "light-dark(#A2845E, #AC8E68)"); public static let primary = Color(css: "CanvasText"); public static let secondary = Color(css: "GrayText")

  // The system palette is Apple's (light and dark values); the neutral and label colors are CSS system colors that follow the active `color-scheme` and therefore remain
  // environment-dependent without resolving a color during Swift rendering.
  /// The app's accent: its asset catalog's `AccentColor`, or the theme's primary without one. As in SwiftUI, a `.tint(_:)`
  /// above a view does not change it (Food Truck's "Get Started" is `.tint(.white)` with an accent-colored label).
  public static let accentColor = Color("var(--asset-color-AccentColor, var(--color-swu-primary))")
  /// The tint where a view is drawn: the nearest `.tint(_:)` above it, or the app's accent (`--tint-color`).
  package static let _currentTint = Color("var(--tint-color, var(--color-swu-primary))")
  package static let systemBackground = Color("var(--color-swu-background)")
  package static let secondarySystemBackground = Color("var(--color-swu-surface)")
  package static let tertiarySystemBackground = Color("var(--color-swu-card)")
  package static let systemGroupedBackground = Color("var(--color-swu-grouped-background)")
  package static let secondarySystemGroupedBackground = Color("var(--color-swu-grouped-surface)")
  package static let tertiarySystemGroupedBackground = Color("var(--color-swu-card)")
  package static let separator = Color("var(--color-swu-border)")
  package static let opaqueSeparator = Color("var(--color-swu-border)")
  package static let link = Color("var(--color-swu-primary)")
  package static let placeholderText = Color("var(--color-swu-muted-foreground)")

  // Semantic design-system colors are backed by the renderer's stylesheet
  // tokens.  Unlike a literal `.white`/`.black`, these values follow the
  // active SwiftUI color scheme (including `preferredColorScheme` and the
  // browser's system preference) without requiring application CSS.
  package static let background = Color("var(--color-swu-background)")
  package static let surface = Color("var(--color-swu-surface)")
  package static let card = Color("var(--color-swu-card)")
  package static let cardForeground = Color("var(--color-swu-card-foreground)")
  package static let popover = Color("var(--color-swu-popover)")
  package static let popoverForeground = Color("var(--color-swu-popover-foreground)")
  package static let primaryForeground = Color("var(--color-swu-primary-foreground)")
  package static let muted = Color("var(--color-swu-muted)")
  package static let mutedForeground = Color("var(--color-swu-muted-foreground)")
  package static let accent = Color("var(--color-swu-accent)")
  package static let accentForeground = Color("var(--color-swu-accent-foreground)")
  package static let destructive = Color("var(--color-swu-destructive)")
  package static let border = Color("var(--color-swu-border)")
  package static let input = Color("var(--color-swu-input)")
  package static let ring = Color("var(--color-swu-ring)")
  public func opacity(_ value: Double) -> Color {
    let clamped = Self._unit(value)
    if clamped >= 1 { return self }
    if clamped <= 0 { return .clear }
    return Color("color-mix(in srgb, \(cssValue) \((clamped * 100).clean)%, transparent)")
  }

  /// Interpolates colors using the browser's color-mix implementation. This
  /// keeps semantic colors unresolved, so a color-scheme/tint change still
  /// updates the final result after the interpolation is applied.
  public func mix(with other: Color, by fraction: Double) -> Color {
    let clamped = Self._unit(fraction)
    if clamped <= 0 { return self }
    if clamped >= 1 { return other }
    let first = ((1 - clamped) * 100).clean
    let second = (clamped * 100).clean
    return Color("color-mix(in srgb, \(cssValue) \(first)%, \(other.cssValue) \(second)%)")
  }

  package func interpolated(to other: Color, fraction: Double) -> Color {
    mix(with: other, by: fraction)
  }

  /// SwiftUI's `Color.gradient`: the color itself, slightly lighter at the top, so a filled shape reads as a
  /// soft vertical gradient and stays opaque (it does not fade out).
  public var gradient: LinearGradient {
    LinearGradient(gradient: Gradient(colors: [mix(with: .white, by: 0.18), self]), startPoint: .top, endPoint: .bottom)
  }

  private static func _unit(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
  }

  private static func _hsvToRGB(hue: Double, saturation: Double, brightness: Double) -> (Double, Double, Double) {
    let finiteHue = hue.isFinite ? hue : 0
    var normalizedHue = finiteHue.truncatingRemainder(dividingBy: 1)
    if normalizedHue < 0 { normalizedHue += 1 }
    let saturation = _unit(saturation)
    let brightness = _unit(brightness)
    let sector = Int(normalizedHue * 6) % 6
    let fraction = normalizedHue * 6 - Double(Int(normalizedHue * 6))
    let p = brightness * (1 - saturation)
    let q = brightness * (1 - fraction * saturation)
    let t = brightness * (1 - (1 - fraction) * saturation)
    switch sector {
    case 0: return (brightness, t, p)
    case 1: return (q, brightness, p)
    case 2: return (p, brightness, t)
    case 3: return (p, q, brightness)
    case 4: return (t, p, brightness)
    default: return (brightness, p, q)
    }
  }
}

public extension Color {
  /// Small source-compatible counterpart of SwiftUI's resolved color value.
  /// Browser renderers normally receive unresolved `Color` values; this type
  /// is useful to custom renderers that already have linear sRGB components.
  struct Resolved: Hashable, Sendable {
    package let colorSpace: Color.RGBColorSpace
    public let red: Float
    public let green: Float
    public let blue: Float
    public let opacity: Float

    public init(
      colorSpace: Color.RGBColorSpace = .sRGB,
      red: Float,
      green: Float,
      blue: Float,
      opacity: Float = 1
    ) {
      self.colorSpace = colorSpace
      self.red = red
      self.green = green
      self.blue = blue
      self.opacity = opacity
    }

    package var color: Color {
      Color(colorSpace, red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(opacity))
    }

    /// Linear interpolation used by Canvas/gradient renderers and custom
    /// hosts. Different color spaces fall back to sRGB rather than silently
    /// labelling mixed components with the wrong space.
    package func interpolated(to other: Resolved, fraction: Float) -> Resolved {
      let t = fraction.isFinite ? min(max(fraction, 0), 1) : 0
      let space = colorSpace == other.colorSpace ? colorSpace : .sRGB
      return Resolved(
        colorSpace: space,
        red: red + (other.red - red) * t,
        green: green + (other.green - green) * t,
        blue: blue + (other.blue - blue) * t,
        opacity: opacity + (other.opacity - opacity) * t
      )
    }

    package func mix(with other: Resolved, by fraction: Double) -> Resolved {
      interpolated(to: other, fraction: Float(fraction))
    }
  }
}

extension Color: ShapeStyle {
  public var _swiftUIWebCSSValue: String { cssValue }
  public var _swiftUIWebSolidColor: Color? { self }
}

/// SwiftUI treats a `Color` as both a paint (`ShapeStyle`) and a primitive
/// view. Rendering it as a normal fill node keeps direct usages such as
/// `Color.blue.frame(...)` in the same Fiber tree as every other view, while
/// retaining the unresolved CSS value for environment-dependent colors.
extension Color: View {
  public typealias Body = Never

  public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _paintNode(style: cssValue, shape: "rectangle")
    node.classes.append("color-well")
    node.attributes["data-color"] = cssValue
    node.attributes["data-color-style"] = "fill"
    return node
  }
}

public struct Font: Hashable, Sendable {
  public struct Weight: Hashable, Sendable {
    package let rawValue: String
    package init(rawValue: String) { self.rawValue = rawValue }
    public static let ultraLight = Weight(rawValue: "200")
    public static let thin = Weight(rawValue: "300")
    public static let light = Weight(rawValue: "300")
    public static let regular = Weight(rawValue: "400")
    public static let medium = Weight(rawValue: "500")
    public static let semibold = Weight(rawValue: "600")
    public static let bold = Weight(rawValue: "700")
    public static let heavy = Weight(rawValue: "800")
    public static let black = Weight(rawValue: "900")
  }
  public struct Design: Hashable, Sendable {
    package let rawValue: String
    package init(rawValue: String) { self.rawValue = rawValue }
    public static let `default` = Design(rawValue: "system-ui")
    // The system-ui families exist in Safari only: another browser ignores a bare `ui-monospace` and falls back to its
    // default serif face. Each design ends in a generic family so the text keeps its character everywhere.
    public static let rounded = Design(rawValue: "ui-rounded, \"SF Pro Rounded\", system-ui, sans-serif")
    public static let serif = Design(rawValue: "ui-serif, Georgia, \"Times New Roman\", serif")
    public static let monospaced = Design(rawValue: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", monospace")
  }
  public struct Width: Hashable, Sendable {
    package let rawValue: String
    package init(rawValue: String) { self.rawValue = rawValue }
    public static let compressed = Width(rawValue: "75%")
    public static let condensed = Width(rawValue: "87.5%")
    public static let standard = Width(rawValue: "100%")
    public static let expanded = Width(rawValue: "125%")
  }
  package let cssStyles: _NodeValues
  package init(size: Double? = nil, weight: String? = nil, design: String? = nil) {
    var values = _NodeValues()
    if let size {
      values["font-size"] = "\(size.clean)px"
      // The stylesheet's reset sets a 1.5 document line-height. A
      // SwiftUI Font is not document typography: its line box comes from the
      // platform font metrics. `normal` lets the browser use the native system
      // font metrics instead of inheriting the document leading.
      values["line-height"] = "normal"
    }
    if let weight { values["font-weight"] = weight }
    // `.system(...)` must not inherit an application/document font such as
    // Inter. Keep the system family explicit so browser intrinsic measurement
    // is comparable to SwiftUI's SF system font on Apple platforms.
    values["font-family"] = design ?? "-apple-system, BlinkMacSystemFont, system-ui, sans-serif"
    cssStyles = values
  }
  public static func system(_ style: Font.TextStyle, design: Font.Design? = nil, weight: Font.Weight? = nil) -> Font {
    var styles = _textStyleFont(style).cssStyles
    if let design { styles["font-family"] = design.rawValue }
    if let weight { styles["font-weight"] = weight.rawValue }
    return Font(cssStyles: styles)
  }
  private static func _textStyleFont(_ style: Font.TextStyle) -> Font {
    switch style {
    case .largeTitle: return .largeTitle
    case .title: return .title
    case .title2: return .title2
    case .title3: return .title3
    case .headline: return .headline
    case .subheadline: return .subheadline
    case .body: return .body
    case .callout: return .callout
    case .footnote: return .footnote
    case .caption: return .caption
    case .caption2: return .caption2
    }
  }
  public static func system(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
    Font(size: size, weight: weight?.rawValue, design: design?.rawValue)
  }
  // Internal so `Font.custom` and other focused Font extensions can build
  // values without widening the public initializer surface.
  package init(cssStyles: _NodeValues) { self.cssStyles = cssStyles }
  public func weight(_ weight: Font.Weight) -> Font { var styles = cssStyles; styles["font-weight"] = weight.rawValue; return Font(cssStyles: styles) }
  public func bold() -> Font { weight(.bold) }
  public func italic() -> Font { var styles = cssStyles; styles["font-style"] = "italic"; return Font(cssStyles: styles) }
  public func monospacedDigit() -> Font { var styles = cssStyles; styles["font-variant-numeric"] = "tabular-nums"; return Font(cssStyles: styles) }
  public func monospaced() -> Font { var styles = cssStyles; styles["font-family"] = Design.monospaced.rawValue; return Font(cssStyles: styles) }
  public func width(_ width: Font.Width) -> Font { var styles = cssStyles; styles["font-stretch"] = width.rawValue; return Font(cssStyles: styles) }
  public static let largeTitle = Font(size: 34, weight: "700"); public static let title = Font(size: 28, weight: "700"); public static let title2 = Font(size: 22, weight: "700"); public static let title3 = Font(size: 20, weight: "600"); public static let headline = Font(size: 17, weight: "700"); public static let subheadline = Font(size: 15); public static let body = Font(size: 17); public static let callout = Font(size: 16); public static let footnote = Font(size: 13); public static let caption = Font(size: 12); public static let caption2 = Font(size: 11)
}

/// A compact, host-neutral representation of SwiftUI's animation values.
///
/// The browser renderer turns this metadata into a CSS transition.  Keeping
/// the timing values here (rather than in individual controls) means an
/// application can use the normal SwiftUI animation factories, including the
/// spring and timing-curve overloads used by the real projects.
public struct Animation: Hashable, Sendable {
  package let name: String
  private let duration: Double?
  private let timingFunction: String
  private let delayValue: Double
  private let repeatCountValue: Int?
  private let repeatsForever: Bool
  private let autoreversesValue: Bool
  private let speedValue: Double
  /// When the animation is logically complete, before its delay: a spring's response (its perceptual duration), which
  /// comes before it settles; nil when it is its whole duration.
  private let logicalDuration: Double?
  /// The curve in a form Swift can evaluate (`_fraction(at:)`), for what Swift animates itself: `Animatable` data,
  /// custom animations.
  private let curve: _AnimationCurve
  /// How long a spring that interrupts another blends from it (SwiftUI's `blendDuration`).
  private let blendDurationValue: Double

  package init(_ name: String = "default") {
    self.name = name
    duration = nil
    timingFunction = Animation.defaultTimingFunction(for: name)
    curve = _AnimationCurve.named(timingFunction)
    blendDurationValue = 0
    delayValue = 0
    repeatCountValue = nil
    repeatsForever = false
    autoreversesValue = true
    speedValue = 1
    logicalDuration = nil
  }

  private init(
    name: String,
    duration: Double?,
    timingFunction: String,
    delay: Double = 0,
    repeatCount: Int? = nil,
    repeatsForever: Bool = false,
    autoreverses: Bool = true,
    speed: Double = 1,
    logicalDuration: Double? = nil,
    curve: _AnimationCurve? = nil,
    blendDuration: Double = 0
  ) {
    self.logicalDuration = logicalDuration
    self.curve = curve ?? _AnimationCurve.named(timingFunction)
    blendDurationValue = blendDuration.isFinite ? max(blendDuration, 0) : 0
    self.name = name
    self.duration = duration
    self.timingFunction = timingFunction
    delayValue = max(delay, 0)
    repeatCountValue = repeatCount.map { max($0, 0) }
    self.repeatsForever = repeatsForever
    autoreversesValue = autoreverses
    speedValue = speed > 0 ? speed : 1
  }

  /// SwiftUI's default animation: since iOS 17 a critically damped spring.
  public static let `default` = Animation.springAnimation(name: "default", motion: _SpringMotion(response: 0.55, dampingRatio: 1))
  public static let linear = Animation("linear")
  public static let easeIn = Animation("ease-in")
  public static let easeOut = Animation("ease-out")
  public static let easeInOut = Animation("ease-in-out")

  public static func linear(duration: TimeInterval) -> Animation {
    Animation(name: "linear", duration: duration, timingFunction: "linear")
  }
  public static func easeIn(duration: TimeInterval) -> Animation {
    Animation(name: "ease-in", duration: duration, timingFunction: "ease-in")
  }
  public static func easeOut(duration: TimeInterval) -> Animation {
    Animation(name: "ease-out", duration: duration, timingFunction: "ease-out")
  }
  public static func easeInOut(duration: TimeInterval) -> Animation {
    Animation(name: "ease-in-out", duration: duration, timingFunction: "ease-in-out")
  }

  /// A spring played by the browser: it runs until the spring settles, along the spring's own curve (a CSS
  /// `linear()` easing sampled from the closed-form solution), so overshoot and settling match SwiftUI.
  static func springAnimation(name: String, motion: _SpringMotion, blendDuration: Double = 0) -> Animation {
    let duration = motion.settlingDuration()
    return Animation(
      name: name, duration: duration, timingFunction: motion.cssEasing(duration: duration),
      logicalDuration: min(motion.response, duration), curve: .spring(motion), blendDuration: blendDuration)
  }

  /// A custom animation. Swift evaluates it for what it animates itself; the browser plays it as a `linear()` easing
  /// sampled from it, for as long as it runs (ten seconds at most).
  public init<A: CustomAnimation>(_ base: A) {
    let box = _CustomAnimationBox(base)
    let sampled = box.sampled()
    self.init(
      name: "custom(\(box.hash))", duration: sampled.duration, timingFunction: sampled.easing,
      curve: .custom(box))
  }

  /// The response/damping spelling. Disfavored, as in SwiftUI: `.spring()` and `.spring` are the duration/bounce spring,
  /// which does not overshoot; this one overshoots by default (damping fraction 0.825) and is reached by its labels.
  @_disfavoredOverload
  public static func spring(
    response: Double = 0.5,
    dampingFraction: Double = 0.825,
    blendDuration: TimeInterval = 0
  ) -> Animation {
    springAnimation(
      name: "spring(\(max(response, 0.01).clean),\(max(dampingFraction, 0).clean),\(blendDuration.clean))",
      motion: _SpringMotion(response: response, dampingRatio: dampingFraction), blendDuration: blendDuration)
  }

  /// The duration/bounce spelling: bounce 0 is critically damped, and a positive bounce lowers the damping. It is what
  /// `.spring()` and `.spring` mean, as in SwiftUI.
  public static func spring(duration: TimeInterval = 0.5, bounce: Double = 0, blendDuration: Double = 0) -> Animation {
    springAnimation(
      name: "spring-duration(\(duration.clean),\(bounce.clean),\(blendDuration.clean))",
      motion: _SpringMotion(duration: duration, bounce: bounce), blendDuration: blendDuration)
  }

  /// Disfavored, as in SwiftUI: `.interactiveSpring()` is the duration/bounce spelling below.
  @_disfavoredOverload
  public static func interactiveSpring(
    response: Double = 0.15,
    dampingFraction: Double = 0.86,
    blendDuration: TimeInterval = 0.25
  ) -> Animation {
    spring(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
  }

  /// A quick spring with a little bounce (0.15), for a value that follows the person's finger.
  public static func interactiveSpring(duration: TimeInterval = 0.15, extraBounce: Double = 0, blendDuration: TimeInterval = 0.25) -> Animation {
    spring(duration: duration, bounce: 0.15 + extraBounce, blendDuration: blendDuration)
  }

  public static var interactiveSpring: Animation { interactiveSpring() }

  public static var interpolatingSpring: Animation { interpolatingSpring() }

  public static func interpolatingSpring(
    mass: Double = 1,
    stiffness: Double,
    damping: Double,
    initialVelocity: Double = 0
  ) -> Animation {
    springAnimation(
      name: "interpolating-spring(\(mass.clean),\(stiffness.clean),\(damping.clean),\(initialVelocity.clean))",
      motion: _SpringMotion(mass: mass, stiffness: stiffness, damping: damping, initialVelocity: initialVelocity))
  }

  public static func interpolatingSpring(
    duration: TimeInterval = 0.5,
    bounce: Double = 0,
    initialVelocity: Double = 0
  ) -> Animation {
    springAnimation(
      name: "interpolating-spring-duration(\(duration.clean),\(bounce.clean),\(initialVelocity.clean))",
      motion: _SpringMotion(duration: duration, bounce: bounce, initialVelocity: initialVelocity))
  }

  public static func timingCurve(
    _ c0x: Double,
    _ c0y: Double,
    _ c1x: Double,
    _ c1y: Double,
    duration: TimeInterval = 0.35
  ) -> Animation {
    Animation(
      name: "timing-curve(\(c0x.clean),\(c0y.clean),\(c1x.clean),\(c1y.clean))",
      duration: max(duration, 0),
      timingFunction: "cubic-bezier(\(c0x.clean),\(c0y.clean),\(c1x.clean),\(c1y.clean))",
      curve: .bezier(c0x, c0y, c1x, c1y)
    )
  }

  /// SwiftUI's presets are springs of the given perceptual duration: `smooth` has no bounce, `snappy` a little
  /// (0.15), `bouncy` a noticeable one (0.3); `extraBounce` adds to it.
  public static func smooth(duration: TimeInterval = 0.5, extraBounce: Double = 0) -> Animation {
    springAnimation(name: "smooth(\(duration.clean),\(extraBounce.clean))", motion: _SpringMotion(duration: duration, bounce: extraBounce))
  }

  public static func snappy(duration: TimeInterval = 0.5, extraBounce: Double = 0) -> Animation {
    springAnimation(name: "snappy(\(duration.clean),\(extraBounce.clean))", motion: _SpringMotion(duration: duration, bounce: 0.15 + extraBounce))
  }

  public static func bouncy(duration: TimeInterval = 0.5, extraBounce: Double = 0) -> Animation {
    springAnimation(name: "bouncy(\(duration.clean),\(extraBounce.clean))", motion: _SpringMotion(duration: duration, bounce: 0.3 + extraBounce))
  }

  public func delay(_ delay: TimeInterval) -> Animation {
    copy(delay: delayValue + max(delay, 0))
  }

  /// Speeds up what is already built, the delay included: `.delay(1).speed(2)` waits half a second, while
  /// `.speed(2).delay(1)` waits a whole one, as in SwiftUI.
  public func speed(_ speed: Double) -> Animation {
    let factor = speed > 0 ? speed : 1
    return copy(delay: delayValue / factor, speed: factor)
  }

  public func repeatCount(_ count: Int, autoreverses: Bool = true) -> Animation {
    copy(repeatCount: max(count, 0), autoreverses: autoreverses)
  }

  public func repeatForever(autoreverses: Bool = true) -> Animation {
    copy(repeatsForever: true, autoreverses: autoreverses)
  }

  package var cssValue: String {
    // Repeat/direction are animation concepts, not valid CSS transition tokens.
    // The retained host consumes their separate metadata with WAAPI.  Keep a
    // harmless CSS comment in the public description so diagnostics and
    // SwiftUI-shaped callers can still observe that repetition was requested;
    // browsers ignore the comment when using this value as a transition.
    let repetition = repeatsForever ? " /* infinite */" : (repeatCountValue.map { " /* repeat \($0) */" } ?? "")
    // The host plays an insertion or removal that a transaction animates with these (`TransitionHost.timingFor`).
    let direction = _browserDirection == "alternate" ? " /* alternate */" : ""
    return "all \(_transitionTiming)\(repetition)\(direction)"
  }

  /// Duration, timing function and delay of a CSS transition, without the property: what the page and a hover rule
  /// apply to the properties they animate.
  package var _transitionTiming: String {
    // A time too short to write without an exponent (which the page's parser and CSS number grammar differ on) is no time.
    func text(_ milliseconds: Double) -> String { milliseconds < 0.001 ? "0" : milliseconds.clean }
    let milliseconds = text(max((duration ?? 0.35) / speedValue * 1000, 0))
    let delay = delayValue * 1000 >= 0.001 ? " \(text(delayValue * 1000))ms" : ""
    return "\(milliseconds)ms \(timingFunction)\(delay)"
  }

  /// The timing of a transition's own animation as the host plays it: the CSS timing, then ` repeat:<iterations> <direction>`
  /// when the animation repeats (the page cannot take them from a CSS transition value).
  var _transitionPlayback: String {
    repeatsForever || repeatCountValue != nil ? "\(_transitionTiming) repeat:\(_browserIterations) \(_browserDirection)" : _transitionTiming
  }

  var _browserIterations: String {
    repeatsForever ? "infinite" : String(max(repeatCountValue ?? 1, 1))
  }
  var _browserDirection: String {
    autoreversesValue && (repeatsForever || repeatCountValue != nil) ? "alternate" : "normal"
  }

  private func copy(
    delay: Double = 0,
    repeatCount: Int? = nil,
    repeatsForever: Bool? = nil,
    autoreverses: Bool? = nil,
    speed: Double = 1
  ) -> Animation {
    Animation(
      name: name,
      duration: duration,
      timingFunction: timingFunction,
      delay: delay == 0 ? delayValue : delay,
      repeatCount: repeatCount ?? repeatCountValue,
      repeatsForever: repeatsForever ?? self.repeatsForever,
      autoreverses: autoreverses ?? autoreversesValue,
      speed: speed == 1 ? speedValue : speedValue * speed,
      logicalDuration: logicalDuration,
      curve: curve,
      blendDuration: blendDurationValue
    )
  }

  /// Marks the animation logically complete `duration` seconds in, for completions that wait for it.
  public func logicallyComplete(after duration: TimeInterval) -> Animation {
    Animation(
      name: name, duration: self.duration, timingFunction: timingFunction, delay: delayValue, repeatCount: repeatCountValue,
      repeatsForever: repeatsForever, autoreverses: autoreversesValue, speed: speedValue,
      logicalDuration: duration.isFinite ? max(duration, 0) : nil, curve: curve, blendDuration: blendDurationValue)
  }

  /// How far along the animation is `time` seconds after it started, from 0 to 1 (a spring passes 1 on the way), or
  /// nil once it has finished. Delay, speed and repeats included; `context` carries a custom animation's state.
  package func _fraction(at time: Double, context: inout AnimationContext<Double>) -> Double? {
    _fraction(at: time, change: 1, context: &context)
  }

  /// `_fraction(at:)` for a change of magnitude `change`. A custom animation is evaluated for that magnitude (its
  /// `magnitudeSquared` is the square of it), and the fraction is what it made of the change.
  package func _fraction(at time: Double, change: Double, context: inout AnimationContext<Double>) -> Double? {
    let local = (time - delayValue) * speedValue
    guard local > 0 else { return 0 }
    let repeats = repeatsForever || repeatCountValue != nil
    if case .custom(let box) = curve, !repeats {
      return _customFraction(box, at: local, change: change, context: &context)
    }
    let length = duration ?? 0.35
    guard length > 0 else { return nil }
    let iteration = (local / length).rounded(.down)
    let iterations = repeatsForever ? Double.infinity : Double(max(repeatCountValue ?? 1, 1))
    guard iteration < iterations else { return nil }
    var progress = (local - iteration * length) / length
    // `Int(iteration)` would trap past 2^31 iterations on wasm32; the remainder of a Double cannot.
    if autoreversesValue && repeats && iteration.truncatingRemainder(dividingBy: 2) == 1 { progress = 1 - progress }
    if case .custom(let box) = curve {
      // Each iteration runs the custom animation over its own time (backwards on a reversed one). Once it has
      // finished before the iteration ends, it holds its final value.
      return _customFraction(box, at: progress * length, change: change, context: &context) ?? 1
    }
    return curve.value(at: progress, duration: length)
  }

  private func _customFraction(_ box: _CustomAnimationBox, at time: Double, change: Double, context: inout AnimationContext<Double>) -> Double? {
    guard change > 0 else { return box.animate(1, time, &context) }
    return box.animate(change, time, &context).map { $0 / change }
  }

  /// SwiftUI's `blendDuration` of a spring, 0 for other curves.
  package var _blendDuration: Double { blendDurationValue }

  /// Whether an animation that interrupts another continues from it: springs do, as in SwiftUI.
  package var _merges: Bool {
    switch curve {
    case .spring: return true
    case .bezier, .custom: return false
    }
  }

  /// A custom animation's own velocity at `time` for a change of magnitude `change`, in value units per second, with
  /// the animation's delay, speed, repeats and autoreverse applied as `_fraction` applies them. `isCustom` is false for
  /// the built-in curves; `rate` is nil when the custom animation reports no velocity (or has finished).
  package func _customVelocity(at time: Double, change: Double, context: AnimationContext<Double>) -> (isCustom: Bool, rate: Double?) {
    guard case .custom(let box) = curve else { return (false, nil) }
    let local = (time - delayValue) * speedValue
    guard local > 0 else { return (true, 0) }
    var customTime = local
    var direction = 1.0
    if repeatsForever || repeatCountValue != nil {
      let length = duration ?? 0.35
      guard length > 0 else { return (true, nil) }
      let iteration = (local / length).rounded(.down)
      let iterations = repeatsForever ? Double.infinity : Double(max(repeatCountValue ?? 1, 1))
      guard iteration < iterations else { return (true, nil) }
      var progress = (local - iteration * length) / length
      if autoreversesValue && iteration.truncatingRemainder(dividingBy: 2) == 1 { progress = 1 - progress; direction = -1 }
      customTime = progress * length
    }
    return (true, box.velocity(change > 0 ? change : 1, customTime, context).map { $0 * speedValue * direction })
  }

  /// Whether this animation, interrupting `previous`, takes it over: a custom animation decides for itself (and keeps
  /// the state it updates), a spring does, other curves do not.
  package func _shouldMerge(previous: Animation, change: Double, time: Double, context: inout AnimationContext<Double>) -> Bool {
    if case .custom(let box) = curve { return box.shouldMerge(previous, change, time, &context) }
    return _merges
  }

  /// The CSS timing function alone (`ease-in-out`, `cubic-bezier(...)`, a spring's `linear(...)`).
  package var _timingFunction: String { timingFunction }
  /// The seconds the browser plays one iteration for, speed included.
  package var _playedDuration: Double { max((duration ?? 0.35) / speedValue, 0) }
  /// How long the animation waits before it starts, in seconds.
  package var _playedDelay: Double { max(delayValue, 0) }

  /// The seconds after which `criteria` is met: the delay plus the logical or the whole duration of every iteration.
  /// An animation that repeats forever never completes.
  func _completionDelay(_ criteria: AnimationCompletionCriteria) -> Double? {
    if repeatsForever { return nil }
    let iterations = Double(max(repeatCountValue ?? 1, 1))
    let whole = _playedDuration * iterations
    let logical = logicalDuration.map { $0 / speedValue + _playedDuration * (iterations - 1) } ?? whole
    return delayValue + (criteria == .removed ? whole : logical)
  }

  private static func defaultTimingFunction(for name: String) -> String {
    switch name {
    case "linear": return "linear"
    case "ease-in": return "ease-in"
    case "ease-out": return "ease-out"
    case "ease-in-out": return "ease-in-out"
    default: return "ease-in-out"
    }
  }
}

/// What a completion handler of `withAnimation` waits for.
public struct AnimationCompletionCriteria: Hashable, Sendable {
  let removedAtEnd: Bool
  /// The animation has reached its target: a spring after its response, before it settles.
  public static let logicallyComplete = AnimationCompletionCriteria(removedAtEnd: false)
  /// The animation has ended and no longer affects the view.
  public static let removed = AnimationCompletionCriteria(removedAtEnd: true)
}

/// Runs `completion` on the main actor after `seconds`. The browser runtime installs a scheduler backed by the page's
/// timer (SwiftUIWebBrowser); a host without one (native tests) runs the completion right away.
nonisolated(unsafe) package var _animationCompletionScheduler: ((Double, @escaping () -> Void) -> Void)? = nil

/// `withAnimation` with a completion: `body` runs in the animation's transaction, then `completion` runs once the
/// animation meets `completionCriteria`. Without an animation, or with one that repeats forever, it runs at once and
/// never respectively.
@discardableResult
public func withAnimation<Result>(
  _ animation: Animation? = .default,
  completionCriteria: AnimationCompletionCriteria = .logicallyComplete,
  _ body: () throws -> Result,
  completion: @escaping () -> Void
) rethrows -> Result {
  let result = try withAnimation(animation, body)
  _scheduleAnimationCompletion(animation, criteria: completionCriteria, completion)
  return result
}

/// Runs a state mutation with a SwiftUI-shaped animation transaction. Fiber
/// state updates are synchronous, so the closure is executed immediately;
/// any `.animation(_:value:)` metadata on affected nodes is then reconciled by
/// the browser host. The return/rethrow shape matches SwiftUI's API, allowing
/// existing application code to move between SwiftUI and SwiftUIWeb.
@discardableResult
public func withAnimation<Result>(
  _ animation: Animation? = .default,
  _ body: () throws -> Result
) rethrows -> Result {
  // The current transaction with this animation: the values a `withTransaction` around it set stay.
  var transaction = _RenderThreadState.current.transaction ?? Transaction()
  transaction.animation = animation
  transaction.disablesAnimations = false
  transaction.completions = []
  return try withTransaction(transaction, body)
}

// Access is serialized by the UI runtime. StateStore captures this transaction
// when a source changes, before the scope is restored or a deferred commit runs.
enum _AnimationTransactionRuntime {
  static var current: Animation? {
    get { _RenderThreadState.current.animation }
    set { _RenderThreadState.current.animation = newValue }
  }
  static var isActive: Bool {
    get { _RenderThreadState.current.animationActive }
    set { _RenderThreadState.current.animationActive = newValue }
  }
  /// The transaction of the changes being made now.
  static var transaction: Transaction? {
    let thread = _RenderThreadState.current
    return thread.transaction ?? (thread.animationActive ? Transaction(animation: thread.animation) : nil)
  }
}

extension Edge {
  /// The bit that transition identities have always carried, so the names
  /// stay stable now that `Edge` is an enum (SwiftUI's shape).
  var _transitionCode: Int {
    switch self {
    case .top: return 1
    case .leading: return 2
    case .bottom: return 4
    case .trailing: return 8
    }
  }
}

private func _frameDimension(_ value: Double) -> String {
  if value.isInfinite { return "100%" }
  if value.isNaN { return "auto" }
  return "\(value.clean)px"
}

// Style tables for the frame, padding and fixedSize modifiers. They are
// independent of the view they apply to, so they are built here once instead
// of inside the generic `View` extension methods, which would specialize the
// whole construction per view type.
@inline(never)
func _paddingModifier(_ value: Double) -> StyleModifier {
  StyleModifier(styles: ["padding": "\(value.clean)px"], semantic: [
    "data-layout-kind": "padding", "data-padding-top": String(value),
    "data-padding-leading": String(value), "data-padding-bottom": String(value),
    "data-padding-trailing": String(value)])
}

@inline(never)
func _paddingModifier(_ edges: Edge.Set, _ length: Double?) -> StyleModifier {
  let amount = length ?? 8
  var styles: _NodeValues = .init()
  var semantic: _NodeValues = ["data-layout-kind": "padding"]
  if edges.contains(.top) { styles["padding-top"] = "\(amount.clean)px"; semantic["data-padding-top"] = String(amount) }
  if edges.contains(.leading) { styles["padding-inline-start"] = "\(amount.clean)px"; semantic["data-padding-leading"] = String(amount) }
  if edges.contains(.bottom) { styles["padding-bottom"] = "\(amount.clean)px"; semantic["data-padding-bottom"] = String(amount) }
  if edges.contains(.trailing) { styles["padding-inline-end"] = "\(amount.clean)px"; semantic["data-padding-trailing"] = String(amount) }
  return StyleModifier(styles: styles, semantic: semantic)
}

@inline(never)
func _frameModifier(width: Double?, height: Double?, alignment: Alignment) -> StyleModifier {
  var styles = _NodeValues()
  if let width { styles["width"] = _frameDimension(width) }
  if let height { styles["height"] = _frameDimension(height) }
  if width != nil || height != nil { styles["--frame-alignment"] = alignment.cssValue }
  return StyleModifier(styles: styles, semantic: _semanticFrame(["w": width, "h": height], alignment))
}

@inline(never)
func _frameModifier(width: Double?, height: Double?, maxWidth: Double?, maxHeight: Double?, alignment: Alignment) -> StyleModifier {
  var styles = _NodeValues()
  if let width { styles["width"] = _frameDimension(width) }
  if let height { styles["height"] = _frameDimension(height) }
  if let maxWidth {
    styles["max-width"] = _frameDimension(maxWidth)
    if width == nil { styles["width"] = "100%" }
  }
  if let maxHeight {
    styles["max-height"] = _frameDimension(maxHeight)
    if height == nil && maxHeight.isInfinite { styles["height"] = "100%" }
  }
  if width != nil || height != nil || maxWidth != nil || maxHeight != nil {
    styles["--frame-alignment"] = alignment.cssValue
  }
  return StyleModifier(styles: styles, semantic: _semanticFrame(["w": width, "h": height, "max-w": maxWidth, "max-h": maxHeight], alignment))
}

@inline(never)
func _frameModifier(maxWidth: Double?, maxHeight: Double?, alignment: Alignment) -> StyleModifier {
  var styles = _NodeValues()
  if let maxWidth {
    styles["max-width"] = _frameDimension(maxWidth)
    // A max-width frame accepts the parent's proposal up to the limit. A
    // percentage width lets a nested frame participate in that proposal;
    // the max-width still caps it for constrained content columns.
    styles["width"] = "100%"
  }
  if let maxHeight {
    styles["max-height"] = _frameDimension(maxHeight)
    if maxHeight.isInfinite { styles["height"] = "100%" }
  }
  if maxWidth != nil || maxHeight != nil { styles["--frame-alignment"] = alignment.cssValue }
  return StyleModifier(styles: styles, semantic: _semanticFrame(["max-w": maxWidth, "max-h": maxHeight], alignment))
}

@inline(never)
func _frameModifier(minWidth: Double?, idealWidth: Double?, maxWidth: Double?, minHeight: Double?, idealHeight: Double?, maxHeight: Double?, alignment: Alignment) -> StyleModifier {
  var styles = _NodeValues()
  if let minWidth { styles["min-width"] = _frameDimension(minWidth) }
  if let idealWidth {
    styles["width"] = _frameDimension(idealWidth)
    // Preserve the ideal independently when a max frame later changes the
    // CSS width to 100%; split layouts use this semantic seed for their
    // initial pane allocation.
    styles["--ideal-width"] = _frameDimension(idealWidth)
  }
  if let maxWidth {
    styles["max-width"] = _frameDimension(maxWidth)
    styles["width"] = "100%"
  }
  if let minHeight { styles["min-height"] = _frameDimension(minHeight) }
  if let idealHeight {
    styles["height"] = _frameDimension(idealHeight)
    styles["--ideal-height"] = _frameDimension(idealHeight)
  }
  if let maxHeight {
    styles["max-height"] = _frameDimension(maxHeight)
    if maxHeight.isInfinite { styles["height"] = "100%" }
  }
  if !styles.isEmpty { styles["--frame-alignment"] = alignment.cssValue }
  return StyleModifier(styles: styles, semantic: _semanticFrame(["min-w": minWidth, "ideal-w": idealWidth, "max-w": maxWidth, "min-h": minHeight, "ideal-h": idealHeight, "max-h": maxHeight], alignment))
}

@inline(never)
func _fixedSizeModifier(horizontal: Bool, vertical: Bool) -> StyleModifier {
  var styles: _NodeValues = .init()
  if horizontal { styles["width"] = "max-content" }
  if vertical { styles["height"] = "max-content" }
  return StyleModifier(styles: styles, semantic: ["data-layout-kind": "fixed", "data-fixed-x": String(horizontal), "data-fixed-y": String(vertical)])
}

// Int64(exactly:) is nil, not a trap, for a whole value Int64 cannot hold (`.opacity(1e300)`).
private extension Double { var clean: String { Int64(exactly: self).map { String($0) } ?? String(self) } }

// The gradients are plain Sendable values used as `ShapeStyle`s from any context; View is
// declared in an extension so it does not make the type main-actor isolated.
extension LinearGradient: View {}
extension RadialGradient: View {}
extension AngularGradient: View {}
extension EllipticalGradient: View {}

/// The color scheme that an `environment(_:_:)` write sets, when the write sets `\.colorScheme`. Such a subtree is marked
/// with it as `.preferredColorScheme` marks one, so its semantic colors resolve for that scheme. Embedded Swift has no
/// key-path comparison; there the lowerer spells `.environment(\.colorScheme, x)` as `EnvironmentOverride(colorScheme:)`.
fileprivate nonisolated func _environmentColorScheme<Value>(_ keyPath: WritableKeyPath<EnvironmentValues, Value>, _ value: Value) -> ColorScheme? {
  #if hasFeature(Embedded)
  return nil
  #else
  guard (keyPath as AnyKeyPath) == (\EnvironmentValues.colorScheme as AnyKeyPath) else { return nil }
  return value as? ColorScheme
  #endif
}
