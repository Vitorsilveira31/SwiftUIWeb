@MainActor
final class InMemoryEventRepository: EventRepository {
    private var storedEvents: [CalendarEvent]

    init(events: [CalendarEvent]) {
        storedEvents = events.sorted { $0.start < $1.start }
    }

    func events() -> [CalendarEvent] {
        storedEvents
    }

    func add(_ event: CalendarEvent) {
        storedEvents.append(event)
        storedEvents.sort { $0.start < $1.start }
    }

    func delete(id: String) {
        storedEvents.removeAll { $0.id == id }
    }
}
