// SwiftUI's transactions: the context of one state change (its animation, whether animations are off, values set
// through `TransactionKey`, completions), and the modifiers that change it for a subtree.
//
// `withAnimation` and `withTransaction` make the transaction current while their body changes state; the state store
// keeps it for the commit that follows (`StateStore._commitTransaction`). The page plays the commit's animation for what
// CSS animates (the root's `data-animation-transaction`); a `.transaction` or `.animation(_:value:)` modifier changes
// it for its subtree (`data-transaction-timing`), and Swift reads the subtree's transaction for what it animates itself
// (`Animator.swift`).

/// A key for a value carried by a transaction.
public protocol TransactionKey {
  associatedtype Value
  static var defaultValue: Self.Value { get }
}

/// The context of the current state change: how it animates, and the values and completions that go with it.
public struct Transaction: Hashable, @unchecked Sendable {
  public var animation: Animation?
  public var disablesAnimations: Bool
  /// Whether the change is part of a continuous interaction (a drag), whose views should not animate each step.
  public var isContinuous: Bool
  /// Whether animations follow the velocity of the interaction that ends in this change.
  public var tracksVelocity: Bool
  var values = _TypedValueStorage<ObjectIdentifier>()
  var completions: [(criteria: AnimationCompletionCriteria, run: () -> Void)] = []

  public init() {
    animation = nil
    disablesAnimations = false
    isContinuous = false
    tracksVelocity = false
  }

  public init(animation: Animation?) {
    self.init()
    self.animation = animation
  }

  public subscript<K>(key: K.Type) -> K.Value where K: TransactionKey {
    get { values.value(for: _storedTypeID(key), as: K.Value.self) ?? K.defaultValue }
    set { values.set(newValue, for: _storedTypeID(key)) }
  }

  /// Runs `completion` once the animation of this transaction meets `criteria`.
  public mutating func addAnimationCompletion(criteria: AnimationCompletionCriteria = .logicallyComplete, _ completion: @escaping () -> Void) {
    completions.append((criteria, completion))
  }

  /// The animation that plays: none when animations are disabled.
  var effectiveAnimation: Animation? { disablesAnimations ? nil : animation }

  /// Schedules the completions added since `start`, against this transaction's animation.
  func scheduleCompletions(from start: Int = 0) {
    guard start < completions.count else { return }
    for entry in completions[start...] { _scheduleAnimationCompletion(effectiveAnimation, criteria: entry.criteria, entry.run) }
  }

  public static func == (lhs: Transaction, rhs: Transaction) -> Bool {
    lhs.animation == rhs.animation && lhs.disablesAnimations == rhs.disablesAnimations &&
      lhs.isContinuous == rhs.isContinuous && lhs.tracksVelocity == rhs.tracksVelocity
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(animation)
    hasher.combine(disablesAnimations)
    hasher.combine(isContinuous)
    hasher.combine(tracksVelocity)
  }
}

/// Runs `completion` once `animation` meets `criteria`: at once without an animation, never for one that repeats forever.
func _scheduleAnimationCompletion(_ animation: Animation?, criteria: AnimationCompletionCriteria, _ completion: @escaping () -> Void) {
  guard let animation else { completion(); return }
  guard let delay = animation._completionDelay(criteria) else { return }
  if let schedule = _animationCompletionScheduler { schedule(delay, completion) } else { completion() }
}

/// Runs `body` in `transaction`: its state changes animate with the transaction's animation (none when it disables
/// animations), carry its values, and its completions run once that animation completes.
@discardableResult
public func withTransaction<Result>(_ transaction: Transaction, _ body: () throws -> Result) rethrows -> Result {
  let thread = _RenderThreadState.current
  let previous = thread.transaction
  let previousAnimation = thread.animation
  let wasActive = thread.animationActive
  thread.transaction = transaction
  thread.animation = transaction.effectiveAnimation
  thread.animationActive = true
  defer {
    thread.transaction = previous
    thread.animation = previousAnimation
    thread.animationActive = wasActive
  }
  let result = try body()
  transaction.scheduleCompletions()
  return result
}

/// Runs `body` in the current transaction with `keyPath` set to `value`.
@discardableResult
public func withTransaction<R, V>(_ keyPath: WritableKeyPath<Transaction, V>, _ value: V, _ body: () throws -> R) rethrows -> R {
  var transaction = _RenderThreadState.current.transaction ?? Transaction()
  transaction.completions = []
  transaction[keyPath: keyPath] = value
  return try withTransaction(transaction, body)
}

extension _RenderContext {
  /// The transaction of the changes this render shows here: the commit's, as `.transaction` modifiers above changed it.
  var _transaction: Transaction? { _transactionOverride ?? stateStore._commitTransaction }
}

