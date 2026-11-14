@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebTransferable

public nonisolated struct BorderedButtonStyle: PrimitiveButtonStyle {
  public nonisolated init() {}
  public nonisolated func makeBody(configuration: BorderedButtonStyle.Configuration) -> some View { configuration.label }
  public nonisolated var _swiftUIWebButtonStyleToken: String? { "bordered" }
}

public nonisolated struct BorderedProminentButtonStyle: PrimitiveButtonStyle {
  public nonisolated init() {}
  public nonisolated func makeBody(configuration: BorderedProminentButtonStyle.Configuration) -> some View { configuration.label }
  public nonisolated var _swiftUIWebButtonStyleToken: String? { "bordered-prominent" }
}

public nonisolated struct BorderlessButtonStyle: PrimitiveButtonStyle {
  public nonisolated init() {}
  public nonisolated func makeBody(configuration: BorderlessButtonStyle.Configuration) -> some View { configuration.label }
  public nonisolated var _swiftUIWebButtonStyleToken: String? { "borderless" }
}

nonisolated struct PrimitiveButtonStyleModifier<Style: PrimitiveButtonStyle>: ViewModifier {
  let style: Style
  private let value: ButtonStyleValue
  private let isCustom: Bool
  init(style: Style) {
    self.style = style
    let token = style._swiftUIWebButtonStyleToken
    self.value = ButtonStyleValue(token ?? ButtonStyleValue.automatic.rawValue)
    self.isCustom = token == nil
  }
  @MainActor func _modifyContext(_ context: inout _RenderContext) {
    context.environment.buttonStyle = value
    context.environment.buttonStyleIsCustom = isCustom
    if context.environment._buttonStyleIsPrimitive != isCustom { context.environment._buttonStyleIsPrimitive = isCustom }
    context.environment.buttonStyleRenderer = _ButtonStyleRenderer { configuration in
      let primitive = PrimitiveButtonStyleConfiguration(
        role: configuration.role,
        label: .init(body: configuration.label.body),
        action: configuration._action
      )
      return AnyView(style.makeBody(configuration: primitive))
    }
  }
  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-button-style"] = value.rawValue
  }
}

public extension PrimitiveButtonStyle where Self == BorderedButtonStyle {
  static nonisolated var bordered: BorderedButtonStyle { BorderedButtonStyle() }
}

public extension PrimitiveButtonStyle where Self == BorderedProminentButtonStyle {
  static nonisolated var borderedProminent: BorderedProminentButtonStyle { BorderedProminentButtonStyle() }
}

public extension PrimitiveButtonStyle where Self == BorderlessButtonStyle {
  static nonisolated var borderless: BorderlessButtonStyle { BorderlessButtonStyle() }
}

nonisolated struct ButtonStyleModifier<Style: ButtonStyle>: ViewModifier {
  let style: Style
  private let value: ButtonStyleValue
  private let isCustom: Bool
  init(style: Style) {
    self.style = style
    let token = style._swiftUIWebButtonStyleToken
    self.value = ButtonStyleValue(token ?? ButtonStyleValue.automatic.rawValue)
    self.isCustom = token == nil
  }
  @MainActor func _modifyContext(_ context: inout _RenderContext) {
    context.environment.buttonStyle = value
    context.environment.buttonStyleIsCustom = isCustom
    if context.environment._buttonStyleIsPrimitive { context.environment._buttonStyleIsPrimitive = false }
    context.environment.buttonStyleRenderer = _ButtonStyleRenderer { configuration in AnyView(style.makeBody(configuration: configuration)) }
  }
  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-button-style"] = value.rawValue
  }
}

package nonisolated struct ControlSizeModifier: ViewModifier {
  package let size: ControlSize
  package init(size: ControlSize) { self.size = size }
  @MainActor package func _modifyContext(_ context: inout _RenderContext) { context.environment.controlSize = size }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-control-size"] = size.rawValue
  }
}

public extension View {
  // Apple's two `buttonStyle` overloads. Built-in styles reach the primitive
  // overload and are identified by their browser token; app-defined styles are
  // rendered through their own `makeBody`.
  nonisolated func buttonStyle<S: ButtonStyle>(_ style: S) -> some View {
    modifier(ButtonStyleModifier(style: style))
  }

  nonisolated func buttonStyle<S: PrimitiveButtonStyle>(_ style: S) -> some View {
    modifier(PrimitiveButtonStyleModifier(style: style))
  }

  nonisolated func controlSize(_ size: ControlSize) -> some View {
    modifier(ControlSizeModifier(size: size))
  }
}

