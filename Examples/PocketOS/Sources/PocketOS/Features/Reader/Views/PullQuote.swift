import SwiftUI

// The article's pull quote: a serif line with an orange rule beside it.
struct PullQuote: View {
    let text: String
    @Environment(\.readingScale) private var scale

    var body: some View {
        Text(text)
            .font(Voice.title(24 * scale))
            .padding(.leading, 16)
            .padding(.vertical, 6)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 3)
            }
    }
}