/// `.transaction(_:)`: the transaction of the changes below runs through `transform`.
nonisolated struct _TransactionModifier: ViewModifier {
  let transform: (inout Transaction) -> Void

  @MainActor func _modifyContext(_ context: inout _RenderContext) {
    let committed = context.stateStore._commitTransaction != nil
    var transaction = context._transaction ?? Transaction()
    let inherited = transaction.effectiveAnimation != nil
    let count = transaction.completions.count
    transform(&transaction)
    if transaction.effectiveAnimation != nil { context._animationCleared = false } else if inherited { context._animationCleared = true }
    // Completions added here belong to this commit's changes: schedule them once, in the render the commit drives.
    if committed { transaction.scheduleCompletions(from: count) }
    transaction.completions = []
    context._transactionOverride = transaction
  }

  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    // What the page plays for this subtree in this commit: the transformed animation, or none.
    if context.stateStore._commitTransaction != nil || context._transactionOverride?.effectiveAnimation != nil || context._animationCleared {
      node.attributes["data-transaction-timing"] = context._transactionOverride?.effectiveAnimation?.cssValue ?? "none"
    }
  }
}

/// `.transaction(value:_:)`: like `.transaction(_:)`, for the commits in which `value` changed.
nonisolated struct _ValueTransactionModifier<Value: Equatable>: ViewModifier {
  let value: Value
  let transform: (inout Transaction) -> Void

  @MainActor func _modifyContext(_ context: inout _RenderContext) {
    // A speculative render (the hovered look of a hover effect) must not advance the history of the real one.
    guard !context._speculative else { return }
    let key = context._modifierStateKey("#transaction-value")
    let previous = context.stateStore._animatorValues.value(for: key, as: Value.self)
    context.stateStore._animatorValues.set(value, for: key)
    guard let previous, previous != value else { return }
    _TransactionModifier(transform: transform)._modifyContext(&context)
  }

  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    guard let transaction = context._transactionOverride else { return }
    node.attributes["data-transaction-timing"] = transaction.effectiveAnimation?.cssValue ?? "none"
  }
}

public extension View {
  /// Changes the transaction of the state changes this view shows.
  nonisolated func transaction(_ transform: @escaping (inout Transaction) -> Void) -> some View {
    _modified(_TransactionModifier(transform: transform))
  }

  /// Changes the transaction of the state changes this view shows, in the commits in which `value` changed.
  nonisolated func transaction(value: some Equatable, _ transform: @escaping (inout Transaction) -> Void) -> some View {
    _modified(_ValueTransactionModifier(value: value, transform: transform))
  }

  /// Changes the transaction for the modifiers `body` applies to this view, and only for them.
  nonisolated func transaction<V>(_ transform: @escaping (inout Transaction) -> Void, @ContentBuilder body: (PlaceholderContentView<Self>) -> V) -> some View where V: View {
    _ScopedTransaction(transform: transform, content: body(PlaceholderContentView(AnyView(self))))
  }

  /// Animates the changes of the modifiers `body` applies to this view with `animation`, and only those.
  nonisolated func animation<V>(_ animation: Animation?, @ContentBuilder body: (PlaceholderContentView<Self>) -> V) -> some View where V: View {
    transaction({ transaction in
      guard !transaction.disablesAnimations else { return }
      transaction.animation = animation
    }, body: body)
  }
}

/// The transaction override a placeholder is rendered with (see `_RenderContext._placeholderTransaction`).
///
/// A reference, not a value: the render context is copied into every level of the recursion, and this is set only under a
/// scoped transaction, so it costs a pointer in each frame.
package final class _PlaceholderTransaction {
  let override: Transaction?
  let cleared: Bool
  init(override: Transaction?, cleared: Bool) { self.override = override; self.cleared = cleared }
}

/// The view `transaction(_:body:)` returns: `content` (the modified placeholder) under the changed transaction. What
/// Swift animates in it follows that transaction; the page animates the node, so CSS properties of the whole node do.
nonisolated struct _ScopedTransaction<Content: View>: View {
  typealias Body = Never
  let transform: (inout Transaction) -> Void
  let content: Content

  @MainActor func _render(in context: _RenderContext) -> _RenderNode {
    var scoped = context
    scoped._placeholderTransaction = _PlaceholderTransaction(override: context._transactionOverride, cleared: context._animationCleared)
    _TransactionModifier(transform: transform)._modifyContext(&scoped)
    let node = content._render(in: scoped)
    var applied = scoped
    _TransactionModifier(transform: transform)._apply(to: node, context: &applied)
    return node
  }
}

// MARK: The view a closure modifies

/// SwiftUI exposes the first argument of the phase/keyframe modifier content
/// closures as `PlaceholderContentView<Self>`. SwiftUIWeb's renderer already
/// has the corresponding erased view value (`AnyView`), so keep the public
/// spelling source-compatible without adding another wrapper node (which
/// would change Fiber identity and make state appear to reset on every phase).
/// The content view handed to phase and keyframe animator closures. It forwards
/// rendering to the animated base view, so no extra node enters the tree.
public nonisolated struct PlaceholderContentView<Value>: View {
  public typealias Body = Never
  private let base: AnyView

  package init(_ base: AnyView) { self.base = base }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    // Under `transaction(_:body:)` the view itself keeps the transaction it came in with: the changed one is for the
    // modifiers the closure applies.
    guard let placeholder = context._placeholderTransaction else { return base._render(in: context) }
    var inner = context
    inner._transactionOverride = placeholder.override
    inner._animationCleared = placeholder.cleared
    inner._placeholderTransaction = nil
    return base._render(in: inner)
  }
}
