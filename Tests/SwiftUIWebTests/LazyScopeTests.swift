import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

/// A lazy stack windows its own rows. A collection in a container that lays its content out itself (a horizontal
/// ScrollView, an HStack in a LazyVStack) is not one of those rows and renders whole, as in SwiftUI.
@MainActor
struct LazyScopeTests {
  @Test func horizontalShelfInLazyVStackRendersEveryItem() {
    let view = ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        Text("Header")
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { Text("Chip \($0)") }
          }
        }
      }
    }
    let tree = FiberTree(view)
    #expect(tree._lazyCollections().isEmpty)
    let html = tree.root.renderNode.htmlDescription
    #expect(html.contains("Chip 4"))
    #expect(!html.contains("data-lazy-spacer"))
  }

  @Test func stackAcrossTheLazyAxisEndsTheScope() {
    let vertical = FiberTree(LazyVStack { HStack { ForEach(0..<40, id: \.self) { Text("Cell \($0)") } } })
    #expect(vertical._lazyCollections().isEmpty)
    #expect(vertical.root.renderNode.htmlDescription.contains("Cell 39"))
    let horizontal = FiberTree(LazyHStack { VStack { ForEach(0..<40, id: \.self) { Text("Cell \($0)") } } })
    #expect(horizontal._lazyCollections().isEmpty)
    let layered = FiberTree(LazyVStack { ZStack { ForEach(0..<40, id: \.self) { Text("Cell \($0)") } } })
    #expect(layered._lazyCollections().isEmpty)
  }

  @Test func lazyStacksKeepWindowingTheirOwnRows() {
    let vertical = FiberTree(ScrollView { LazyVStack { ForEach(0..<40, id: \.self) { Text("Row \($0)") } } })
    #expect(vertical._lazyCollections().map(\.descriptor.axis) == [.vertical])
    let horizontal = FiberTree(ScrollView(.horizontal) { LazyHStack { ForEach(0..<40, id: \.self) { Text("Card \($0)") } } })
    #expect(horizontal._lazyCollections().map(\.descriptor.axis) == [.horizontal])
    // A lazy stack inside the shelf starts a scope of its own on its axis.
    let nested = FiberTree(ScrollView {
      LazyVStack {
        ScrollView(.horizontal) { LazyHStack { ForEach(0..<40, id: \.self) { Text("Card \($0)") } } }
      }
    })
    #expect(nested._lazyCollections().map(\.descriptor.axis) == [.horizontal])
  }
}
