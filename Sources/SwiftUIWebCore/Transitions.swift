// SwiftUI's insertion and removal transitions.
//
// A transition is described by the state the view is in while it is not yet (or no longer) there: its active
// state, as CSS declarations relative to the view's own box. The view renders at identity; the browser host
// (Tools/embedded-dom.js, `TransitionHost`) plays the active state into identity when the view is inserted in an
// animated commit, and identity into the removal's active state before it takes the view out. The animation is the
// commit's (`withAnimation`, an `.animation(_:value:)` that changed) unless the transition carries its own.

/// The active state of one side of a transition, as CSS declarations that compose: opacities multiply, scales
/// multiply, translations add, transforms and filters chain.
package struct _TransitionState: Hashable, Sendable {
  package var opacity: Double = 1
  package var scaleX: Double = 1
  package var scaleY: Double = 1
  /// The anchor of the scale, in unit coordinates of the view.
  package var anchor: UnitPoint? = nil
  /// Translation terms per axis (`-100%`, `12px`); they add up.
  package var translateX: [String] = []
  package var translateY: [String] = []
  /// Horizontal terms that go towards the leading or the trailing edge (a move, a slide, a push): they add to `translateX`,
  /// and change side in a right-to-left layout, where the leading edge is on the right. An offset is not one of them.
  package var edgeTranslateX: [String] = []
  package var blur: Double = 0
  /// Declarations of a custom transition that have no structured form (`transform`, `filter`, colors), last wins
  /// except `transform` and `filter`, which chain.
  package var declarations: [String: String] = .init()
  /// What the identity phase of a custom transition does to the view (`opacity:0.5`): how the view rests, which the view takes
  /// on for good. The other terms describe the active phase.
  package var restingCSS: String = ""

  package init() {}

  package static let identity = _TransitionState()

  /// Whether the active phase looks like identity (the resting look is not part of it).
  package var isIdentity: Bool { var plain = self; plain.restingCSS = ""; return plain == .identity }

  package func combined(with other: _TransitionState) -> _TransitionState {
    var result = self
    result.opacity *= other.opacity
    result.scaleX *= other.scaleX
    result.scaleY *= other.scaleY
    result.anchor = other.anchor ?? anchor
    result.translateX += other.translateX
    result.translateY += other.translateY
    result.edgeTranslateX += other.edgeTranslateX
    result.blur += other.blur
    result.restingCSS = [restingCSS, other.restingCSS].filter { !$0.isEmpty }.joined(separator: ";")
    for (key, value) in other.declarations {
      if let existing = result.declarations[key], key == "transform" || key == "filter" { result.declarations[key] = existing + " " + value }
      else { result.declarations[key] = value }
    }
    return result
  }

  /// `opacity:0;translate:-100% 0;scale:0.5;transform-origin:50% 50%;filter:blur(8px)`; empty at identity.
  package var css: String {
    var parts: [String] = []
    // Not clamped above: for a custom transition it is a ratio of the identity phase's opacity (2 over a resting 0.5 is 1), and the
    // host multiplies it by that opacity.
    if opacity != 1 { parts.append("opacity:\(_transitionNumber(max(0, opacity)))") }
    if !translateX.isEmpty || !translateY.isEmpty || !edgeTranslateX.isEmpty {
      parts.append("translate:\(_translateTerm(translateX + edgeTranslateX)) \(_translateTerm(translateY))")
    }
    if scaleX != 1 || scaleY != 1 {
      parts.append(scaleX == scaleY ? "scale:\(_transitionNumber(scaleX))" : "scale:\(_transitionNumber(scaleX)) \(_transitionNumber(scaleY))")
    }
    if let anchor, scaleX != 1 || scaleY != 1 {
      parts.append("transform-origin:\(_transitionNumber(anchor.x * 100))% \(_transitionNumber(anchor.y * 100))%")
    }
    var filter = blur > 0 ? "blur(\(_transitionNumber(blur))px)" : ""
    for key in declarations.keys.sorted() {
      guard let value = declarations[key] else { continue }
      if key == "filter" { filter += (filter.isEmpty ? "" : " ") + value; continue }
      parts.append("\(key):\(value)")
    }
    if !filter.isEmpty { parts.append("filter:\(filter)") }
    return parts.joined(separator: ";")
  }

  package static func opacity(_ value: Double) -> _TransitionState { var state = _TransitionState(); state.opacity = value; return state }
  package static func scale(_ value: Double, anchor: UnitPoint) -> _TransitionState {
    var state = _TransitionState(); state.scaleX = value; state.scaleY = value; state.anchor = anchor; return state
  }
  static func translation(x: String?, y: String?) -> _TransitionState {
    var state = _TransitionState()
    if let x { state.translateX = [x] }
    if let y { state.translateY = [y] }
    if x != nil && y == nil { state.translateY = ["0px"] }
    if y != nil && x == nil { state.translateX = ["0px"] }
    return state
  }
  /// Off the view's own box towards `edge`, as `MoveTransition` does.
  static func move(_ edge: Edge) -> _TransitionState {
    switch edge {
    case .leading: var state = _TransitionState(); state.edgeTranslateX = ["-100%"]; state.translateY = ["0px"]; return state
    case .trailing: var state = _TransitionState(); state.edgeTranslateX = ["100%"]; state.translateY = ["0px"]; return state
    case .top: return translation(x: nil, y: "-100%")
    case .bottom: return translation(x: nil, y: "100%")
    }
  }
  static func blur(_ radius: Double) -> _TransitionState { var state = _TransitionState(); state.blur = radius; return state }

  /// The state in a right-to-left layout: what goes towards the leading or trailing edge goes the other way, and the anchor
  /// of a scale, which is in leading-to-trailing unit coordinates, is on the other side.
  package func mirrored() -> _TransitionState {
    var result = self
    result.edgeTranslateX = edgeTranslateX.map { $0.hasPrefix("-") ? String($0.dropFirst()) : "-" + $0 }
    if let anchor { result.anchor = UnitPoint(x: 1 - anchor.x, y: anchor.y) }
    return result
  }
}

