import SwiftUI

/// held: a 32x32 square at a quarter turn. The reference starts a 1s spin with a
/// -250ms delay and pauses it, which freezes it at 90 degrees, so it is static here.
struct HeldTile: View {
    var body: some View {
        Rectangle()
            .fill(.primary)
            .frame(width: 32, height: 32)
            .rotationEffect(.degrees(90))
    }
}