public nonisolated struct ViewThatFits<Content: View>: View {
  public typealias Body = Never
  package let axes: Axis.Set
  package let content: Content

  public nonisolated init(in axes: Axis.Set = [.horizontal, .vertical], @ViewBuilder content: () -> Content) {
    self.axes = axes
    self.content = content()
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.classes = ["view-that-fits"]
    node.attributes["data-view-that-fits"] = axes.contains(.horizontal) && axes.contains(.vertical) ? "both" : axes.contains(.vertical) ? "vertical" : "horizontal"

    let rendered = content._render(in: context.child(_FiberKey("candidates")))
    let candidates: [_RenderNode]
    if rendered.kind == .fragment { candidates = rendered.children } else if rendered.isEmpty { candidates = [] } else { candidates = [rendered] }
    node.children = candidates.enumerated().map { index, candidate in
      candidate.classes.append("view-that-fits-candidate")
      candidate.attributes["data-fit-index"] = String(index)
      if index == 0 { candidate.attributes["data-fit-selected"] = "true" }
      return candidate
    }
    return node
  }
}

package nonisolated struct RefreshableModifier: ViewModifier {
  package let action: @MainActor () async -> Void
  package init(action: @escaping @MainActor () async -> Void) {
    self.action = action
  }
  @MainActor package func _modifyContext(_ context: inout _RenderContext) {
    context.environment.refresh = RefreshAction(action)
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-refreshable"] = "true"
    let box = _RefreshTaskBox(action)
    node.events["refresh"] = _EventHandler(name: "refresh", action: {
      #if !hasFeature(Embedded)
      _ = Task { await box.action() }
      #endif
    })
  }
}

private final class _RefreshTaskBox {
  let action: () async -> Void
  init(_ action: @escaping () async -> Void) { self.action = action }
}

package nonisolated struct RedactedModifier: ViewModifier {
  package let reasons: RedactionReasons
  package init(reasons: RedactionReasons) { self.reasons = reasons }
  @MainActor package func _modifyContext(_ context: inout _RenderContext) {
    var inherited = context.environment.redactionReasons
    inherited.formUnion(reasons)
    context.environment.redactionReasons = inherited
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    // Stacked modifiers on one node accumulate their reasons, as SwiftUI does.
    let previous = RedactionReasons(rawValue: Int(node.attributes["data-redaction-reasons"] ?? "") ?? 0)
    let combined = previous.union(reasons)
    node.classes.removeAll { $0 == "redacted" || $0 == "redacted-placeholder" || $0 == "redacted-privacy" }
    node.classes.append("redacted")
    // The CSS takes each reason from its own class, because it cannot test one bit of a number.
    if combined.contains(.placeholder) { node.classes.append("redacted-placeholder") }
    if combined.contains(.privacy) { node.classes.append("redacted-privacy") }
    node.attributes["data-redaction-reasons"] = String(combined.rawValue)
    node.attributes["aria-busy"] = "true"
  }
}

package nonisolated struct UnredactedModifier: ViewModifier {
  package init() {}
  @MainActor package func _modifyContext(_ context: inout _RenderContext) {
    context.environment.redactionReasons = []
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    // `unredacted` ends the redaction rules of an enclosing `.redacted` node (see Tools/styles.css).
    node.classes.removeAll { $0 == "redacted" || $0 == "redacted-placeholder" || $0 == "redacted-privacy" }
    if !node.classes.contains("unredacted") { node.classes.append("unredacted") }
    node.attributes.removeValue(forKey: "data-redaction-reasons")
    node.attributes.removeValue(forKey: "aria-busy")
  }
}

package nonisolated struct SafeAreaInsetModifier<Inset: View>: ViewModifier {
  package let edge: Edge.Set
  package let alignment: Alignment
  package let spacing: Double?
  package let content: () -> Inset
  package init(edge: Edge.Set, alignment: Alignment = .center, spacing: Double? = nil, content: @escaping () -> Inset) {
    self.edge = edge; self.alignment = alignment; self.spacing = spacing; self.content = content
  }

  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let original = _semanticWrap(node, kind: "inset")
    let inset = content()._render(in: context.child(_FiberKey("safe-area-inset")))
    let name = _safeAreaEdgeName(edge)
    node.classes = ["safe-area-inset"]
    node.attributes["data-safe-area-edge"] = name
    node.attributes["data-inset-edge"] = name
    node.attributes["data-layout-gap"] = String(spacing ?? 0)
    for (key, value) in _semanticAlignment(alignment) { node.attributes[key] = value }
    node.styles["display"] = "flex"
    node.styles["flex-direction"] = name == "top" ? "column-reverse" : name == "leading" ? "row-reverse" : name == "trailing" ? "row" : "column"
    node.styles["gap"] = String(spacing ?? 0) + "px"
    node.children = [original, inset]

  }
}

