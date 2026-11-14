import SwiftUI

// The Reader library: a masthead with today's date, the lead article as a card, the rest as rows.
struct LibraryView: View {
    let reader: ReaderViewModel
    let shell: ShellViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Strings.Reader.title)
                        .font(Voice.display(40))
                    Spacer()
                    Text(Date.now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                if let lead = reader.state.articles.first {
                    LeadCard(article: lead) {
                        shell.send(.openArticle(lead.id))
                    }
                }
                ForEach(reader.state.articles.dropFirst()) { article in
                    ArticleRow(article: article) {
                        shell.send(.openArticle(article.id))
                    }
                }
            }
            .padding(20)
        }
        .accessibilityIdentifier("reader-list")
    }
}
