import Testing

@testable import LoweringCore

@Suite struct TableSortingTests {
  private func sorted(_ source: String, rules: [String] = ["table-sorting"]) -> LoweringResult { lower(source, rules: rules) }

  @Test func comparatorsBecomeEmbeddedMemberClosures() {
    let result = sorted(#"""
      @State private var sortOrder = [KeyPathComparator(\Order.status, order: .reverse)]
      let byName = KeyPathComparator(\.name)
      let typed = KeyPathComparator<Donut>(\.name, order: .forward)
      let nested = KeyPathComparator(\Order.customer.name)
      """#)
    #expect(result.text.contains(#"[KeyPathComparator(_embeddedMember: "status", { (row: Order) in row.status }, order: .reverse)]"#))
    #expect(result.text.contains(#"KeyPathComparator(_embeddedMember: "name", { $0.name })"#))
    #expect(result.text.contains(#"KeyPathComparator<Donut>(_embeddedMember: "name", { $0.name }, order: .forward)"#))
    #expect(result.text.contains(#"KeyPathComparator(_embeddedMember: "customer.name", { (row: Order) in row.customer.name })"#))
    #expect(!result.text.contains("\\"))
    #expect(result.counts["key-path-comparator"] == 4)
  }

  @Test func sortableColumnsKeepTheirContentClosure() {
    let result = sorted(#"""
      Table(selection: $selection, sortOrder: $sortOrder) {
          TableColumn("Status", value: \.status) { order in
              order.status.label
          }
          TableColumn("Date", value: \Order.creationDate, comparator: .standard) { order in Text(order.formattedDate) }
          TableColumn("Name", value: \.name)
          TableColumn("Details") { order in Text("x") }
              .width(60)
      } rows: {
          ForEach(orders) { order in TableRow(order) }
      }
      """#)
    #expect(result.text.contains(#"TableColumn("Status", _embeddedMember: "status", _embeddedValue: { $0.status }) {"#))
    #expect(result.text.contains(
      #"TableColumn("Date", _embeddedMember: "creationDate", _embeddedValue: { (row: Order) in row.creationDate }, comparator: .standard) {"#
    ))
    // Without a content closure the column is left to the simple rules.
    #expect(result.text.contains(#"TableColumn("Name", value: \.name)"#))
    #expect(result.text.contains(#"TableColumn("Details") { order in"#))
    #expect(result.counts["table-column-sortable"] == 2)
    let both = sorted(result.text, rules: ["table-sorting", "simple-rules"])
    #expect(both.text.contains(#"TableColumn("Name") { row in Text(row.name) }"#))
    #expect(!both.text.contains("\\"))
  }

  @Test func countsAndLeavesOtherShapesAlone() {
    let result = sorted(#"""
      let a = KeyPathComparator(\.id)
      TableColumn("T", value: \.id) { r in Text(r.id) }
      let plain = KeyPathComparator(compare: f)
      let optional = KeyPathComparator(\.owner?.name)
      let reversed = KeyPathComparator(\.id, order: reverse(order))
      let description = "KeyPathComparator(\\.id) in a string"
      // KeyPathComparator(\.id) in a comment
      """#)
    #expect(result.counts["key-path-comparator"] == 2)
    #expect(result.counts["table-column-sortable"] == 1)
    #expect(result.text.contains("KeyPathComparator(compare: f)"))
    #expect(result.text.contains(#"KeyPathComparator(\.owner?.name)"#))
    #expect(result.text.contains(#"KeyPathComparator(_embeddedMember: "id", { $0.id }, order: reverse(order))"#))
    #expect(result.text.contains(#""KeyPathComparator(\\.id) in a string""#))
    #expect(result.text.contains(#"// KeyPathComparator(\.id) in a comment"#))
  }

  @Test func argumentsMayBeSplitOverLines() {
    let result = sorted(#"""
      let order = KeyPathComparator(
        \Order.status,
        order: .reverse
      )
      TableColumn(
        "Status",
        value: \.status
      ) { order in Text(order.status) }
      """#)
    #expect(result.text.contains(#"KeyPathComparator(_embeddedMember: "status", { (row: Order) in row.status }, order: .reverse)"#))
    #expect(result.text.contains(#"_embeddedMember: "status", _embeddedValue: { $0.status }) {"#))
  }

  @Test func loweringItsOwnOutputChangesNothing() {
    let first = sorted(#"""
      let a = KeyPathComparator(\Order.status, order: .reverse)
      TableColumn("S", value: \.status, comparator: .standard) { Text($0.status) }
      """#)
    let second = sorted(first.text)
    #expect(second.text == first.text)
    #expect(second.counts.isEmpty)
  }
}
