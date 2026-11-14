import SwiftUI

// Page 7: markers. SwiftUI has no marker property, so each marker is drawn where the
// SVG marker would sit.
struct Page07View: View {
    var body: some View {
        FixtureGrid {
            FxArrows()
            FxOrient()
        }
    }
}
