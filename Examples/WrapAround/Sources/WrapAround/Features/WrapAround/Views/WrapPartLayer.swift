import SwiftUI

/// Draws a study's shapes at their absolute positions.
struct WrapPartLayer: View {
    let shapes: [WrapExclusion]

    var body: some View {
        ForEach(shapes) { part in
            WrapPartView(part: part)
        }
    }
}
