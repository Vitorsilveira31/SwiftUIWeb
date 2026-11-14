import SwiftUIWeb

/// `HSplitView` and `VSplitView`, whose panes the page lays out with CSS:
/// Swift's split layout gives each pane a slot and the pane's content is a root proposed that slot.
/// - two panes, one that hugs its content and one that fills;
/// - three panes with minimum, ideal and maximum widths, and the same along a vertical split;
/// - panes that wrap a text, hold a ScrollView or a split view of their own;
/// - a split view that takes the window's width, and one inside a stack beside a view that takes the rest.
/// "Count" changes the text of a pane, which changes what it wraps. The window narrowing gives the panes less width.
struct EmbeddedSplitFixture: View {
  let onDone: () -> Void
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      Button("Count") { count += 1 }
      HSplitView {
        Text("Hugs").padding(8)
        Color.green.opacity(0.3)
      }
      .frame(height: 60)
      HSplitView {
        Text("Sidebar").frame(minWidth: 120, idealWidth: 160, maxWidth: 220, maxHeight: .infinity).background(Color.blue.opacity(0.2))
        Text("Content \(count)").frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.orange.opacity(0.2))
        Text("Inspector").frame(minWidth: 100, idealWidth: 140, maxHeight: .infinity).background(Color.purple.opacity(0.2))
      }
      .frame(height: 80)
      VSplitView {
        Text("Top").frame(maxWidth: .infinity, minHeight: 30, idealHeight: 50, maxHeight: 90).background(Color.blue.opacity(0.2))
        Text("Middle \(count)").frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.orange.opacity(0.2))
        Text("Bottom").padding(6)
      }
      .frame(width: 320, height: 220)
      HStack(alignment: .top, spacing: 12) {
        HSplitView {
          VStack(alignment: .leading, spacing: 8) {
            Text("Navigator").font(.headline)
            ForEach(["Project", "Sources", "Tests"], id: \.self) { item in
              Text(item).padding(6).frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .padding(10)
          VSplitView {
            Text("Editor").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(12)
            Text("Inspector").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(12)
          }
        }
        .frame(width: 420, height: 220)
        .border(Color.gray)
        Color.gray.opacity(0.2)
      }
      .frame(height: 220)
      HSplitView {
        Text("A pane with a longer text that wraps at the width the split view gives it \(count)").padding(8)
        ScrollView {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<12, id: \.self) { index in Text("Row \(index)").frame(maxWidth: .infinity, alignment: .leading) }
          }
          .padding(8)
        }
      }
      .frame(height: 100)
    }
    .padding(12)
  }
}
