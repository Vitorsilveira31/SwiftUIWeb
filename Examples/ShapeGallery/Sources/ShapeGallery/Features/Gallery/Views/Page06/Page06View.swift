import SwiftUI

// Page 6: taps on picture elements. Each element names what was tapped, and a label
// beside the grid shows the last one.
struct Page06View: View {
    @State private var viewModel = HitTestViewModel()

    var body: some View {
        FixtureGrid {
            FxHit(viewModel: viewModel)
            FxBars(viewModel: viewModel)
            PickedLabel(viewModel: viewModel)
        }
    }
}
