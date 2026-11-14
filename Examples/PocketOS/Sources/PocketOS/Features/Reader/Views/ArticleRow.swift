import SwiftUI

// One article in the library: its section and length, title, and the first lines of its deck.
struct ArticleRow: View {
    let article: Article
    let open: () -> Void
    @Environment(\.readingScale) private var scale

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 5) {
                Text(Strings.Reader.listKicker(article.section, article.minutes))
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(article.title)
                    .font(Voice.title(17))
                Text(article.deck)
                    .font(Voice.text(14 * scale))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("article-\(article.id)")
    }
}
