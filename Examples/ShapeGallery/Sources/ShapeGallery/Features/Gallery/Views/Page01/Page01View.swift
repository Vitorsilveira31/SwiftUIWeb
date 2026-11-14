import SwiftUI

// Page 1: geometry, units, transforms, nested viewports and styles.
struct Page01View: View {
    var body: some View {
        FixtureGrid {
            FxShapes()
            FxUnits()
            FxTransform()
            FxOrigin()
            FxIcon()
            FxNested()
            FxNonscaling()
            FxStyle()
            FxRatio()
        }
    }
}
