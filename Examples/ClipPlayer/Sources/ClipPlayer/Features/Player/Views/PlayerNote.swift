import SwiftUI

/// The note field. Return or Done closes the keyboard; the picture grows back.
struct PlayerNote: View {
    @Binding var note: String
    var focus: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Player.noteHeading)
                .font(.headline)
            HStack(spacing: 10) {
                TextField(Strings.Player.notePlaceholder, text: $note)
                    .textFieldStyle(.roundedBorder)
                    .focused(focus)
                    .submitLabel(.done)
                    .onSubmit { focus.wrappedValue = false }
                    .accessibilityIdentifier("note")
                    .accessibilityLabel(Strings.Player.noteLabel)
                Button(Strings.Player.done) { focus.wrappedValue = false }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("done")
            }
        }
    }
}
