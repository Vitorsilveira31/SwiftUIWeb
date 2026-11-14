import Testing
@testable import SwiftUIWeb
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
@_spi(Renderer) @testable import SwiftUIWebCore

/// View structure values an application can receive from data (a scale, a stepper value at the end of its range, option
/// tags, duplicate row ids, a binding to a collection that shrank) must not trap, and the rows they produce keep their
/// own state.
@Suite
@MainActor
struct ViewStructureHardeningTests {
  private struct Item: Identifiable {
    let id: Int
    let name: String
  }

  private struct TableRow: Identifiable {
    let id: Int
    let name: String
  }

  private func html<V: View>(_ view: V) -> String { StaticHTMLFiberRenderer().render(view) }

  private func descendants(of node: _RenderNode) -> [_RenderNode] {
    [node] + node.children.flatMap(descendants)
  }

  @Test
  func asyncImageScaleOutsideTheIntegerRangeIsNotConverted() {
    let url = URL(string: "https://example.test/a.png")!
    #expect(html(AsyncImage(url: url, scale: 1e300) { _ in EmptyView() }).contains("data-scale=\"1000000\""))
    #expect(html(AsyncImage(url: url, scale: .nan) { _ in EmptyView() }).contains("data-scale=\"1\""))
    #expect(html(AsyncImage(url: url, scale: .infinity) { _ in EmptyView() }).contains("data-scale=\"1\""))
    #expect(html(AsyncImage(url: url, scale: 0) { _ in EmptyView() }).contains("data-scale=\"1\""))
    #expect(html(AsyncImage(url: url, scale: 2) { _ in EmptyView() }).contains("data-scale=\"2\""))
  }

  @Test
  func steppersAtTheEndOfTheirRangeAreDisabledWithoutTrapping() {
    var high = Int.max
    let top = FiberTree(Stepper(value: Binding(get: { high }, set: { high = $0 }), in: 0...Int.max, step: 1) { EmptyView() })
    let topButtons = descendants(of: top.renderNode).filter { $0.kind == .element("button") }
    #expect(topButtons.filter { $0.attributes["disabled"] == "disabled" }.count == 1)

    var nearEnd = Int.max - 1
    let stepTooLarge = FiberTree(Stepper(value: Binding(get: { nearEnd }, set: { nearEnd = $0 }), in: 0...Int.max, step: 5) { EmptyView() })
    let stepButtons = descendants(of: stepTooLarge.renderNode).filter { $0.kind == .element("button") }
    #expect(stepButtons.filter { $0.attributes["disabled"] == "disabled" }.count == 1)
    #expect(nearEnd == Int.max - 1)

    var low = Int.min
    let bottom = FiberTree(Stepper(value: Binding(get: { low }, set: { low = $0 }), in: Int.min...0, step: 1) { EmptyView() })
    let bottomButtons = descendants(of: bottom.renderNode).filter { $0.kind == .element("button") }
    #expect(bottomButtons.filter { $0.attributes["disabled"] == "disabled" }.count == 1)
  }

  @Test
  func steppersNextToTheIntegerEndsDisableWithoutTrapping() {
    var low = Int.min
    let nearMin = FiberTree(Stepper(value: Binding(get: { low }, set: { low = $0 }), in: Int.min...(Int.min + 1), step: 2) { EmptyView() })
    #expect(descendants(of: nearMin.renderNode).filter { $0.kind == .element("button") && $0.attributes["disabled"] == "disabled" }.count == 2)
    var high = Int.max
    let nearMax = FiberTree(Stepper(value: Binding(get: { high }, set: { high = $0 }), in: (Int.max - 1)...Int.max, step: 2) { EmptyView() })
    #expect(descendants(of: nearMax.renderNode).filter { $0.kind == .element("button") && $0.attributes["disabled"] == "disabled" }.count == 2)
    var byte: UInt8 = 250
    let bytes = FiberTree(Stepper(value: Binding(get: { byte }, set: { byte = $0 }), in: 0...255, step: 10) { EmptyView() })
    let byteButtons = descendants(of: bytes.renderNode).filter { $0.kind == .element("button") }
    #expect(byteButtons[1].attributes["disabled"] == "disabled")
    bytes.dispatch(event: "click", on: byteButtons[0])
    #expect(byte == 240)
    // Without a range, the type's own end: a press at Int.max is refused, not a trap.
    var unbounded = Int.max
    let open = FiberTree(Stepper(value: Binding(get: { unbounded }, set: { unbounded = $0 }), step: 1) { EmptyView() })
    let openButtons = descendants(of: open.renderNode).filter { $0.kind == .element("button") }
    #expect(openButtons[1].attributes["disabled"] == "disabled")
    open.dispatch(event: "click", on: openButtons[1])
    #expect(unbounded == Int.max)
  }

