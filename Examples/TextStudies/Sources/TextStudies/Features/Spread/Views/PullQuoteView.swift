import SwiftUI

/// The pull quote: its height is measured by the layout at the page's quote width.
struct PullQuoteView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 19).italic())
            .foregroundStyle(Color(red: 0.35, green: 0.23, blue: 0.16))
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.15)))
    }
}
