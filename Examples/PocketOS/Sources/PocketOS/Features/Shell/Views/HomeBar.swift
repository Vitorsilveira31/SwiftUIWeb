import SwiftUI

// The Home bar. A tap or an upward swipe on it leaves the app.
struct HomeBar: View {
    let goHome: () -> Void

    var body: some View {
        Button(action: goHome) {
            Capsule()
                .fill(.primary)
                .frame(width: 134, height: 5)
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    if value.translation.height < -40 {
                        goHome()
                    }
                }
        )
        .accessibilityLabel(Strings.Shell.home)
        .accessibilityIdentifier("home-bar")
    }
}
