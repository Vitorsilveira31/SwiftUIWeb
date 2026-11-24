import SwiftUIWeb

/// The fixtures of `Tools/test-lazy-grid-lanes-browser.mjs`: lazy grids of many equal cells, one tab for each kind of grid
/// (adaptive, a fixed column beside an adaptive one, flexible columns, adaptive rows across a horizontal scroll view, and an
/// adaptive grid that grows when a button is pressed). Each ends with a text, so the test reads the grid's extent from where
/// that text starts.
struct LazyGridFixtures {
  static let cellCount = 120
  static let cell = 100.0
  static let gap = 8.0
  /// The cells the growing grid starts with (fewer than the cells a viewport of estimated rows holds, so the first window grows), and the cells a press of its button adds.
  static let growStart = 12
  static let growStep = 300
}

/// A vertical lazy grid of 120 cells, each 100 tall.
struct VerticalGridFixture: View {
  let kind: String
  let columns: [GridItem]

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        LazyVGrid(columns: columns, spacing: LazyGridFixtures.gap) {
          ForEach(0..<LazyGridFixtures.cellCount, id: \.self) { index in
            Text("cell \(index)").frame(maxWidth: .infinity).frame(height: LazyGridFixtures.cell).background(Color.gray.opacity(0.2))
              .accessibilityIdentifier("\(kind)-cell-\(index)")
          }
        }
        Text("end of grid").accessibilityIdentifier("\(kind)-end")
      }
    }
  }
}

/// A horizontal lazy grid of 120 cells, each 100 wide, with adaptive rows, in a horizontal scroll view 300 tall.
struct HorizontalGridFixture: View {
  let kind: String

  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 0) {
        LazyHGrid(rows: [GridItem(.adaptive(minimum: 60), spacing: LazyGridFixtures.gap)], spacing: LazyGridFixtures.gap) {
          ForEach(0..<LazyGridFixtures.cellCount, id: \.self) { index in
            Text("cell \(index)").frame(maxHeight: .infinity).frame(width: LazyGridFixtures.cell).background(Color.gray.opacity(0.2))
              .accessibilityIdentifier("\(kind)-cell-\(index)")
          }
        }
        Text("end of grid").accessibilityIdentifier("\(kind)-end")
      }
    }
    .frame(height: 300)
  }
}

/// An adaptive grid that starts with 12 cells and gets 300 more when the button is pressed.
struct GrowingGridFixture: View {
  let kind: String
  @State private var count = LazyGridFixtures.growStart

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        // The cells arrive some time after the press, outside the press's own publication, as the pages of a list do when a request answers.
        Button("Append") {
          Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            count += LazyGridFixtures.growStep
          }
        }.accessibilityIdentifier("\(kind)-append")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: LazyGridFixtures.gap) {
          ForEach(0..<count, id: \.self) { index in
            Text("cell \(index)").frame(maxWidth: .infinity).frame(height: LazyGridFixtures.cell).background(Color.gray.opacity(0.2))
              .accessibilityIdentifier("\(kind)-cell-\(index)")
          }
        }
        Text("end of grid").accessibilityIdentifier("\(kind)-end")
      }
    }
  }
}
