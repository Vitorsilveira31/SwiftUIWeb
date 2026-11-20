import Testing
@testable @_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWeb

/// A GeometryReader tells the page the size its content was drawn for (`data-geometry-rendered`): with Swift in a worker the
/// page keeps a reader it has just inserted hidden until that size is its box's (Tools/embedded-dom.js).
@Suite
@MainActor
struct GeometryReaderRenderedSizeTests {
  @Test
  func aReaderReportsTheSizeItsContentWasDrawnFor() throws {
    let tree = FiberTree(GeometryReader { proxy in Text("\(Int(proxy.size.width))") })
    defer { tree._dispose() }
    // Not measured yet, and no enclosing size to go by: drawn at zero.
    var reader = try #require(tree.findNode(withEvent: "geometry"))
    #expect(reader.attributes["data-geometry-rendered"] == "0,0")
    // Drawn for a guess: the page holds it until it is drawn for its box.
    #expect(reader.attributes["data-geometry-guess"] == "true")
    // Measured: drawn again for the box the page reported.
    tree.dispatch(event: "geometry", value: "0,0,320.5,200", on: reader)
    reader = try #require(tree.findNode(withEvent: "geometry", in: tree.renderNode))
    #expect(reader.attributes["data-geometry-rendered"] == "320.5,200")
    #expect(reader.attributes["data-geometry-guess"] == nil)
  }

  @Test
  func aNestedReaderReportsTheEnclosingReadersSizeUntilItIsMeasured() throws {
    let tree = FiberTree(GeometryReader { _ in GeometryReader { inner in Text("\(Int(inner.size.width))") } })
    defer { tree._dispose() }
    let outer = try #require(tree.findNode(withEvent: "geometry"))
    tree.dispatch(event: "geometry", value: "0,0,800,600", on: outer)
    // The inner reader was drawn at its parent's size, which the page compares with its own box.
    let measured = try #require(tree.findNode(withEvent: "geometry", in: tree.renderNode))
    let inner = try #require(tree.findNode(withEvent: "geometry", in: measured.children.first))
    #expect(inner.attributes["data-geometry-rendered"] == "800,600")
  }
}
