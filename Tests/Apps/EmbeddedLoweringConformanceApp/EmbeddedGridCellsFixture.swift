import SwiftUIWeb

/// A `Grid` whose cells say how they sit in it, and a screen with a bottom bar:
/// - `gridCellColumns(_:)` covers several columns, `gridCellAnchor(_:)` places a cell in its slot,
///   `gridCellUnsizedAxes(_:)` takes the slot instead of sizing it and `gridColumnAlignment(_:)` aligns a whole column;
/// - `ToolbarItemPlacement.bottomBar` items form a bar in a row of their own below the screen.
/// CSS layout must lay both out (`Tools/test-css-layout-fixtures-browser.mjs`).
struct EmbeddedGridCellsFixture: View {
  let onDone: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
        GridRow {
          Text("Alpha beta gamma")
          Text("B")
        }
        GridRow {
          Text("C").gridColumnAlignment(.trailing)
          Text("D")
        }
        GridRow {
          Text("E").gridCellAnchor(.trailing)
          Text("F").gridCellAnchor(.bottomTrailing)
        }
        GridRow {
          Text("A cell that covers both columns").gridCellColumns(2)
        }
        GridRow {
          Color.orange.frame(height: 6).gridCellUnsizedAxes(.horizontal)
          Text("G")
        }
      }
      .frame(width: 280)
      NavigationStack {
        Text("Screen")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
              Button("Down") {}
              Button("Top") {}
            }
          }
      }
      .frame(width: 320, height: 200)
      // The same screen with its navigation bar hidden: the bottom bar stays at the foot, the top items go.
      NavigationStack {
        Text("Hidden bar screen")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .toolbar(.hidden, for: .navigationBar)
          .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
              Button("Share") {}
            }
          }
      }
      .frame(width: 320, height: 160)
    }
    .padding(16)
  }
}
