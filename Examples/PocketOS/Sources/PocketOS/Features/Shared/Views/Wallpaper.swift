import SwiftUI

// The dark ground of the lock and home screens.
struct Wallpaper: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.11, green: 0.11, blue: 0.14), .black],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
