import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// The browser host reports every post-commit measurement (onGeometryChange, GeometryReader) to Swift
/// one by one and publishes once, after the last report. State written by an earlier report in the
/// batch must survive a later report that invalidates a GeometryReader's own render owner.
@Suite(.serialized)
@MainActor
struct BatchedMeasurementReportTests {
  private struct Fixture: View {
    @State private var measuredHeight = 0.0
    @State private var changes = 0

    var body: some View {
      VStack {
        Text("height:\(Int(measuredHeight)) changes:\(changes)")
        Color.blue
          .frame(width: 120, height: 40)
          .onGeometryChange(for: Double.self, of: { $0.size.height }) { height in
            measuredHeight = height
            changes += 1
          }
        GeometryReader { proxy in
          Text("reader:\(Int(proxy.size.width))")
        }
        .frame(height: 40)
      }
    }
  }

  /// The fixture is shown by a state change of the root, so its body is rendered by a targeted
  /// re-render of the root owner, whose node is the fixture's own node.
  private struct Root: View {
    @State private var showsFixture = false
    var body: some View {
      if showsFixture {
        Fixture()
      } else {
        VStack {
          Text("home")
          Button("Open") { showsFixture = true }
        }
      }
    }
  }

  private struct WidthLabel: View {
    let title: String
    @Binding var width: Int
    var body: some View { Text("\(title):\(width)") }
  }

  /// The measured width is read by two child views, so its write has no single owner to target and
  /// must be reconciled from the root, even when a reader's own owner is already waiting in the batch.
  private struct SharedWidthFixture: View {
    @State private var measuredWidth = 1000

    var body: some View {
      VStack {
        WidthLabel(title: "first", width: $measuredWidth)
        WidthLabel(title: "second", width: $measuredWidth)
        Color.green
          .frame(height: 10)
          .onGeometryChange(for: Int.self, of: { Int($0.size.width) }) { measuredWidth = $0 }
        GeometryReader { proxy in
          Text("reader:\(Int(proxy.size.width))")
        }
        .frame(height: 40)
      }
    }
  }

  private func report(_ tree: FiberTree, readerFirst: Bool = false) -> String {
    if readerFirst { tree.dispatch(event: "geometry", value: "0,274,1000,40") }
    tree.dispatch(event: "geometryChange", value: "440,208,120,40")
    if !readerFirst { tree.dispatch(event: "geometry", value: "0,274,1000,40") }
    return tree.renderNode.htmlDescription
  }

  @Test func reportsForAViewShownByATargetedRootUpdateSurviveOneBatch() {
    let tree = FiberTree(Root(), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    tree._startLifecycle()
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    _ = tree.renderNode
    tree.dispatch(event: "click")
    #expect(tree.renderNode.htmlDescription.contains("height:0 changes:0"))

    let html = report(tree)
    #expect(html.contains("height:40 changes:1"), "\(html)")
    #expect(html.contains("reader:1000"), "\(html)")
  }

  @Test func readerReportFirstInTheBatchKeepsTheLaterStateWrite() {
    let tree = FiberTree(Root(), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    tree._startLifecycle()
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    _ = tree.renderNode
    tree.dispatch(event: "click")
    _ = tree.renderNode

    let html = report(tree, readerFirst: true)
    #expect(html.contains("height:40 changes:1"), "\(html)")
    #expect(html.contains("reader:1000"), "\(html)")
  }

  @Test func reportsForTheRootViewSurviveOneBatch() {
    let tree = FiberTree(Fixture(), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    tree._startLifecycle()
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    #expect(tree.renderNode.htmlDescription.contains("height:0 changes:0"))

    let html = report(tree)
    #expect(html.contains("height:40 changes:1"), "\(html)")
    #expect(html.contains("reader:1000"), "\(html)")
  }

  @Test func unroutedStateWriteAfterAReaderReportInTheSameBatchIsRendered() {
    let tree = FiberTree(SharedWidthFixture(), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    tree._startLifecycle()
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    #expect(tree.renderNode.htmlDescription.contains("first:1000"))

    tree.dispatch(event: "geometry", value: "0,294,700,40")
    tree.dispatch(event: "geometryChange", value: "0,276,700,10")
    let html = tree.renderNode.htmlDescription
    #expect(html.contains("first:700"), "\(html)")
    #expect(html.contains("second:700"), "\(html)")
    #expect(html.contains("reader:700"), "\(html)")
  }
}
