import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFiber

/// What a binary publication leaves in the fibers (Documentation/Architecture/BINARY_PATCHES.md, "Swift side"), and what a
/// later publication reads from them to decide what the host already holds.
///
/// A fiber's element is held by a host that acknowledged the epoch the element was first published in, or a later one
/// (`Fiber.firstPublishedEpoch`). The host applies only the newest publication it has when it commits, so an acknowledged
/// epoch says that the host holds what that publication and every one before it that it read carried: a fiber that a
/// publication visited is visited again by the following ones until the host acknowledges one of them
/// (`Fiber.publishedEpoch` above the acknowledged epoch), which is how a publication the host dropped is made good.
@MainActor
package enum BinaryHeldState {
  package static func record(of fiber: Fiber) -> BinaryNodeRecord {
    BinaryNodeRecord(firstEpoch: fiber.firstPublishedEpoch, idHash: fiber.publishedIDHash, ownHash: fiber.publishedOwnHash, ownSince: fiber.ownHashSince,
                     childrenHash: fiber.publishedChildrenHash, childrenSince: fiber.childrenHashSince, ownsState: fiber.publishedOwnsState)
  }

  /// Whether the host holds the tree the fibers' records describe, so that a publication lists changes to it. The record of
  /// the tree is the one of the list of the page's own children, kept apart from the records of the fibers: the root
  /// fiber's element is one of that list.
  package static func holdsTree(_ record: BinaryNodeRecord, acked: UInt64) -> Bool {
    record.firstEpoch != 0 && record.firstEpoch <= acked
  }

  /// Whether a placeholder may stand for `fiber`'s element: the host holds it, and nothing about it changed or was
  /// published since the epoch the host acknowledged. (What else keeps a fiber from being left out is the snapshot's to
  /// decide: state the host keeps, a layout block that changed.)
  package static func holds(_ fiber: Fiber, acked: UInt64) -> Bool {
    fiber.firstPublishedEpoch != 0 && fiber.firstPublishedEpoch <= acked && fiber.version <= acked && fiber.publishedEpoch <= acked
  }

  private static func forget(_ fiber: Fiber, epoch: UInt64) {
    fiber.firstPublishedEpoch = 0
    fiber.publishedOwnsState = false
    fiber.publishedHostOwned = false
    fiber.publishedEpoch = epoch
  }

  /// Records `output`, the publication of epoch `covered`, in the fibers a snapshot visited (`visited`: the fiber, the copy
  /// that stands for it, and whether it sits in content the page replaces or manages, whose elements the page does not keep)
  /// and in the placeholders that stood for the others (`kept`).
  package static func published(_ output: BinaryFiberEncoder.Output, visited: [(fiber: Fiber, copy: _RenderNode, inHostContent: Bool)], kept: [(fiber: Fiber, node: _RenderNode)], covered: UInt64) {
    var byCopy: [ObjectIdentifier: Fiber] = .init()
    byCopy.reserveCapacity(visited.count + kept.count)
    for entry in visited { byCopy[ObjectIdentifier(entry.copy)] = entry.fiber }
    for entry in kept { byCopy[ObjectIdentifier(entry.node)] = entry.fiber }
    // What the encoder did not reach is not in the host's hands: a fiber below a node that is not in the DOM.
    for entry in visited { forget(entry.fiber, epoch: covered) }
    for update in output.updates {
      guard let fiber = byCopy[ObjectIdentifier(update.node)] else { continue }
      fiber.firstPublishedEpoch = update.record.firstEpoch
      fiber.publishedIDHash = update.record.idHash
      fiber.publishedOwnHash = update.record.ownHash
      fiber.ownHashSince = update.record.ownSince
      fiber.publishedChildrenHash = update.record.childrenHash
      fiber.childrenHashSince = update.record.childrenSince
      fiber.publishedOwnsState = update.record.ownsState
    }
    // The page keeps none of what it would be given inside content it replaces or manages (icons, a player's controls).
    for entry in visited where entry.inHostContent { entry.fiber.firstPublishedEpoch = 0 }
    // Children come before their parents in `visited`: a fiber holds state when it, or anything below it, does.
    for entry in visited {
      let fiber = entry.fiber
      var holds = fiber.publishedOwnsState
      if !holds { for child in fiber.children where child.publishedHostOwned { holds = true; break } }
      fiber.publishedHostOwned = holds
    }
  }
}
