import SwiftUI

/// One quarter of a frame. White stays opaque even when the coloured quarters are translucent.
struct QuarterCell: View {
    let fill: Color

    var body: some View {
        Rectangle()
            .fill(fill)
    }
}
