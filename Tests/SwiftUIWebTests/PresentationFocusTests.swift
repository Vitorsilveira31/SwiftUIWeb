import Foundation
import Testing
@testable import SwiftUIWeb
import SwiftUIWebHTML
@_spi(Renderer) @testable import SwiftUIWebCore
@_spi(Renderer) @testable import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

@Suite
@MainActor
final class PresentationFocusTests {
  private func collect(_ node: _RenderNode) -> [_RenderNode] {
    [node] + node.children.flatMap(collect)
  }

  @Test
  func testPresentationOwnersAndNestedIDsAreStable() {
    let view = Text("Root").sheet(isPresented: .constant(true)) {
      Text("Outer").alert("Inner", isPresented: .constant(true)) { Text("OK") }
    }
    let first = StaticHTMLFiberRenderer().render(view)
    let second = StaticHTMLFiberRenderer().render(view)
    let firstIDs = first.split(separator: "data-presentation-id=\"").dropFirst().map { $0.split(separator: "\"").first.map(String.init) ?? "" }
    let secondIDs = second.split(separator: "data-presentation-id=\"").dropFirst().map { $0.split(separator: "\"").first.map(String.init) ?? "" }
    _expectEqual(firstIDs.count, 2, first)
    _expectEqual(firstIDs, secondIDs)
    _expectEqual(Set(firstIDs).count, 2)
    _expectTrue(first.contains("data-presentation-phase=\"presented\""), first)
    _expectTrue(first.contains("data-presentation-owner-id="), first)
  }

  @Test
  func testFocusedModifierEmitsProgrammaticFocusRequest() {
    let html = StaticHTMLFiberRenderer().render(
      TextField("Name", text: .constant("")).focused(.constant(true))
    )
    _expectTrue(html.contains("data-focused=\"true\""), html)
    _expectTrue(html.contains("data-focus-request=\"true\""), html)
  }

  @Test
  func testPresentationDismissalUsesOneSemanticEvent() {
    let view = Button("Open") {}.sheet(isPresented: .constant(true)) { Text("Sheet") }
    let tree = FiberTree(view)
    let presentations = collect(tree.renderNode).filter { $0.classes.contains("presentation-root") }
    _expectEqual(presentations.count, 1)
    _expectEqual(presentations.first?.events.keys.filter { $0 == "presentation-dismiss" }.count, 1)
  }
}
