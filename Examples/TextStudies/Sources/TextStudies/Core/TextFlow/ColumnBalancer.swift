/// Finds the fewest lines per column that hold every word. Binary search works because more
/// lines never place fewer words.
enum ColumnBalancer {
    static func minimumBands(_ input: LineBreakInput, limit: Int = 800) -> Int {
        var low = 1
        var high = limit
        while low < high {
            let middle = (low + high) / 2
            if LineBreaker.fill(input, bands: middle).placed == input.widths.count {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low
    }
}
