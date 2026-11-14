@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

/// Holds a value that is not `Sendable` so a main-actor closure (which is implicitly `Sendable`) can use it:
/// the box is main-actor isolated, and so is every closure that reads it.
@MainActor final class _MainActorBox<Value> {
  nonisolated(unsafe) let value: Value
  nonisolated init(_ value: Value) { self.value = value }
}
