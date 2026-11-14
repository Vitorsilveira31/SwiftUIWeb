import SwiftUI

/// A round picture: a sphere-like stack of three circles, sized by the layout.
struct RoundPictureView: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.31, green: 0.49, blue: 0.42))
            Circle()
                .fill(Color(red: 0.76, green: 0.38, blue: 0.25))
                .scaleEffect(0.6)
            Circle()
                .fill(Color(red: 0.95, green: 0.76, blue: 0.31))
                .scaleEffect(0.28)
        }
    }
}
