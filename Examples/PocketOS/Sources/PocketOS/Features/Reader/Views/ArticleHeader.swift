import SwiftUI

// The article page's top bar: back to the library, and Ask Pocket.
struct ArticleHeader: View {
    let onBack: () -> Void
    let onAsk: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Label(Strings.Reader.title, systemImage: "chevron.left")
                    .font(.system(size: 17))
            }
            .accessibilityIdentifier("article-back")
            Spacer()
            Button(action: onAsk) {
                Label(Strings.Reader.askPocket, systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("ask-pocket")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
