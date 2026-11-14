@_spi(Renderer) import SwiftUIWebTransferable
@_spi(Renderer) import SwiftUIWebLocking

/// Render-pass state that SwiftUI keeps implicit while a view graph update
/// runs: the environment installed for the view being evaluated, the active
/// state scope, the animation transaction and the diagnostic memory
/// counters.
///
/// A render pass is synchronous and never suspends, so this state is confined
/// to the thread that performs it. The browser runtime is single-threaded and
/// uses one instance. Native hosts (tests, tooling, previews) may evaluate
/// independent view graphs concurrently; each thread therefore owns its own
/// instance so one graph can never observe another graph's scope or
/// environment in the middle of an evaluation.
final class _RenderThreadState: @unchecked Sendable {
  var environment: EnvironmentValues?
  var stateScope: StateScope?
  var animation: Animation?
  var animationActive = false
  /// The transaction `withTransaction` or `withAnimation` runs its body in.
  var transaction: Transaction?
  let staging = _RenderStagingState()
  let nodeGraveyard = _NodeGraveyard()
  let closureGraveyard = _ClosureGraveyard()
  let memoryCounters = _RuntimeMemoryCounters()

  private static let storage = _ThreadLocal { _RenderThreadState() }
  static var current: _RenderThreadState { storage.current }
}