private func _safeAreaEdgeName(_ edge: Edge.Set) -> String {
  if edge.contains(.top) { return "top" }
  if edge.contains(.bottom) { return "bottom" }
  if edge.contains(.leading) { return "leading" }
  if edge.contains(.trailing) { return "trailing" }
  return "bottom"
}

public extension View {
  nonisolated func refreshable(action: @escaping @Sendable () async -> Void) -> some View {
    modifier(RefreshableModifier(action: { await action() }))
  }

  nonisolated func redacted(reason: RedactionReasons) -> some View {
    modifier(RedactedModifier(reasons: reason))
  }

  nonisolated func unredacted() -> some View { modifier(UnredactedModifier()) }

  nonisolated func safeAreaInset<Inset: View>(edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: Double? = nil, @ViewBuilder content: @escaping () -> Inset) -> some View {
    modifier(SafeAreaInsetModifier(edge: edge == .top ? .top : .bottom, alignment: Alignment(horizontal: alignment, vertical: .center), spacing: spacing, content: content))
  }

  nonisolated func safeAreaInset<Inset: View>(edge: HorizontalEdge, alignment: VerticalAlignment = .center, spacing: Double? = nil, @ViewBuilder content: @escaping () -> Inset) -> some View {
    modifier(SafeAreaInsetModifier(edge: edge == .leading ? .leading : .trailing, alignment: Alignment(horizontal: .center, vertical: alignment), spacing: spacing, content: content))
  }
}

public extension ShareLink where Label == Text {
  nonisolated init(item: String, subject: Text? = nil, message: Text? = nil) {
    self.init(described: item, subject: subject, message: message, label: Text("Share"))
  }

  nonisolated init(item: URL, subject: Text? = nil, message: Text? = nil) {
    self.init(described: _swiftUIWebDescribe(item), subject: subject, message: message, label: Text("Share"))
  }
}

package nonisolated struct AccessibilityMetadataModifier: ViewModifier {
  package let value: String?
  package let hint: String?
  package let addTraits: AccessibilityTraits
  package let removeTraits: AccessibilityTraits
  package let hidden: Bool?
  package init(value: String? = nil, hint: String? = nil, addTraits: AccessibilityTraits = [], removeTraits: AccessibilityTraits = [], hidden: Bool? = nil) {
    self.value = value; self.hint = hint; self.addTraits = addTraits; self.removeTraits = removeTraits; self.hidden = hidden
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    _AccessibilityBackend.apply(
      .init(value: value, hint: hint, addTraits: addTraits, removeTraits: removeTraits, hidden: hidden),
      to: node
    )
  }
}

public extension View {
  @_disfavoredOverload nonisolated func accessibilityValue<S: StringProtocol>(_ value: S) -> some View {
    modifier(AccessibilityMetadataModifier(value: String(value)))
  }

  nonisolated func accessibilityValue(_ value: Text) -> some View {
    accessibilityValue(value.value)
  }

  @_disfavoredOverload nonisolated func accessibilityHint<S: StringProtocol>(_ hint: S) -> some View {
    modifier(AccessibilityMetadataModifier(hint: String(hint)))
  }

  nonisolated func accessibilityHint(_ hint: Text) -> some View {
    accessibilityHint(hint.value)
  }

  nonisolated func accessibilityAddTraits(_ traits: AccessibilityTraits) -> some View {
    modifier(AccessibilityMetadataModifier(addTraits: traits))
  }

  nonisolated func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> some View {
    modifier(AccessibilityMetadataModifier(removeTraits: traits))
  }

  nonisolated func accessibilityHidden(_ hidden: Bool) -> some View {
    modifier(AccessibilityMetadataModifier(hidden: hidden))
  }
}

package nonisolated struct OnChangeNoArgumentModifier<Value: Equatable>: ViewModifier {
  package let value: Value
  package let initial: Bool
  package let action: () -> Void
  package init(value: Value, initial: Bool, action: @escaping () -> Void) { self.value = value; self.initial = initial; self.action = action }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    // Use the modifier's semantic slot rather than the transient StateScope
    // counter. AnyView boundaries intentionally create independent scopes;
    // deriving the key from that counter made adjacent `onChange` overloads
    // accidentally share their first value and suppressed the initial pair
    // callback. The Fiber path is stable across renders and the suffix keeps
    // the no-argument and old/new overloads independent.
    let key = context._fiberPath.description + "#onChange\(node._onChangeCount)"
    node._onChangeCount += 1
    if context._speculative { return }
    let result = context.stateStore.rememberChange(key, value: value)
    if result.changed || (initial && result.initial) {
      let action = self.action, store = context.stateStore
      _RenderStaging.ordered { _ in store._runAfterCommit { action() } }
    }
  }
}

