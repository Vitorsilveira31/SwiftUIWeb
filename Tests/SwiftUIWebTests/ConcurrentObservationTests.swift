import Foundation
import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber
import SwiftUIWeb

/// Observable models change on whatever thread the caller is on. A tree that
/// reads several of them must tolerate their callbacks arriving together.
@Suite
@MainActor
struct ConcurrentObservationTests {
  // Shared across threads on purpose, without synchronization: the test is that the runtime survives it.
  @Observable final class Counter: @unchecked Sendable { var value = 0 }

  private struct Reader: View {
    let first: Counter
    let second: Counter
    var body: some View { Text("\(first.value)-\(second.value)") }
  }

  @Test
  func observationCallbacksFromSeveralThreadsDoNotTrapTheRuntime() {
    let first = Counter(), second = Counter()
    let tree = FiberTree(Reader(first: first, second: second), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    _ = tree.renderNode
    let group = DispatchGroup()
    for worker in 0..<8 {
      DispatchQueue.global().async(group: group) {
        for step in 0..<300 {
          if (worker + step) % 2 == 0 { first.value += 1 } else { second.value += 1 }
        }
      }
    }
    group.wait()
    // Unsynchronized `+=` from several threads loses updates, so only the
    // survival of the tree is asserted: it still renders after the storm.
    #expect(tree.renderNode.htmlDescription.contains("-"))
  }
}
