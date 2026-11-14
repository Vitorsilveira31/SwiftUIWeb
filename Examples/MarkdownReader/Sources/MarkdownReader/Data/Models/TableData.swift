struct TableData: Sendable, Equatable {
    /// One per column, from the separator row (`:---`, `:---:`, `---:`).
    let alignments: [ColumnAlignment]
    let header: [String]
    /// Every row has exactly `header.count` cells.
    let rows: [[String]]
}
