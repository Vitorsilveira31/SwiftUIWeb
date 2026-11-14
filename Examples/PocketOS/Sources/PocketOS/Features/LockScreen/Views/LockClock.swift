import SwiftUI

// The time in the display face, the date above it in the rounded text face.
// The timeline ticks once a second, as the device's own clock does.
struct LockClock: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(context.date, format: .dateTime.hour().minute())
                    .font(Voice.display(124))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityIdentifier("lock-clock")
            }
        }
    }
}