private func _translateTerm(_ terms: [String]) -> String {
  if terms.isEmpty { return "0px" }
  if terms.count == 1 { return terms[0] }
  return "calc(" + terms.joined(separator: " + ") + ")"
}

/// A decimal with at most five places and no exponent: "0.00001", "-12.5", "40".
package func _transitionNumber(_ value: Double) -> String {
  guard value.isFinite else { return "0" }
  // Within what an Int64 holds after scaling: a length beyond a billion pixels is as far off the page as any.
  let scaled = Int64((min(max(value, -1e12), 1e12) * 100_000).rounded())
  if scaled == 0 { return "0" }
  let negative = scaled < 0, magnitude = negative ? -scaled : scaled
  var fraction = magnitude % 100_000, digits = 5
  var text = (negative ? "-" : "") + String(magnitude / 100_000)
  if fraction != 0 {
    while fraction % 10 == 0 { fraction /= 10; digits -= 1 }
    var fractionText = String(fraction)
    while fractionText.count < digits { fractionText = "0" + fractionText }
    text += "." + fractionText
  }
  return text
}

private extension Edge {
  var opposite: Edge {
    switch self {
    case .top: return .bottom
    case .bottom: return .top
    case .leading: return .trailing
    case .trailing: return .leading
    }
  }
}

/// Resolves a transition whose states come from SwiftUI views (`Transition.body`, `AnyTransition.modifier`): its
/// phases are rendered once against an empty placeholder, and what differs from the identity phase is its active state.
package final class _TransitionResolver: @unchecked Sendable {
  let render: @MainActor (_RenderContext) -> (insertion: _TransitionState, removal: _TransitionState)
  init(_ render: @escaping @MainActor (_RenderContext) -> (insertion: _TransitionState, removal: _TransitionState)) { self.render = render }
}

