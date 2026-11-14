import SwiftUI

// One event line, with a swipe action to delete it. Used by the month day list and the agenda.
struct CalendarEventRow: View {
    let event: CalendarEvent
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.color.color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.body)
                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityIdentifier("event-\(event.id)")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label(Strings.EventRow.delete, systemImage: "trash")
            }
        }
    }

    private var timeText: String {
        if event.isAllDay { return Strings.EventRow.allDay }
        let from = event.start.formatted(.dateTime.hour().minute())
        let to = event.end.formatted(.dateTime.hour().minute())
        return Strings.EventRow.timeRange(from: from, to: to)
    }
}
