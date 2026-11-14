import SwiftUI

// An article page. Ask Pocket, in the header or below the text, opens the assistant's thread
// with the article as its first question.
struct ArticleView: View {
    let article: Article
    let messages: MessagesViewModel
    let shell: ShellViewModel
    @AppStorage("pocketos.assistantKey") private var assistantKey = ""
    @AppStorage("pocketos.assistantModel") private var assistantModel = ChatModel.balanced.rawValue
    @Environment(\.readingScale) private var scale

    var body: some View {
        VStack(spacing: 0) {
            ArticleHeader(onBack: { shell.send(.closeArticle) }, onAsk: askPocket)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(article.section.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.orange)
                    Text(article.title)
                        .font(Voice.title(32))
                    Text(article.deck)
                        .font(.system(size: 19 * scale))
                        .fontDesign(.serif)
                        .italic()
                        .foregroundStyle(.secondary)
                    Text(Strings.Reader.byline(article.author, article.posted, article.minutes))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Divider()
                    ForEach(article.body, id: \.self) { paragraph in
                        Text(paragraph)
                            .font(.system(size: 18 * scale))
                            .fontDesign(.serif)
                            .lineSpacing(5)
                    }
                    PullQuote(text: article.pull)
                    Button(action: askPocket) {
                        Label(Strings.Reader.talkAboutThis, systemImage: "bubble.left.and.text.bubble.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 6)
                    .accessibilityIdentifier("ask-pocket-below")
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("article-screen")
    }

    private func askPocket() {
        shell.send(.openThread(ChatThread.assistantID))
        messages.send(.askAboutArticle(
            article.title,
            hasKey: !assistantKey.isEmpty,
            model: ChatModel(rawValue: assistantModel) ?? .balanced
        ))
    }
}
