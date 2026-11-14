import SwiftUI

struct ParagraphBlockView: View {
    let text: String

    var body: some View {
        Text(MarkdownInlineStyler.styled(text))
            .foregroundStyle(.primary)
            .lineSpacing(4)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