  @Test
  func steppersReachAFloatingEndpointAndStepFromTheCheckedValue() {
    // 0.5 + 0.2 is exactly 0.7, the bound, though 0.7 - 0.2 is 0.49999999999999994.
    var volume = 0.5
    let floating = FiberTree(Stepper(value: Binding(get: { volume }, set: { volume = $0 }), in: 0.0...0.7, step: 0.2) { EmptyView() })
    let floatingButtons = descendants(of: floating.renderNode).filter { $0.kind == .element("button") }
    #expect(floatingButtons[1].attributes["disabled"] == nil)
    floating.dispatch(event: "click", on: floatingButtons[1])
    #expect(volume == 0.7)

    // An editing callback that moves the value does not move the step: the next value was computed before it ran.
    var count = 5
    let binding = Binding(get: { count }, set: { count = $0 })
    let editing = FiberTree(Stepper(value: binding, in: 0...10, step: 1, onEditingChanged: { began in if began { count = 10 } }) { EmptyView() })
    let editingButtons = descendants(of: editing.renderNode).filter { $0.kind == .element("button") }
    editing.dispatch(event: "click", on: editingButtons[1])
    #expect(count == 6)
  }

  @Test
  func pickerOptionsWithOneTokenStillGetDistinctValues() {
    var selected = "same"
    let picker = FiberTree(Picker("Choice", selection: Binding(get: { selected }, set: { selected = $0 })) {
      Text("One").tag("same")
      Text("Two").tag("same")
    })
    let values = descendants(of: picker.renderNode)
      .filter { $0.kind == .element("option") }
      .compactMap { $0.attributes["value"] }
    #expect(values.count == 2)
    #expect(Set(values).count == 2)
    #expect(values.first == "same")
  }

  @Test
  func tableRowsWithOneIdKeepSeparatePaths() {
    let rows = [TableRow(id: 1, name: "First"), TableRow(id: 1, name: "Second")]
    let table = Table(rows) {
      TableColumn("Name") { row in Text(row.name) }
    }
    let trNodes = descendants(of: table._render(in: _RenderContext())).filter {
      $0.kind == .element("tr") && $0.attributes["data-row-id"] != nil
    }
    #expect(trNodes.count == 2)
    #expect(trNodes[0].key != trNodes[1].key)
  }

  @Test
  func bindingToAnElementOfAShrunkCollectionDoesNotTrap() {
    var items = [Item(id: 1, name: "A"), Item(id: 2, name: "B"), Item(id: 3, name: "C")]
    let rows = ForEach(Binding(get: { items }, set: { items = $0 })) { _ in EmptyView() }
    let last = rows.data[2]
    items.removeLast()
    #expect(last.wrappedValue.name == "C")
    last.wrappedValue = Item(id: 3, name: "changed")
    #expect(items.count == 2)
    #expect(!items.contains { $0.name == "changed" })

    let first = rows.data[0]
    items.removeFirst()
    #expect(first.wrappedValue.name == "A")
    let second = rows.data[1]
    items = items + [Item(id: 9, name: "Z")]
    #expect(second.wrappedValue.name == "B")
    second.wrappedValue = Item(id: 2, name: "edited")
    #expect(items.contains { $0.name == "edited" })
  }
}
