import Testing
@_spi(Renderer) @testable import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFiber
import SwiftUIWeb

/// An `AnyView` is named by the type it holds (`View._swiftUIWebTypeTag`). One that holds another `AnyView` holds what
/// that one holds, so a chain of erasures is named by the type it finally holds: when that type changes the fiber is
/// replaced, and while it stays the fiber is kept, however many `AnyView`s wrap it.
@MainActor
struct AnyViewIdentityTests {
  private struct A: View {
    var text = "a"
    var appear: () -> Void
    var disappear: () -> Void
    var body: some View { Text(text).onAppear(perform: appear).onDisappear(perform: disappear) }
  }

  private struct B: View {
    var appear: () -> Void
    var disappear: () -> Void
    var body: some View { Text("b").onAppear(perform: appear).onDisappear(perform: disappear) }
  }

  /// Holds the action that bumps the `@State` of the view that rendered last.
  private final class Bump { var action: () -> Void = {} }
  private struct Counting: View {
    @State private var count = 0
    let bump: Bump
    var body: some View {
      let binding = $count
      bump.action = { binding.wrappedValue += 1 }
      return Text("counting:\(count)")
    }
  }
  private struct OtherCounting: View {
    @State private var count = 0
    let bump: Bump
    var body: some View {
      let binding = $count
      bump.action = { binding.wrappedValue += 1 }
      return Text("other:\(count)")
    }
  }

  /// Shows `Counting` under two erasures, or `OtherCounting` once `swap` ran. `touch` renders it again as it was.
  private struct Host: View {
    @State private var other = false
    @State private var touches = 0
    let bump: Bump
    let swap: Bump
    let touch: Bump
    var body: some View {
      let otherBinding = $other
      let touchBinding = $touches
      swap.action = { otherBinding.wrappedValue = true }
      touch.action = { touchBinding.wrappedValue += 1 }
      _ = touches
      // One expression of one type, so that no conditional tells the two apart: only the erased type does.
      return other ? AnyView(AnyView(OtherCounting(bump: bump))) : AnyView(AnyView(Counting(bump: bump)))
    }
  }

  private func host(_ run: (FiberTree, _ bump: Bump, _ swap: Bump, _ touch: Bump) -> Void) {
    let bump = Bump(), swap = Bump(), touch = Bump()
    let tree = FiberTree(Host(bump: bump, swap: swap, touch: touch))
    defer { tree._dispose() }
    _ = tree.renderNode
    run(tree, bump, swap, touch)
  }

  private struct Lifecycle: Equatable {
    var appears: Int
    var disappears: Int
    static let kept = Lifecycle(appears: 1, disappears: 0)
    static let replaced = Lifecycle(appears: 2, disappears: 1)
  }

  private func lifecycle<First: View, Second: View>(
    from first: (_ appear: @escaping () -> Void, _ disappear: @escaping () -> Void) -> First,
    to second: (_ appear: @escaping () -> Void, _ disappear: @escaping () -> Void) -> Second
  ) -> Lifecycle {
    var appears = 0
    var disappears = 0
    let tree = FiberTree(first({ appears += 1 }, { disappears += 1 }))
    defer { tree._dispose() }
    _ = tree.renderNode
    _ = tree.update(second({ appears += 1 }, { disappears += 1 }))
    _ = tree.renderNode
    return Lifecycle(appears: appears, disappears: disappears)
  }

  @Test func `Two erasures of one type are replaced when the type changes`() {
    let result = lifecycle(
      from: { a, d in AnyView(AnyView(A(appear: a, disappear: d))) },
      to: { a, d in AnyView(AnyView(B(appear: a, disappear: d))) })
    #expect(result == .replaced)
  }

  @Test func `Three erasures of one type are replaced when the type changes`() {
    let result = lifecycle(
      from: { a, d in AnyView(AnyView(AnyView(A(appear: a, disappear: d)))) },
      to: { a, d in AnyView(AnyView(AnyView(B(appear: a, disappear: d)))) })
    #expect(result == .replaced)
  }

  @Test func `A chain of erasures is kept while its type is the same`() {
    let result = lifecycle(
      from: { a, d in AnyView(AnyView(A(text: "one", appear: a, disappear: d))) },
      to: { a, d in AnyView(AnyView(A(text: "two", appear: a, disappear: d))) })
    #expect(result == .kept)
  }

  @Test func `One more erasure of the same type keeps the fiber`() {
    // Assumption: SwiftUI names an AnyView by the type it wraps, and does not tell an AnyView holding an AnyView holding
    // A from one holding A. Nothing in Apple's documentation says it otherwise.
    let result = lifecycle(
      from: { a, d in AnyView(A(appear: a, disappear: d)) },
      to: { a, d in AnyView(AnyView(A(appear: a, disappear: d))) })
    #expect(result == .kept)
  }

  @Test func `State starts fresh when the type under two erasures changes`() {
    host { tree, bump, swap, _ in
      bump.action()
      #expect(tree.renderNode.htmlDescription.contains("counting:1"))
      swap.action()
      #expect(tree.renderNode.htmlDescription.contains("other:0"))
    }
  }

  @Test func `State carries over while the type under two erasures is the same`() {
    host { tree, bump, _, touch in
      bump.action()
      #expect(tree.renderNode.htmlDescription.contains("counting:1"))
      touch.action()
      #expect(tree.renderNode.htmlDescription.contains("counting:1"))
    }
  }
}
