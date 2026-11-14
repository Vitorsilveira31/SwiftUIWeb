import SwiftUI

/// A table as a `Grid`: every row shares the column widths, the header is
/// bold on a tinted band, and the whole grid scrolls sideways when wider than the screen.
struct TableBlockView: View {
    let table: TableData

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { column, title in
                        TableCellView(text: title, alignment: alignment(at: column), isHeader: true)
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, value in
                            TableCellView(text: value, alignment: alignment(at: column), isHeader: false)
                        }
                    }
                }
            }
            .padding(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func alignment(at column: Int) -> ColumnAlignment {
        table.alignments.indices.contains(column) ? table.alignments[column] : .leading
    }
}