/// The styles a phase render adds over identity: the declarations that differ, along the chain of wrappers the
/// modifiers built around the placeholder.
@MainActor
func _transitionDelta(active: _RenderNode, identity: _RenderNode) -> _TransitionState {
  var state = _TransitionState()
  var activeChain: [_RenderNode] = [], identityChain: [_RenderNode] = []
  var current: _RenderNode? = active
  while let node = current, activeChain.count < 16 { activeChain.append(node); current = node.children.count == 1 ? node.children[0] : nil }
  current = identity
  while let node = current, identityChain.count < 16 { identityChain.append(node); current = node.children.count == 1 ? node.children[0] : nil }
  for (index, node) in activeChain.enumerated() {
    let reference = index < identityChain.count ? identityChain[index].styles : _NodeValues()
    // A phase may leave the opacity unset while identity sets it (identity at 0.5, the active look at the default 1): the
    // active opacity is then the default, and the ratio to identity still applies. Other styles cannot be removed by a delta.
    var styles = node.styles
    if styles["opacity"] == nil, reference["opacity"] != nil { styles["opacity"] = "1" }
    for (key, value) in styles where reference[key] != value {
      switch key {
      case "opacity":
        // Relative to the identity phase's opacity: that is how the view rests, and the active look is put over it.
        // With an identity opacity of zero there is no ratio to take: the active opacity is given as it is, and the page does not
        // multiply it by the resting opacity.
        let rest = Double(reference["opacity"] ?? "1") ?? 1
        if rest > 0 { state.opacity *= (Double(value) ?? 1) / rest } else { state.declarations["opacity"] = value }
      case "transform", "filter":
        if let existing = state.declarations[key] { state.declarations[key] = existing + " " + value } else { state.declarations[key] = value }
      case "transition", "will-change": continue
      default:
        state.declarations[key] = value
      }
    }
  }
  return state
}

// MARK: AnyTransition

/// A type-erased transition.
public struct AnyTransition {
  package let name: String
  package let insertion: _TransitionState
  package let removal: _TransitionState
  /// The animation of both sides. An asymmetric transition keeps the animations of its sides apart.
  package let animation: Animation?
  package let insertionAnimation: Animation?
  package let removalAnimation: Animation?
  package let resolver: _TransitionResolver?
  /// The speed and repeats of a symbol effect transition, which the host plays the commit's (or the transition's own) timing with.
  package let playback: SymbolEffectOptions?

  package init(_ name: String, insertion: _TransitionState = .identity, removal: _TransitionState? = nil, animation: Animation? = nil, insertionAnimation: Animation? = nil, removalAnimation: Animation? = nil, resolver: _TransitionResolver? = nil, playback: SymbolEffectOptions? = nil) {
    self.playback = playback
    self.name = name
    self.insertion = insertion
    self.removal = removal ?? insertion
    self.animation = animation
    self.insertionAnimation = insertionAnimation
    self.removalAnimation = removalAnimation
    self.resolver = resolver
  }


