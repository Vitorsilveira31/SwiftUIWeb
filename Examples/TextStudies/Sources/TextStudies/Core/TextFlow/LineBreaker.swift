import SwiftUI

/// Greedy line breaking around obstacles. Within each line band, the free gaps are filled
/// left to right; a word that does not fit the current gap moves to the next gap or band.
enum LineBreaker {
    static let minGap: CGFloat = 28

    /// Places words column by column, `bands` lines per column. Returns the top-left corner of
    /// each placed word (in order) and the count placed.
    static func fill(_ input: LineBreakInput, bands: Int) -> (origins: [CGPoint], placed: Int) {
        var origins: [CGPoint] = []
        var next = 0
        let count = input.widths.count
        for column in 0..<input.columns {
            let left = CGFloat(column) * (input.columnWidth + input.gap)
            let right = left + input.columnWidth
            for band in 0..<bands where next < count {
                let top = CGFloat(band) * input.lineHeight
                let excluded = TextSpans.union(
                    input.obstacles.flatMap { $0.excluded(top: top, bottom: top + input.lineHeight) })
                let gaps = TextSpans.free(from: left, to: right, excluded: excluded, minWidth: minGap)
                var endsParagraph = false
                for gap in gaps where next < count && !endsParagraph {
                    var pen = gap.lowerBound
                    while next < count, pen + input.widths[next] <= gap.upperBound + 0.5 {
                        origins.append(CGPoint(x: pen, y: top))
                        pen += input.widths[next] + input.space
                        endsParagraph = input.breaks[next]
                        next += 1
                        if endsParagraph { break }
                    }
                }
            }
        }
        return (origins, next)
    }
}
