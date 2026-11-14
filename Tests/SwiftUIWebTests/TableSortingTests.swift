import Foundation
import Testing
@testable import SwiftUIWeb
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

private struct TableTestRow: Identifiable {
  let id: Int
  let name: String
  let rank: Int
}

@MainActor
private final class TableTestBox<Value> {
  var value: Value
  init(_ value: Value) { self.value = value }
  var binding: Binding<Value> { Binding(get: { self.value }, set: { self.value = $0 }) }
}

@MainActor
private func descendants(of node: _RenderNode, where predicate: (_RenderNode) -> Bool) -> [_RenderNode] {
  var result: [_RenderNode] = []
  if predicate(node) { result.append(node) }
  for child in node.children { result.append(contentsOf: descendants(of: child, where: predicate)) }
  return result
}

@MainActor
private func tag(_ node: _RenderNode, _ name: String) -> Bool {
  if case .element(let tag) = node.kind { return tag == name }
  return false
}

private let tableTestRows = [
  TableTestRow(id: 1, name: "Bravo", rank: 2),
  TableTestRow(id: 2, name: "Alpha", rank: 3),
  TableTestRow(id: 3, name: "Charlie", rank: 1)
]

@Suite(.processGlobalState)
@MainActor
struct TableSortingTests {
  @Test
  func comparatorsSortForwardReverseAndByMultipleKeys() {
    let byName = KeyPathComparator(\TableTestRow.name)
    #expect(tableTestRows.sorted(using: byName).map(\.id) == [2, 1, 3])
    let reversed = KeyPathComparator(\TableTestRow.rank, order: .reverse)
    #expect(tableTestRows.sorted(using: reversed).map(\.id) == [2, 1, 3])
    var rows = tableTestRows
    rows.sort(using: [KeyPathComparator(\TableTestRow.rank)])
    #expect(rows.map(\.id) == [3, 1, 2])
    let tied = [TableTestRow(id: 1, name: "B", rank: 1), TableTestRow(id: 2, name: "A", rank: 1)]
    #expect(tied.sorted(using: [KeyPathComparator(\TableTestRow.rank), KeyPathComparator(\TableTestRow.name)]).map(\.id) == [2, 1])
  }

  @Test
  func singleAndMultipleSelectionHighlightRowsAndWriteTheBinding() throws {
    let single = TableTestBox<Int?>(2)
    let singleTable = Table(tableTestRows, selection: single.binding) {
      TableColumn("Name") { row in Text(row.name) }
    }
    let node = singleTable._render(in: _RenderContext())
    let rows = descendants(of: node) { tag($0, "tr") && $0.attributes["data-row-id"] != nil }
    #expect(rows.count == 3)
    #expect(rows.filter { $0.attributes["aria-selected"] == "true" }.count == 1)
    #expect(rows[1].attributes["data-selected"] == "true")
    #expect(rows[0].attributes["tabindex"] == "0")
    rows[0].events["click"]?.action()
    #expect(single.value == 1)

    let multiple = TableTestBox<Set<Int>>([])
    let multipleTable = Table(tableTestRows, selection: multiple.binding) {
      TableColumn("Name") { row in Text(row.name) }
    }
    let multipleRows = descendants(of: multipleTable._render(in: _RenderContext())) { $0.attributes["data-row-id"] != nil }
    multipleRows[2].events["click"]?.action()
    #expect(multiple.value == [3])
  }

  @Test
  func sortableHeaderTogglesAndWritesComparators() throws {
    let box = TableTestBox([KeyPathComparator(\TableTestRow.rank, order: .reverse)])
    let table = Table(tableTestRows, sortOrder: box.binding) {
      TableColumn("Name", value: \.name) { row in Text(row.name) }
      TableColumn("Rank", value: \.rank) { row in Text("\(row.rank)") }
      TableColumn("Plain") { row in Text("\(row.id)") }
    }
    func headers() -> [_RenderNode] {
      descendants(of: table._render(in: _RenderContext())) { tag($0, "th") }
    }
    var current = headers()
    #expect(current.count == 3)
    #expect(current[0].attributes["aria-sort"] == "none")
    #expect(current[1].attributes["aria-sort"] == "descending")
    #expect(current[2].attributes["data-sortable"] == nil)
    #expect(current[2].events["click"] == nil)

    current[1].events["click"]?.action()
    #expect(box.value.count == 1)
    #expect(box.value[0].order == .forward)
    #expect(tableTestRows.sorted(using: box.value).map(\.id) == [3, 1, 2])
    #expect(headers()[1].attributes["aria-sort"] == "ascending")

    current = headers()
    current[0].events["click"]?.action()
    #expect(box.value[0].order == .forward)
    #expect(tableTestRows.sorted(using: box.value).map(\.name) == ["Alpha", "Bravo", "Charlie"])
    headers()[0].events["click"]?.action()
    #expect(box.value[0].order == .reverse)
    #expect(headers()[0].attributes["aria-sort"] == "descending")
  }

  @Test
  func rowsFormCollectsTableRowsAndSupportsSelectionAndSorting() throws {
    let sort = TableTestBox([KeyPathComparator(\TableTestRow.rank)])
    let selection = TableTestBox<Set<Int>>([3])
    let ordered = tableTestRows.sorted(using: sort.value)
    let table = Table(of: TableTestRow.self, selection: selection.binding, sortOrder: sort.binding) {
      TableColumn("Name", value: \.name) { row in Text(row.name) }
        .width(120)
      TableColumn("Rank", value: \.rank) { row in Text("\(row.rank)") }
    } rows: {
      ForEach(ordered) { row in TableRow(row) }
    }
    let node = table._render(in: _RenderContext())
    let rows = descendants(of: node) { tag($0, "tr") && $0.attributes["data-row-id"] != nil }
    #expect(rows.count == 3)
    #expect(rows[0].attributes["data-selected"] == "true")
    let firstCell = descendants(of: rows[0]) { tag($0, "td") }
    #expect(firstCell.count == 2)
    let headers = descendants(of: node) { tag($0, "th") }
    #expect(headers[0].styles["width"] == "120.0px")
    #expect(headers[1].attributes["aria-sort"] == "ascending")
    headers[1].events["click"]?.action()
    #expect(sort.value[0].order == .reverse)
  }

  @Test
  func tableStyleModifiersAreAccepted() {
    let table = Table(tableTestRows) {
      TableColumn("Name") { row in Text(row.name) }
    }
    .tableStyle(.inset)
    .tableColumnHeaders(.visible)
    #expect(StaticHTMLFiberRenderer().render(table).contains("data-table-style=\"inset\""))
  }
  @Test
  func aComparatorColumnRecognizesItsComparatorInEitherOrder() {
    let sort = _TableColumnSort(comparator: KeyPathComparator(\TableTestRow.name))
    #expect(sort.matches(KeyPathComparator(\TableTestRow.name)))
    #expect(sort.matches(KeyPathComparator(\TableTestRow.name, order: .reverse)), "a click on the active column toggles it")
    #expect(!sort.matches(KeyPathComparator(\TableTestRow.rank)))
    #expect(sort.make(.reverse).order == .reverse)
  }
}
