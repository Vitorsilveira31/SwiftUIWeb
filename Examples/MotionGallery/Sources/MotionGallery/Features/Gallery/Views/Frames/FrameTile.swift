import SwiftUI

/// An image tile driven by a periodic timeline that ticks every 0.1s, the finest step the sequences use.
struct FrameTile: View {
    let sequence: FrameSequence
    var cornerRadius: CGFloat = 0
    @State private var start = Date.now

    var body: some View {
        TimelineView(.periodic(from: start, by: 0.1)) { context in
            let index = sequence.frameIndex(elapsed: context.date.timeIntervalSince(start))
            QuarterFrame(colour: sequence.colour.opacity(sequence.alpha), whiteQuarter: index % 4)
                .padding(sequence.inset)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
