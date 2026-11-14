import SwiftUIWeb
import SwiftUIWebCharts

/// The layout trees a browser-owned widget hosts: an alert's message above its actions, a confirmation dialog, the cells
/// of a Table, the views a Chart draws in its foreignObjects (annotations, custom axis labels) and a Grid inside a Form
/// row or a disclosure. Each is a semantic root of its own, which the page's CSS mapper lays out. CSS layout
/// must lay it out (`Tools/test-css-layout-fixtures-browser.mjs`), on WebKit too.
enum EmbeddedHostRootsKind: String, CaseIterable {
  case alert, confirmation, table, chart, form
}

struct EmbeddedHostRootsFixture: View {
  let kind: EmbeddedHostRootsKind
  let onDone: () -> Void

  var body: some View {
    switch kind {
    case .alert: EmbeddedHostRootsAlert(onDone: onDone)
    case .confirmation: EmbeddedHostRootsConfirmation(onDone: onDone)
    case .table: EmbeddedHostRootsTable(onDone: onDone)
    case .chart: EmbeddedHostRootsChart(onDone: onDone)
    case .form: EmbeddedHostRootsForm(onDone: onDone)
    }
  }
}

private struct EmbeddedHostRootsAlert: View {
  let onDone: () -> Void
  @State private var shown = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      Button("Show alert") { shown = true }
      Text("Behind the alert")
    }
    .padding(16)
    .alert("Delete this item?", isPresented: $shown, actions: {
      Button("Delete", role: .destructive) {}
      Button("Cancel", role: .cancel) {}
    }, message: {
      Text("This cannot be undone, and the message is long enough to wrap onto a second line of the alert.")
    })
  }
}

private struct EmbeddedHostRootsConfirmation: View {
  let onDone: () -> Void
  @State private var shown = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      Button("Show dialog") { shown = true }
      Text("Behind the dialog")
    }
    .padding(16)
    .confirmationDialog("Choose an action", isPresented: $shown, actions: {
      Button("Duplicate") {}
      Button("Share") {}
      Button("Cancel", role: .cancel) {}
    }, message: {
      Text("Short message")
    })
  }
}

private struct HostRootsRow: Identifiable {
  let id: Int
  let name: String
  let amount: Int
}

private struct EmbeddedHostRootsTable: View {
  let onDone: () -> Void
  private let rows = [
    HostRootsRow(id: 1, name: "Glazed", amount: 12),
    HostRootsRow(id: 2, name: "A donut with a longer name", amount: 7),
    HostRootsRow(id: 3, name: "Sprinkles", amount: 120),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      Table(rows) {
        TableColumn("Order") { row in
          HStack(spacing: 6) {
            Circle().fill(.orange).frame(width: 12, height: 12)
            Text(row.name)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        TableColumn("Donuts") { row in
          Text("\(row.amount)").frame(maxWidth: .infinity, alignment: .trailing)
        }
        TableColumn("Status", value: \HostRootsRow.name)
      }
    }
    .padding(16)
  }
}

private struct HostRootsSale: Identifiable {
  let id: Int
  let donut: String
  let count: Int
}

private struct EmbeddedHostRootsChart: View {
  let onDone: () -> Void
  private let sales = [
    HostRootsSale(id: 1, donut: "Glazed", count: 12),
    HostRootsSale(id: 2, donut: "Sprinkles", count: 7),
    HostRootsSale(id: 3, donut: "Maple", count: 3),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      Chart {
        ForEach(sales) { sale in
          BarMark(x: .value("Donut", sale.donut), y: .value("Sales", sale.count))
            .annotation(position: .top) {
              Text("\(sale.count)").padding(.horizontal, 8).padding(.vertical, 4).background(.gray)
            }
        }
      }
      .chartXAxis {
        AxisMarks { _ in
          AxisValueLabel {
            VStack {
              Circle().fill(.orange).frame(width: 18, height: 18)
              Text("Donut").lineLimit(2)
            }
          }
        }
      }
      .frame(height: 300)
    }
    .padding(16)
  }
}

private struct EmbeddedHostRootsForm: View {
  let onDone: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      Form {
        Section("Totals") {
          Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
              Text("Glazed")
              Text("12").frame(maxWidth: .infinity, alignment: .trailing)
            }
            GridRow {
              Text("A donut with a longer name")
              Text("7").frame(maxWidth: .infinity, alignment: .trailing)
            }
          }
        }
        DisclosureGroup("Details") {
          Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
              Text("Name")
              Text("Value")
            }
            GridRow {
              Circle().fill(.orange).frame(width: 12, height: 12)
              Text("Orange")
            }
          }
        }
      }
      .frame(height: 320)
    }
    .padding(16)
  }
}
