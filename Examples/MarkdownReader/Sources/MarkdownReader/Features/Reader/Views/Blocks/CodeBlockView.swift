import SwiftUI

/// A fenced block: a language label, a Copy button, and the code in a
/// monospaced font that scrolls sideways instead of wrapping.
struct CodeBlockView: View {
    let language: String
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? Strings.CodeBlock.untitledLanguage : language)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                // The share sheet is the only SwiftUI route to the clipboard
                // on iOS; its Copy action puts the text there.
                ShareLink(item: code) {
                    Label(Strings.CodeBlock.copy, systemImage: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                }
                .accessibilityIdentifier("markdown-code-copy")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: true, vertical: false)
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
