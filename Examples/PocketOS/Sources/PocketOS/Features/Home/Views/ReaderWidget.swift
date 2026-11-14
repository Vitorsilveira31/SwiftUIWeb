import SwiftUI

// The Reader widget: the lead article, opened on a tap.
struct ReaderWidget: View {
    let article: Article
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                Image(systemName: "book.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 52, height: 52)
                    .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(Strings.Home.readerKicker(article.section))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(article.title)
                        .font(Voice.title(18))
                        .lineLimit(2)
                    Text(Strings.Home.readerByline(article.author, article.minutes))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.32), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("widget-reader")
    }
}
