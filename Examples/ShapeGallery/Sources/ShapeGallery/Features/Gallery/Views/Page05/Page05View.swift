import SwiftUI

// Page 5: text, placed by anchor and baseline.
struct Page05View: View {
    var body: some View {
        FixtureGrid {
            FxAxis()
            FxBaselines()
            FxRuns()
        }
    }
}
