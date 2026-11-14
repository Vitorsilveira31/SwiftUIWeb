import Foundation

// What the add-event sheet collects. The view model turns it into a CalendarEvent.
struct NewEvent: Equatable, Sendable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var color: EventColor
}
