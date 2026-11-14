import Foundation

struct CalendarEvent: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var color: EventColor
}
