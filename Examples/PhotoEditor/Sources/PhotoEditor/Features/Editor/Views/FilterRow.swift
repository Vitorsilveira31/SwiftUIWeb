import SwiftUI

/// The preset filters, scrolled sideways.
struct FilterRow: View {
    let viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Editor.filters)
                .font(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Preset.allCases) { preset in
                        Button(preset.title) {
                            viewModel.send(.applyPreset(preset))
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("preset-\(preset.id)")
                    }
                }
            }
        }
    }
}
