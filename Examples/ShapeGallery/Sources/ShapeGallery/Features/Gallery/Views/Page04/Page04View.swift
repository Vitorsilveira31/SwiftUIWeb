import SwiftUI

// Page 4: clipping. Clip paths are written as SwiftUI clip shapes and masks; a clip
// rule (even-odd) is written as a path whose inner contour winds the other way.
struct Page04View: View {
    var body: some View {
        FixtureGrid {
            FxPlot()
            FxBbox()
            FxRules()
        }
    }
}
