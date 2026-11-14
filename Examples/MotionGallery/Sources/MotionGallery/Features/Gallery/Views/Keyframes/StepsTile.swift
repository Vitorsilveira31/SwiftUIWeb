import SwiftUI

/// walk: a 32x32 square moves 32px right and down in steps(4), forever.
/// The position is quantised by hand, since SwiftUI has no stepped timing curve.
struct StepsTile: View {
    @State private var start = Date.now

    var body: some View {
        TimelineView(.animation) { context in
            let progress = context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: 1)
            let stepped = (progress * 4).rounded(.down) / 4
            Rectangle()
                .fill(Palette.violet)
                .frame(width: 32, height: 32)
                .offset(x: 32 * stepped, y: 32 * stepped)
        }
        .frame(width: 64, height: 64, alignment: .topLeading)
    }
}
