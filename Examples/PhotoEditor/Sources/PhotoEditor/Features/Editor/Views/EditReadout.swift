import SwiftUI

/// The readout under the photo: the edit's numbers, how many times it was edited, and the same edit in the photo's terms.
struct EditReadout: View {
    let viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Strings.Editor.editHeading)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(viewModel.state.summary)
                .font(.callout)
                .monospacedDigit()
                .accessibilityIdentifier("edit")
            Text(Strings.Editor.edited(viewModel.state.edits))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("edits")
            Text(viewModel.state.photoTerms)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("photo-terms")
        }
    }
}
