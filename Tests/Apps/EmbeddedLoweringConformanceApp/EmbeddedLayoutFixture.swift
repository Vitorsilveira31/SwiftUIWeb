import SwiftUIWeb

/// User-defined `Layout`s, which the page lays out with CSS:
/// - a flow that wraps its subviews at the width it is offered, asking each for its ideal size (`.unspecified`) and
///   placing it at that proposal, in frames of three widths (the window narrowing wraps them again);
/// - a radial layout that pins the centre of each subview (anchor `.center`) to a point of a circle, proposing each a size;
/// - a layout that asks for the ideal widths and proposes the widest to every subview, so a subview that fills takes it;
/// - custom layouts inside one another;
/// - a custom layout in a ScrollView, and in a stack beside a view that takes the rest.
/// "Count" changes the text of the chips, which changes what the flow wraps.
struct EmbeddedLayoutFixture: View {
  let onDone: () -> Void
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      Button("Count") { count += 1 }
      FixtureFlowLayout { chips }.frame(width: 300)
      FixtureFlowLayout { chips }.frame(width: 200)
      FixtureFlowLayout { chips }.frame(maxWidth: .infinity, alignment: .leading)
      HStack(alignment: .top, spacing: 12) {
        FixtureRadialLayout {
          Text("Hub").padding(4).background(Color.orange.opacity(0.4))
          ForEach(0..<8, id: \.self) { index in
            Color.teal.opacity(0.5).overlay(Text("\(index)"))
          }
        }
        .frame(width: 150, height: 150)
        Color.gray.opacity(0.2)
      }
      .frame(height: 150)
      FixtureColumnsLayout {
        Text("Short")
        Text("A longer line of text")
        Text("Fills the column").frame(maxWidth: .infinity).background(Color.green.opacity(0.3))
        Text("Count \(count)").background(Color.blue.opacity(0.2))
      }
      FixtureFlowLayout {
        FixtureColumnsLayout {
          Text("Nested one")
          Text("Fills").frame(maxWidth: .infinity).background(Color.green.opacity(0.3))
        }
        FixtureColumnsLayout {
          Text("Nested two, wider")
          Text("Second")
        }
        FixtureRadialLayout {
          Color.red.opacity(0.4)
          Color.purple.opacity(0.4)
          Color.yellow.opacity(0.4)
        }
        .frame(width: 80, height: 80)
      }
      .frame(width: 320)
      ScrollView {
        FixtureFlowLayout { chips }.padding(8)
      }
      .frame(width: 240, height: 90)
    }
    .padding(16)
  }

  private var chips: some View {
    ForEach(0..<9, id: \.self) { index in
      Text(index % 3 == 0 ? "Chip \(index) \(count) with more text" : "Chip \(index)")
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.teal.opacity(0.25))
    }
  }
}

/// Rows of subviews at their ideal sizes, wrapped at the width it is offered (nothing: one row).
private struct FixtureFlowLayout: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
    var width: CGFloat = 0
    var height: CGFloat = 0
    for row in rows(proposal.width, subviews) {
      width = max(width, row.width)
      height += row.height + (height > 0 ? 6 : 0)
    }
    return CGSize(width: width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
    var y = bounds.minY
    for row in rows(proposal.width, subviews) {
      var x = bounds.minX
      for index in row.range {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), anchor: .topLeading, proposal: .unspecified)
        x += size.width + 6
      }
      y += row.height + 6
    }
  }

  private struct Row {
    var range: Range<Int>
    var width: CGFloat
    var height: CGFloat
  }

  private func rows(_ available: CGFloat?, _ subviews: LayoutSubviews) -> [Row] {
    let limit = available ?? 100_000
    var rows: [Row] = []
    var start = 0
    var width: CGFloat = 0
    var height: CGFloat = 0
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      if index > start && width + 6 + size.width > limit {
        rows.append(Row(range: start..<index, width: width, height: height))
        start = index
        width = 0
        height = 0
      }
      width += (index > start ? 6 : 0) + size.width
      height = max(height, size.height)
    }
    if start < subviews.count { rows.append(Row(range: start..<subviews.count, width: width, height: height)) }
    return rows
  }
}

/// Subviews placed on a circle inside the square it is offered (100 where it is offered nothing), the first at the centre;
/// each is pinned by its own centre and proposed 36 x 36.
private struct FixtureRadialLayout: Layout {
  private let directions: [(CGFloat, CGFloat)] = [(1, 0), (0.75, 0.75), (0, 1), (-0.75, 0.75), (-1, 0), (-0.75, -0.75), (0, -1), (0.75, -0.75)]

  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
    let side = min(proposal.width ?? 100, proposal.height ?? 100)
    return CGSize(width: side, height: side)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    let radius = min(bounds.width, bounds.height) / 2 - 18
    for index in subviews.indices {
      let direction = index == 0 ? (CGFloat(0), CGFloat(0)) : directions[(index - 1) % directions.count]
      subviews[index].place(
        at: CGPoint(x: center.x + radius * direction.0, y: center.y + radius * direction.1),
        anchor: .center,
        proposal: ProposedViewSize(width: 36, height: 36)
      )
    }
  }
}

/// A column of subviews that asks each for its ideal width and proposes the widest to every one.
private struct FixtureColumnsLayout: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    var height: CGFloat = 0
    for size in sizes { height += size.height + (height > 0 ? 4 : 0) }
    return CGSize(width: sizes.map(\.width).max() ?? 0, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
    let width = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
    var y = bounds.minY
    for index in subviews.indices {
      subviews[index].place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: width, height: nil))
      y += subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)).height + 4
    }
  }
}
