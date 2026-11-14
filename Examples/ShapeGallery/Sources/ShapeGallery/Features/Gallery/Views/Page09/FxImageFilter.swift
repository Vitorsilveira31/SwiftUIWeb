import SwiftUI

// Image filters: each picture is filtered on its own. The reference uses a photo;
// here a system symbol stands in for it, at the same size and with the same filters.
struct FxImageFilter: View {
    var body: some View {
        FixtureTile(name: "fx-image-filter") {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    StandIn()
                        .accessibilityLabel(Strings.ImageFilter.unfiltered)
                    StandIn()
                        .brightness(-0.4)
                        .accessibilityLabel(Strings.ImageFilter.darkened)
                }
                HStack(spacing: 6) {
                    StandIn()
                        .grayscale(1)
                        .contrast(1.4)
                        .accessibilityLabel(Strings.ImageFilter.grey)
                    StandIn()
                        .colorInvert()
                        .opacity(0.6)
                        .accessibilityLabel(Strings.ImageFilter.inverted)
                }
            }
            .frame(width: 120, height: 80)
        }
    }
}
