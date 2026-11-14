import SwiftUI

// Today's calendar: the weekday, the day in the display face, and the next event.
struct CalendarWidget: View {
    let event: CalendarEvent

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 0) {
                Text(context.date, format: .dateTime.weekday(.wide))
                    .font(.system(size: 13, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(context.date, format: .dateTime.day())
                    .font(Voice.display(56))
                Spacer(minLength: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(Voice.title(15))
                        .lineLimit(1)
                    Text(event.time)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.black)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 164, alignment: .leading)
            .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .accessibilityIdentifier("widget-calendar")
    }
}
