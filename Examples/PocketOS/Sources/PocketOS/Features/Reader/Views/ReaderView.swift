import SwiftUI

// Reader: the library, or one article when the shell has one open.
struct ReaderView: View {
    let reader: ReaderViewModel
    let messages: MessagesViewModel
    let shell: ShellViewModel

    var body: some View {
        if let id = shell.state.openedArticle, let article = reader.state.articles.first(where: { $0.id == id }) {
            ArticleView(article: article, messages: messages, shell: shell)
        } else {
            LibraryView(reader: reader, shell: shell)
        }
    }
}
