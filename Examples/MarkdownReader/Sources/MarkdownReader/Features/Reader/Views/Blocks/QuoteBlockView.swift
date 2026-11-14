import SwiftUI

/// One bar per level of nesting, then the quoted text beside them.
struct QuoteBlockView: View {
    let depth: Int
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            // The parser already caps depth; the view keeps its own cap so it stays safe for any caller.
            ForEach(0..<min(depth, 6), id: \.self) { _ in
                Rectangle()
                    .fill(.tertiary)
                    .frame(width: 3)
            }
            Text(MarkdownInlineStyler.styled(text))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
