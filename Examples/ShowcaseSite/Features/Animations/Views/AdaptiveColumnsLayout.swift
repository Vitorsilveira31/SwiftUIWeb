import SwiftUIWeb

/// Columns that are at least `minimumWidth` wide and share the row: as many as fit, then the cards wrap. Every card is
/// `rowHeight` tall, so the layout never has to measure one. A `LazyVGrid` does the same, but its cells are built lazily and
/// do not redraw when a state of their own changes; and a `ViewThatFits` of stacks puts the page back to the top whenever
/// a card's content changes size (a symbol swaps, a number gains a digit), because it measures its choices again.
struct AdaptiveColumnsLayout: Layout {
  var minimumWidth: CGFloat
  var spacing: CGFloat
  var rowHeight: CGFloat

  private func columnCount(for width: CGFloat) -> Int {
    max(1, Int((width + spacing) / (minimumWidth + spacing)))
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
    let width = proposal.width ?? minimumWidth
    let columns = columnCount(for: width)
    let rows = (subviews.count + columns - 1) / columns
    return CGSize(width: width, height: CGFloat(rows) * rowHeight + CGFloat(max(rows - 1, 0)) * spacing)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
    let columns = columnCount(for: bounds.width)
    let cardWidth = (bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    for index in subviews.indices {
      let row = index / columns
      let column = index % columns
      subviews[index].place(
        at: CGPoint(
          x: bounds.minX + CGFloat(column) * (cardWidth + spacing),
          y: bounds.minY + CGFloat(row) * (rowHeight + spacing)
        ),
        anchor: .topLeading,
        proposal: ProposedViewSize(width: cardWidth, height: rowHeight)
      )
    }
  }
}
