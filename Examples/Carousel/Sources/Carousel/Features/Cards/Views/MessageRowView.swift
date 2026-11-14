import SwiftUI

/// A message row whose height follows its card's width, so the inbox's rows
/// differ in height.
struct MessageRowView: View {
    let post: Int
    let message: CardVO

    var body: some View {
        Text(Strings.Cards.card(message.n))
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            .frame(height: message.width / 2)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
            }
            .accessibilityIdentifier("msg-\(post)-\(message.n)")
    }
}
