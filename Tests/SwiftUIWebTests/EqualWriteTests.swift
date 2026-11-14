import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber
import SwiftUIWeb

@Suite
@MainActor
final class EqualWriteTests {
  private final class Probe: @unchecked Sendable { var bodies = 0; var write: ((Int) -> Void)? }

  private struct Counter: View {
    let probe: Probe
    @State private var count = 0
    var body: some View {
      let _ = probe.bodies += 1
      let _ = probe.write = { count = $0 }
      return Text("count=\(count)")
    }
  }

  @Test
  func writingAnEqualValueToPlainStateDoesNotRender() throws {
    let probe = Probe()
    let tree = FiberTree(Counter(probe: probe))
    let write = try #require(probe.write)
    let baseline = probe.bodies

    write(0)
    _ = tree.renderNode
    #expect(probe.bodies == baseline, "0 -> 0 changes nothing")

    write(1)
    _ = tree.renderNode
    #expect(probe.bodies > baseline)
    #expect(tree.renderNode.htmlDescription.contains("count=1"))
  }

  private final class Model: ObservableObject {
    @Published var title = "a"
    @Published var tags: [String] = []
  }

  private struct Reader: View {
    let probe: Probe
    @ObservedObject var model: Model
    var body: some View {
      let _ = probe.bodies += 1
      return Text(model.title + model.tags.joined())
    }
  }

  // SwiftUIWeb's own `@Published` skips equal writes; Combine's (native) announces every write, as Apple's does.
  @Test
  func publishedOnlyNotifiesWhenTheValueChanges() {
    let probe = Probe()
    let model = Model()
    let tree = FiberTree(Reader(probe: probe, model: model))
    let baseline = probe.bodies

    model.title = "a"
    model.tags = []
    _ = tree.renderNode
    #expect(probe.bodies == baseline, "equal writes are not changes")

    model.title = "b"
    _ = tree.renderNode
    #expect(probe.bodies > baseline)
    #expect(tree.renderNode.htmlDescription.contains("b"))
  }
}
