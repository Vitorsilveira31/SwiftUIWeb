import SwiftUI

/// The heading and one slider per adjustment.
struct AdjustmentSliders: View {
    let viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.Editor.adjust)
                .font(.headline)
            ForEach(Adjustment.allCases) { adjustment in
                AdjustmentSlider(adjustment: adjustment, viewModel: viewModel)
            }
        }
    }
}
