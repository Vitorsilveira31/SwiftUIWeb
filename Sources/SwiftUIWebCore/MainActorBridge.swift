/// Entry points that let Apple's nonisolated property wrappers and bindings reach the
/// main-actor-isolated state runtime.
///
/// SwiftUI declares `State`, `Binding`, `Environment`, `FocusState` and friends without
/// global-actor isolation, so application code may form and read them from any context.
/// SwiftUIWeb's state store, render scope and observation tables are main-actor isolated
/// (and, in the browser, single-threaded). The wrappers therefore hop into that world through
/// the helpers below instead of carrying `@MainActor` on their public declarations.
///
/// `MainActor.assumeIsolated` is not used: it traps when the caller is not on the main
/// executor, which is the case for plain unit tests and for nonisolated application helpers
/// that only touch a `Binding` while the runtime is idle. The wrappers never suspend, so a
/// caller that violates the single-threaded contract races exactly as SwiftUI's own
/// location-based storage would; it cannot deadlock or trap.

/// Runs `body` as if it were on the main actor, without a dynamic executor check.
///
/// SAFETY: a `@MainActor` synchronous function value has the same representation as a
/// nonisolated one (the actor is not part of its calling convention), so erasing the
/// isolation only removes the compiler's static check.
@inline(__always)
package func _assumeMainActor<Result>(_ body: @MainActor () -> Result) -> Result {
  withoutActuallyEscaping(body) { escapable in
    unsafeBitCast(escapable, to: (() -> Result).self)()
  }
}

/// Erases the isolation of a closure received through Apple's `@isolated(any)` parameters.
///
/// SAFETY: a synchronous `@isolated(any)` function value is called with the same convention
/// as a nonisolated one; the isolation only names the actor the body expects to run on. The
/// binding's callers read and write it on the main thread, which is where the closures
/// formed inside a SwiftUI-shaped body are isolated.
///
/// `@isolated(any)` values need runtime support that macOS ships from 15 on, while the package
/// floor is lower; callers on the native build check availability (the Embedded runtime has
/// no such floor).
@inline(__always)
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
func _erasingIsolation<Result>(_ function: @escaping @isolated(any) @Sendable () -> Result) -> () -> Result {
  unsafeBitCast(function, to: (() -> Result).self)
}

@inline(__always)
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
func _erasingIsolation<Argument>(_ function: @escaping @isolated(any) @Sendable (Argument) -> Void) -> (Argument) -> Void {
  unsafeBitCast(function, to: ((Argument) -> Void).self)
}
