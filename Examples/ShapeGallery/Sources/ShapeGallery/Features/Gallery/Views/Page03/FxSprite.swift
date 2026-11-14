import SwiftUI

// A sprite: the star symbol referenced from a separate picture, in its own colour.
struct FxSprite: View {
    var body: some View {
        FixtureTile(name: "fx-sprite") {
            ZStack(alignment: .topLeading) {
                Star()
                    .fill(Color(hex: 0xA855F7))
                    .placed(30, 10, 60, 60)
            }
        }
    }
}
