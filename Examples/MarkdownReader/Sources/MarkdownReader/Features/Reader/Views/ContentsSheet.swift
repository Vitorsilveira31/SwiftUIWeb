import SwiftUI

/// The headings of the open document. Choosing one closes the sheet and
/// scrolls the document to that heading.
struct ContentsSheet: View {
    let headings: [Heading]
    let choose: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if headings.isEmpty {
                    Text(Strings.Contents.empty)
                        .foregroundStyle(.secondary)
                }
                ForEach(headings) { heading in
                    Button {
                        choose(heading.id)
                        dismiss()
                    } label: {
                        Text(heading.title)
                            .font(heading.level <= 2 ? .body.weight(.semibold) : .body)
                            .foregroundStyle(.primary)
                            .padding(.leading, CGFloat(heading.level - 1) * 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("markdown-contents-\(heading.id)")
                }
            }
            .navigationTitle(Strings.Contents.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.Contents.done) {
                        dismiss()
                    }
                }
            }
        }
    }
}