package nonisolated struct OnChangePairModifier<Value: Equatable>: ViewModifier {
  package let value: Value
  package let initial: Bool
  package let action: (Value, Value) -> Void
  package init(value: Value, initial: Bool, action: @escaping (Value, Value) -> Void) { self.value = value; self.initial = initial; self.action = action }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let key = context._fiberPath.description + "#onChange\(node._onChangeCount)"
    node._onChangeCount += 1
    if context._speculative { return }
    let result = context.stateStore.rememberChange(key, value: value)
    let action = self.action
    if result.changed {
      let previous = result.previous ?? value, value = self.value, store = context.stateStore
      _RenderStaging.ordered { _ in store._runAfterCommit { action(previous, value) } }
    } else if initial && result.initial {
      let value = self.value, store = context.stateStore
      _RenderStaging.ordered { _ in store._runAfterCommit { action(value, value) } }
    }
  }
}

public struct SubmitTriggers: OptionSet, Sendable {
  public typealias RawValue = Int
  public let rawValue: RawValue
  public init(rawValue: SubmitTriggers.RawValue) { self.rawValue = rawValue }
  public static let text = SubmitTriggers(rawValue: 1 << 0)
  public static let search = SubmitTriggers(rawValue: 1 << 2)
  public typealias ArrayLiteralElement = SubmitTriggers
  public typealias Element = SubmitTriggers
  package static let date = SubmitTriggers(rawValue: 1 << 1)
  package static let form = SubmitTriggers(rawValue: 1 << 3)
  package static let all: SubmitTriggers = [.text, .search, .date, .form]
}

package nonisolated struct SubmitModifier: ViewModifier {
  package let triggers: SubmitTriggers
  package let action: @MainActor () -> Void
  package init(triggers: SubmitTriggers, action: @escaping @MainActor () -> Void) {
    self.triggers = triggers; self.action = action
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-submit-triggers"] = String(triggers.rawValue)
    node.events["submit"] = _EventHandler(name: "submit", action: action, preventsDefault: true)
  }
}

public extension View {
  nonisolated func onChange<Value: Equatable>(of value: Value, initial: Bool = false, _ action: @escaping () -> Void) -> some View {
    modifier(OnChangeNoArgumentModifier(value: value, initial: initial, action: action))
  }

  nonisolated func onChange<Value: Equatable>(of value: Value, initial: Bool = false, _ action: @escaping (Value, Value) -> Void) -> some View {
    modifier(OnChangePairModifier(value: value, initial: initial, action: action))
  }

  nonisolated func onSubmit(of triggers: SubmitTriggers = .text, _ action: @escaping () -> Void) -> some View {
    modifier(SubmitModifier(triggers: triggers, action: _mainActor(action)))
  }
}

extension Canvas where Symbols == EmptyView {
  nonisolated public init(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear, rendersAsynchronously: Bool = false, renderer: @escaping (inout GraphicsContext, CGSize) -> Void) {
    self.init(opaque: opaque, colorMode: colorMode, rendersAsynchronously: rendersAsynchronously, renderer: renderer, symbols: EmptyView(), symbolProvider: nil)
  }

  /// SwiftUIWeb's non-Apple symbol providers have no SwiftUI counterpart, so they are package-scoped.
  package init(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear, rendersAsynchronously: Bool = false, renderer: @escaping (inout GraphicsContext, CGSize) -> Void, symbolProvider: @escaping () -> GraphicsContext.Symbols) {
    nonisolated(unsafe) let symbols = symbolProvider
    self.init(opaque: opaque, colorMode: colorMode, rendersAsynchronously: rendersAsynchronously, renderer: renderer, symbols: EmptyView(), symbolProvider: { _ in symbols() })
  }

  package init(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear, rendersAsynchronously: Bool = false, renderer: @escaping (inout GraphicsContext, CGSize) -> Void, symbolProvider: @escaping (inout GraphicsContext.Symbols) -> Void) {
    nonisolated(unsafe) let symbols = symbolProvider
    self.init(opaque: opaque, colorMode: colorMode, rendersAsynchronously: rendersAsynchronously, renderer: renderer, symbols: EmptyView(), symbolProvider: { _ in
      var value = GraphicsContext.Symbols()
      symbols(&value)
      return value
    })
  }
}
