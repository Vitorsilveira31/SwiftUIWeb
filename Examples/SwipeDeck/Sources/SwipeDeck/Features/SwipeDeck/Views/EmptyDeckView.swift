import SwiftUI

/// Shown over the deck once every card has been decided on.
struct EmptyDeckView: View {
    let onStartOver: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(Strings.Empty.title, systemImage: "flame.fill")
        } description: {
            Text(Strings.Empty.message)
        } actions: {
            Button(Strings.Empty.startOver, action: onStartOver)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("start-over")
        }
        .accessibilityIdentifier("empty-deck")
        .transition(.opacity)
    }
}
