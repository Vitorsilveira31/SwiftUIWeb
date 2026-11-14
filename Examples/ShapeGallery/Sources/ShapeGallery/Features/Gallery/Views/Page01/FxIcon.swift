import SwiftUI

// A 24-unit icon drawn into an 80 x 80 box, centred in the 120 x 80 picture.
struct FxIcon: View {
    var body: some View {
        FixtureTile(name: "fx-icon") {
            Heart()
                .fill(Color(hex: 0xE11D48))
                .placed(20, 0, 80, 80)
        }
    }
}
