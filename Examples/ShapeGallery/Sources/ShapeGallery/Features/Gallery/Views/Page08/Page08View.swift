import SwiftUI

// Page 8: masks and patterns. Masks are built on full-tile layers, so their
// coordinates are the picture's own.
struct Page08View: View {
    var body: some View {
        FixtureGrid {
            FxMaskLum()
            FxMaskAlpha()
            FxPatternDots()
            FxPatternHatch()
            FxWebForeign()
        }
    }
}