  public static var identity: AnyTransition { AnyTransition("identity") }
  public nonisolated(unsafe) static let opacity = AnyTransition("opacity", insertion: .opacity(0))
  /// Scales the view from (and to) nothing, about its center.
  public static var scale: AnyTransition { AnyTransition("scale", insertion: .scale(1e-5, anchor: .center)) }
  /// Inserts from the leading edge and removes towards the trailing one.
  public static var slide: AnyTransition { AnyTransition("slide", insertion: .move(.leading), removal: .move(.trailing)) }
  public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition {
    // The resolver runs on the main actor while the renderer resolves the modifier; the values are immutable.
    nonisolated(unsafe) let insertion = insertion, removal = removal
    let resolver: _TransitionResolver? = insertion.resolver == nil && removal.resolver == nil ? nil : _TransitionResolver { context in
      (insertion.resolved(in: context).insertion, removal.resolved(in: context).removal)
    }
    return AnyTransition("asymmetric(\(insertion.name),\(removal.name))", insertion: insertion.insertion, removal: removal.removal, insertionAnimation: insertion.animation ?? insertion.insertionAnimation, removalAnimation: removal.animation ?? removal.removalAnimation, resolver: resolver, playback: insertion.playback ?? removal.playback)
  }
  public static func move(edge: Edge) -> AnyTransition {
    AnyTransition("move(\(edge._transitionCode))", insertion: .move(edge))
  }
  public static func offset(_ offset: CGSize) -> AnyTransition {
    Self.offset(x: offset.width, y: offset.height)
  }
  public static func offset(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition {
    let x = Double(x), y = Double(y)
    return AnyTransition("offset(\(x.transitionClean),\(y.transitionClean))", insertion: .translation(x: "\(_transitionNumber(x))px", y: "\(_transitionNumber(y))px"))
  }
  public static func scale(scale: CGFloat, anchor: UnitPoint = .center) -> AnyTransition {
    let scale = Double(scale)
    return AnyTransition("scale(\(scale),\(anchor.x.transitionClean),\(anchor.y.transitionClean))", insertion: .scale(scale, anchor: anchor))
  }
  /// Inserts from `edge` and removes towards the opposite one, fading as it goes.
  public static func push(from edge: Edge) -> AnyTransition {
    AnyTransition("push(\(edge._transitionCode))", insertion: _TransitionState.move(edge).combined(with: .opacity(0)), removal: _TransitionState.move(edge.opposite).combined(with: .opacity(0)))
  }
  public func combined(with other: AnyTransition) -> AnyTransition {
    nonisolated(unsafe) let first = self, second = other
    let resolver: _TransitionResolver? = self.resolver == nil && other.resolver == nil ? nil : _TransitionResolver { context in
      let first = first.resolved(in: context), second = second.resolved(in: context)
      return (first.insertion.combined(with: second.insertion), first.removal.combined(with: second.removal))
    }
    return AnyTransition("combined(\(name),\(other.name))", insertion: insertion.combined(with: other.insertion), removal: removal.combined(with: other.removal), animation: animation ?? other.animation, insertionAnimation: insertionAnimation ?? other.insertionAnimation, removalAnimation: removalAnimation ?? other.removalAnimation, resolver: resolver, playback: playback ?? other.playback)
  }
  /// The transition played with `animation` instead of the commit's.
  public func animation(_ animation: Animation?) -> AnyTransition {
    AnyTransition(name, insertion: insertion, removal: removal, animation: animation, resolver: resolver, playback: playback)
  }
  public static func modifier<Active: ViewModifier, Identity: ViewModifier>(active: Active, identity: Identity) -> AnyTransition {
    nonisolated(unsafe) let active = active, identity = identity
    let resolver = _TransitionResolver { context in
      let placeholder = AnyView(Color.clear)
      let activeNode = placeholder.modifier(active)._render(in: context.child(_FiberKey("transition-active")))
      let identityNode = placeholder.modifier(identity)._render(in: context.child(_FiberKey("transition-identity")))
      let baseline = placeholder._render(in: context.child(_FiberKey("transition-base")))
      var state = _transitionDelta(active: activeNode, identity: identityNode)
      state.restingCSS = _transitionDelta(active: identityNode, identity: baseline).css
      return (state, state)
    }
    return AnyTransition("modifier(\(_swiftUIWebTypeName(Active.self)),\(_swiftUIWebTypeName(Identity.self)))", resolver: resolver)
  }
  /// The transition of a `Transition` value: its `body` is rendered for each phase.
  public init<T: Transition>(_ transition: T) {
    if let builtIn = transition._swiftUIWebAnyTransition {
      self = builtIn
      return
    }
    nonisolated(unsafe) let transition = transition
    let resolver = _TransitionResolver { context in
      let placeholder = { PlaceholderContentView<T>(AnyView(Color.clear)) }
      let identity = transition.body(content: placeholder(), phase: .identity)._render(in: context.child(_FiberKey("transition-identity")))
      let appearing = transition.body(content: placeholder(), phase: .willAppear)._render(in: context.child(_FiberKey("transition-appear")))
      let disappearing = transition.body(content: placeholder(), phase: .didDisappear)._render(in: context.child(_FiberKey("transition-disappear")))
      let baseline = placeholder()._render(in: context.child(_FiberKey("transition-base")))
      let resting = _transitionDelta(active: identity, identity: baseline).css
      var insertion = _transitionDelta(active: appearing, identity: identity), removal = _transitionDelta(active: disappearing, identity: identity)
      insertion.restingCSS = resting
      removal.restingCSS = resting
      return (insertion, removal)
    }
    self.init(_swiftUIWebTypeName(T.self), resolver: resolver)
  }
  /// A source-compatible token used by apps that animate a symbol replacement: an opacity transition here.
  package static var symbolEffect: AnyTransition { AnyTransition("symbol-effect", insertion: .opacity(0)) }

  @MainActor func resolved(in context: _RenderContext) -> (insertion: _TransitionState, removal: _TransitionState) {
    resolver?.render(context) ?? (insertion, removal)
  }
}

private extension Double {
  var transitionClean: String { truncatingRemainder(dividingBy: 1) == 0 && magnitude < 1e15 ? String(Int64(self)) : String(self) }
}

// MARK: Transition (iOS 17)

public enum TransitionPhase: Hashable, Sendable {
  case willAppear
  case identity
  case didDisappear
  public var isIdentity: Bool { self == .identity }
  /// -1 before the view appears, 0 at identity, 1 once it disappeared.
  public var value: Double {
    switch self {
    case .willAppear: return -1
    case .identity: return 0
    case .didDisappear: return 1
    }
  }
}

public struct TransitionProperties: Sendable {
  public var hasMotion: Bool
  public init(hasMotion: Bool = true) { self.hasMotion = hasMotion }
}

@MainActor @preconcurrency public protocol Transition {
  associatedtype Body: View
  typealias Content = PlaceholderContentView<Self>
  @ViewBuilder @MainActor @preconcurrency func body(content: Self.Content, phase: TransitionPhase) -> Self.Body
  @MainActor @preconcurrency static var properties: TransitionProperties { get }
  /// The transitions the framework knows the active states of, so that no phase has to be rendered for them.
  nonisolated var _swiftUIWebAnyTransition: AnyTransition? { get }
}

public extension Transition {
  @MainActor @preconcurrency static var properties: TransitionProperties { TransitionProperties() }
  nonisolated var _swiftUIWebAnyTransition: AnyTransition? { nil }
  /// The view `content` styled as this transition does in `phase`.
  nonisolated func apply<V: View>(content: V, phase: TransitionPhase) -> some View {
    _TransitionApplied(transition: self, content: content, phase: phase)
  }
  @MainActor @preconcurrency func animation(_ animation: Animation?) -> some Transition {
    _AnimatedTransition(base: self, animation: animation)
  }
  @MainActor @preconcurrency func combined<T: Transition>(with other: T) -> some Transition {
    _CombinedTransition(first: self, second: other)
  }
}

private nonisolated struct _TransitionApplied<T: Transition, V: View>: View {
  let transition: T
  let content: V
  let phase: TransitionPhase
  @MainActor var body: some View { transition.body(content: PlaceholderContentView<T>(AnyView(content)), phase: phase) }
}

private nonisolated struct _AnimatedTransition<Base: Transition>: Transition {
  let base: Base
  let animation: Animation?
  func body(content: Content, phase: TransitionPhase) -> some View {
    base.apply(content: content, phase: phase)
  }
  nonisolated var _swiftUIWebAnyTransition: AnyTransition? { AnyTransition(base).animation(animation) }
}

private nonisolated struct _CombinedTransition<First: Transition, Second: Transition>: Transition {
  let first: First
  let second: Second
  func body(content: Content, phase: TransitionPhase) -> some View {
    second.apply(content: first.apply(content: content, phase: phase), phase: phase)
  }
  nonisolated var _swiftUIWebAnyTransition: AnyTransition? { AnyTransition(first).combined(with: AnyTransition(second)) }
}

public nonisolated struct IdentityTransition: Transition {
  nonisolated public init() {}
  nonisolated public func body(content: IdentityTransition.Content, phase: TransitionPhase) -> IdentityTransition.Content { content }
  public static let properties = TransitionProperties(hasMotion: false)
  public var _swiftUIWebAnyTransition: AnyTransition? { .identity }
}

public nonisolated struct OpacityTransition: Transition {
  nonisolated public init() {}
  nonisolated public func body(content: OpacityTransition.Content, phase: TransitionPhase) -> some View {
    content.opacity(phase.isIdentity ? 1 : 0)
  }
  public static let properties = TransitionProperties(hasMotion: false)
  public var _swiftUIWebAnyTransition: AnyTransition? { .opacity }
}

public nonisolated struct ScaleTransition: Transition {
  public var scale: Double
  public var anchor: UnitPoint
  nonisolated public init(_ scale: Double, anchor: UnitPoint = .center) { self.scale = scale; self.anchor = anchor }
  nonisolated public func body(content: ScaleTransition.Content, phase: TransitionPhase) -> some View {
    // What `scaleEffect(_:anchor:)` writes: that modifier is in SwiftUIWebFeatures, above this module.
    let value = phase.isIdentity ? 1 : scale
    return content.modifier(_SemanticCompatibilityModifier(styles: ["transform": "scale(\(value))", "transform-origin": "\(anchor.x * 100)% \(anchor.y * 100)%"]))
  }
  public var _swiftUIWebAnyTransition: AnyTransition? {
    scale == 1e-5 && anchor == .center ? .scale : .scale(scale: scale, anchor: anchor)
  }
}

public nonisolated struct MoveTransition: Transition {
  public var edge: Edge
  nonisolated public init(edge: Edge) { self.edge = edge }
  nonisolated public func body(content: MoveTransition.Content, phase: TransitionPhase) -> some View { content }
  public var _swiftUIWebAnyTransition: AnyTransition? { .move(edge: edge) }
}

public nonisolated struct OffsetTransition: Transition {
  public var offset: CGSize
  nonisolated public init(_ offset: CGSize) { self.offset = offset }
  nonisolated public func body(content: OffsetTransition.Content, phase: TransitionPhase) -> some View {
    content.offset(x: phase.isIdentity ? 0 : offset.width, y: phase.isIdentity ? 0 : offset.height)
  }
  public var _swiftUIWebAnyTransition: AnyTransition? { .offset(offset) }
}

public nonisolated struct SlideTransition: Transition {
  nonisolated public init() {}
  nonisolated public func body(content: SlideTransition.Content, phase: TransitionPhase) -> some View { content }
  public var _swiftUIWebAnyTransition: AnyTransition? { .slide }
}

public nonisolated struct PushTransition: Transition {
  public var edge: Edge
  nonisolated public init(edge: Edge) { self.edge = edge }
  nonisolated public func body(content: PushTransition.Content, phase: TransitionPhase) -> some View { content }
  public var _swiftUIWebAnyTransition: AnyTransition? { .push(from: edge) }
}

@MainActor @preconcurrency public struct BlurReplaceTransition: Transition {
  public struct Configuration: Equatable, Sendable {
    let removalScale: Double
    let insertionScale: Double
    /// Inserted views grow into place, removed ones grow away.
    public static let downUp = Configuration(removalScale: 1.2, insertionScale: 0.8)
    /// Inserted views shrink into place, removed ones grow away.
    public static let upUp = Configuration(removalScale: 1.2, insertionScale: 1.2)
  }
  @MainActor @preconcurrency public var configuration: BlurReplaceTransition.Configuration
  @MainActor @preconcurrency public init(configuration: BlurReplaceTransition.Configuration) { self.configuration = configuration }
  @MainActor @preconcurrency public func body(content: BlurReplaceTransition.Content, phase: TransitionPhase) -> some View { content }
  nonisolated public var _swiftUIWebAnyTransition: AnyTransition? {
    let insertion = _TransitionState.opacity(0).combined(with: .blur(10)).combined(with: .scale(configuration.insertionScale, anchor: .center))
    let removal = _TransitionState.opacity(0).combined(with: .blur(10)).combined(with: .scale(configuration.removalScale, anchor: .center))
    let name = configuration == .downUp ? "blur-replace(down-up)" : "blur-replace(up-up)"
    return AnyTransition(name, insertion: insertion, removal: removal)
  }
}

public nonisolated struct AsymmetricTransition<Insertion: Transition, Removal: Transition>: Transition {
  public var insertion: Insertion
  public var removal: Removal
  nonisolated public init(insertion: Insertion, removal: Removal) { self.insertion = insertion; self.removal = removal }
  nonisolated public func body(content: AsymmetricTransition<Insertion, Removal>.Content, phase: TransitionPhase) -> some View {
    switch phase {
    case .willAppear: insertion.apply(content: content, phase: phase)
    default: removal.apply(content: content, phase: phase)
    }
  }
  public static var properties: TransitionProperties {
    // Both sides' properties are main-actor state; the browser plays every transition, so it reports motion.
    TransitionProperties()
  }
  public var _swiftUIWebAnyTransition: AnyTransition? {
    .asymmetric(insertion: AnyTransition(insertion), removal: AnyTransition(removal))
  }
}

public extension Transition where Self == IdentityTransition {
  nonisolated static var identity: IdentityTransition { Self() }
}
public extension Transition where Self == OpacityTransition {
  @MainActor @preconcurrency static var opacity: OpacityTransition { Self() }
}
public extension Transition where Self == ScaleTransition {
  @MainActor @preconcurrency static var scale: ScaleTransition { Self(1e-5) }
  @MainActor @preconcurrency static func scale(_ scale: Double, anchor: UnitPoint = .center) -> Self { Self(scale, anchor: anchor) }
}
public extension Transition where Self == MoveTransition {
  @MainActor @preconcurrency static func move(edge: Edge) -> Self { Self(edge: edge) }
}
public extension Transition where Self == OffsetTransition {
  @MainActor @preconcurrency static func offset(_ offset: CGSize) -> Self { Self(offset) }
  @MainActor @preconcurrency static func offset(x: CGFloat = 0, y: CGFloat = 0) -> Self { offset(CGSize(width: Double(x), height: Double(y))) }
}
public extension Transition where Self == SlideTransition {
  @MainActor @preconcurrency static var slide: SlideTransition { Self() }
}
public extension Transition where Self == PushTransition {
  @MainActor @preconcurrency static func push(from edge: Edge) -> Self { Self(edge: edge) }
}
public extension Transition where Self == BlurReplaceTransition {
  @MainActor @preconcurrency static func blurReplace(_ config: BlurReplaceTransition.Configuration = .downUp) -> Self { Self(configuration: config) }
  @MainActor @preconcurrency static var blurReplace: BlurReplaceTransition { blurReplace(.downUp) }
}

public extension View {
  @_disfavoredOverload
  nonisolated func transition(_ t: AnyTransition) -> some View {
    modifier(_transitionModifier(t))
  }
  nonisolated func transition<T: Transition>(_ transition: T) -> some View {
    modifier(_transitionModifier(AnyTransition(transition)))
  }
}

// MARK: Symbol effect options

/// How a symbol effect plays: how many times and how fast. Here, below the effects themselves (SwiftUIWebFeatures), because a
/// transition made of a symbol effect keeps them.
public struct SymbolEffectOptions: Hashable, Sendable {
  package let repeatCount: Int?
  package let speedValue: Double
  init(repeatCount: Int?, speed: Double = 1) { self.repeatCount = repeatCount; self.speedValue = speed }
  public static let `default` = SymbolEffectOptions(repeatCount: nil)
  public static let nonRepeating = SymbolEffectOptions(repeatCount: 1)
  public static let `repeating` = SymbolEffectOptions(repeatCount: 0)
  /// `nil` repeats the effect's own way.
  public static func `repeat`(_ count: Int?) -> SymbolEffectOptions { SymbolEffectOptions.default.repeat(count) }
  public static func speed(_ speed: Double) -> SymbolEffectOptions { SymbolEffectOptions.default.speed(speed) }
  /// Plays the effect `speed` times as fast.
  public func speed(_ speed: Double) -> SymbolEffectOptions { SymbolEffectOptions(repeatCount: repeatCount, speed: speed > 0 && speed.isFinite ? speedValue * speed : speedValue) }
  public func `repeat`(_ count: Int?) -> SymbolEffectOptions { SymbolEffectOptions(repeatCount: count.map { max($0, 1) }, speed: speedValue) }
  public var nonRepeating: SymbolEffectOptions { SymbolEffectOptions(repeatCount: 1, speed: speedValue) }
  public var repeating: SymbolEffectOptions { SymbolEffectOptions(repeatCount: 0, speed: speedValue) }

  /// The attributes the host reads: repeats (0 forever, absent the effect's own) and speed (absent at 1).
  package var attributes: _NodeValues {
    var values = _NodeValues()
    if let repeatCount { values["data-symbol-effect-repeat"] = String(repeatCount) }
    if speedValue != 1 { values["data-symbol-effect-speed"] = String(speedValue) }
    return values
  }
}
