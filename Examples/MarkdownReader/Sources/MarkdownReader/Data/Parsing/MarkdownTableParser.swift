import Foundation

/// Reads a pipe table: a header row, a separator row that sets alignments,
/// then body rows until a line without a pipe.
enum MarkdownTableParser {
    /// Pasted tables are cut to these bounds, so one paste cannot allocate millions of cells.
    static let maxColumns = 64
    static let maxRows = 1_000

    /// Returns the table and the index of the first line after it.
    static func parse(_ lines: [String], start: Int) -> (table: TableData, next: Int) {
        let header = Array(splitRow(lines[start]).prefix(maxColumns))
        let alignments = splitRow(lines[start + 1]).prefix(maxColumns).map(columnAlignment)
        var rows: [[String]] = []
        var next = start + 2
        while next < lines.count {
            let row = lines[next].trimmingCharacters(in: .whitespaces)
            if row.isEmpty || !row.contains("|") {
                break
            }
            // Lines past the row cap are still consumed, so the rest of the document keeps its structure.
            if rows.count < maxRows {
                rows.append(splitRow(row))
            }
            next += 1
        }
        // Cells are fitted to the header's columns: short rows are padded,
        // long rows are cut, as a browser's table lays them out.
        let columns = header.count
        let table = TableData(
            alignments: (0..<columns).map { $0 < alignments.count ? alignments[$0] : .leading },
            header: header,
            rows: rows.map { row in (0..<columns).map { $0 < row.count ? row[$0] : "" } }
        )
        return (table, next)
    }

    static func isDelimiterRow(_ line: String) -> Bool {
        guard line.contains("|") else { return false }
        let cells = splitRow(line.trimmingCharacters(in: .whitespaces))
        return !cells.isEmpty && cells.allSatisfy { cell in
            let core = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return !core.isEmpty && core.allSatisfy { $0 == "-" }
        }
    }

    static func splitRow(_ line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") {
            row.removeFirst()
        }
        if row.hasSuffix("|") {
            row.removeLast()
        }
        return row
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func columnAlignment(_ cell: String) -> ColumnAlignment {
        let left = cell.hasPrefix(":")
        let right = cell.hasSuffix(":")
        if left && right { return .center }
        return right ? .trailing : .leading
    }
}
