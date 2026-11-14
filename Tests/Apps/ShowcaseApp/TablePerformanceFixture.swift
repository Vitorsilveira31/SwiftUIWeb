import SwiftUIWeb

private struct TablePerformanceRow: Identifiable, Hashable {
  let id: Int
  let title: String
  let status: String
}

/// Large-table fixture for `Tools/test-performance-browser.mjs`. The route is
/// hidden from the sidebar and reached by path (`/tablePerformance`) only, so
/// the other performance scenarios keep their existing documents.
struct TablePerformanceFixture: View {
  private let rows: [TablePerformanceRow] = (1...2000).map { index in
    TablePerformanceRow(id: index, title: "Row \(index)", status: index % 2 == 0 ? "Ready" : "Queued")
  }

  var body: some View {
    Table(rows) {
      TableColumn("Title", value: \TablePerformanceRow.title)
      TableColumn("Status", value: \TablePerformanceRow.status)
    }
    .frame(height: 480)
  }
}
