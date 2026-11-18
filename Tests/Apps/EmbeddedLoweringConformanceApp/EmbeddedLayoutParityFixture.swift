import SwiftUIWeb

/// Layouts where the page once differed from Apple's SwiftUI, each in a group of its own (`accessibilityIdentifier`) whose boxes
/// the test checks against Apple's frames of the same tree:
/// - a user-defined Layout that asks its subview for its size at one proposal and places it at another, around a title and two
///   scroll views that fill the height left (a page with a list beside a detail): the title stays at the top and the panes
///   take the rest; alone and in a frame;
/// - LazyVGrid cells whose content fills the height with `.frame(maxHeight: .infinity)`: a background outside the frame is
///   as tall as the row, one inside it as tall as its content.
struct EmbeddedLayoutParityFixture: View {
  let onDone: () -> Void
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      Button("Count") { count += 1 }
      ParityGutterLayout(gutter: 20) { splitPage }
      .frame(width: 400, height: 240)
      .accessibilityIdentifier("parity-layout-split")
      splitPage.frame(width: 360, height: 240).accessibilityIdentifier("parity-split")
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
        VStack { Text("Short") }.padding(8).frame(maxHeight: .infinity, alignment: .top).background(Color.gray.opacity(0.3))
        VStack { Text("A much longer text that wraps onto several lines in this narrow column of the grid") }
          .padding(8).frame(maxHeight: .infinity, alignment: .top).background(Color.gray.opacity(0.3))
      }
      .frame(width: 300)
      .accessibilityIdentifier("parity-grid-fill")
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
        VStack { Text("Short") }.padding(8).background(Color.gray.opacity(0.3)).frame(maxHeight: .infinity, alignment: .top)
        VStack { Text("A much longer text that wraps onto several lines in this narrow column of the grid") }
          .padding(8).background(Color.gray.opacity(0.3)).frame(maxHeight: .infinity, alignment: .top)
      }
      .frame(width: 300)
      .accessibilityIdentifier("parity-grid-inner")
    }
    .padding(16)
  }

  /// A title above a list and a detail that each scroll, taking the height left.
  private var splitPage: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Page title \(count)").font(.title)
      HStack(alignment: .top, spacing: 12) {
        ScrollView {
          VStack(alignment: .leading, spacing: 4) { ForEach(0..<3, id: \.self) { Text("Row \($0)") } }
        }
        .frame(width: 100)
        .background(Color.blue.opacity(0.1))
        ScrollView { Text("Detail \(count)").frame(maxWidth: .infinity, alignment: .leading) }
          .frame(maxWidth: .infinity)
          .background(Color.orange.opacity(0.1))
      }
      .frame(maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

/// Its one subview centred, the width it is offered less `gutter` on each side, and as tall as it is offered.
private struct ParityGutterLayout: Layout {
  var gutter: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? 0
    let inner = ProposedViewSize(width: max(0, width - 2 * gutter), height: proposal.height)
    let height = subviews.first?.sizeThatFits(inner).height ?? 0
    return CGSize(width: width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
    subviews.first?.place(
      at: CGPoint(x: bounds.midX, y: bounds.minY),
      anchor: .top,
      proposal: ProposedViewSize(width: max(0, bounds.width - 2 * gutter), height: bounds.height)
    )
  }
}
