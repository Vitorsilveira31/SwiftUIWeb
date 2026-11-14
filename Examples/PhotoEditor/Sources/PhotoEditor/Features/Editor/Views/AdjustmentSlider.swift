import SwiftUI

/// One adjustment: its title and value, and the slider that moves it. A drag is one history entry.
struct AdjustmentSlider: View {
    let adjustment: Adjustment
    let viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(adjustment.title) {
                Text(adjustment.value(in: viewModel.state.edit), format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { adjustment.value(in: viewModel.state.edit) },
                    set: { viewModel.send(.changeAdjustment(adjustment, $0)) }
                ),
                in: adjustment.range,
                onEditingChanged: { editing in
                    viewModel.send(editing ? EditorViewModel.Action.beginSliderDrag : .endSliderDrag)
                }
            )
            .accessibilityIdentifier("adjust-\(adjustment.id)")
        }
    }
}
