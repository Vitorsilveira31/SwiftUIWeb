import SwiftUIWebCore
import SwiftUIWebFiber

/// Rendering backend boundary for the Fiber runtime. There is intentionally no
/// renderer selector; all output is produced from a FiberTree.
package protocol FiberRenderer {
  associatedtype Output
  @MainActor func render<V: View>(_ view: V) -> Output
  @MainActor func renderTree<V: View>(_ view: V) -> FiberTree
}
