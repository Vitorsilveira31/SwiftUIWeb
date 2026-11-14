// Every user-visible string of the app. Sample data and accessibility identifiers stay next to their use.
enum Strings {
    enum Screen {
        static let title = "Calendar"
        static let modeLabel = "View"
        static let modeMonth = "Month"
        static let modeAgenda = "Agenda"
        static let addEvent = "Add event"
    }

    enum Month {
        static let today = "Today"
        static let previousMonth = "Previous month"
        static let nextMonth = "Next month"
        static let noEvents = "No Events"
        static let noEventsDetail = "Tap + to add an event to this day."
    }

    enum Agenda {
        static let noEvents = "No events"
    }

    enum EventRow {
        static let allDay = "All day"
        static let delete = "Delete"

        static func timeRange(from start: String, to end: String) -> String {
            "\(start) – \(end)"
        }
    }

    enum NewEvent {
        static let title = "New Event"
        static let cancel = "Cancel"
        static let add = "Add"
        static let titleField = "Title"
        static let allDay = "All-day"
        static let starts = "Starts"
        static let ends = "Ends"
        static let color = "Color"
    }
}
