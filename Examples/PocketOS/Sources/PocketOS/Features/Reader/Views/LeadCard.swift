import SwiftUI

// The lead article in the library: a large card with its section, title, deck and byline.
struct LeadCard: View {
    let article: Article
    let open: () -> Void
    @Environment(\.readingScale) private var scale

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                Text(article.section.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange)
                Text(article.title)
                    .font(Voice.title(28))
                Text(article.deck)
                    .font(Voice.text(16 * scale).italic())
                    .foregroundStyle(.secondary)
                Text(Strings.Reader.byline(article.author, article.posted, article.minutes))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("article-\(article.id)")
    }
}
