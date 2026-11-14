// Where the calendar's events live. The view model only knows this protocol.
@MainActor
protocol EventRepository {
    func events() -> [CalendarEvent]
    func add(_ event: CalendarEvent)
    func delete(id: String)
}
