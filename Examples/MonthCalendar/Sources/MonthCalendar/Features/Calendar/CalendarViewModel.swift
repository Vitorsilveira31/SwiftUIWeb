import Foundation
import Observation

// Owns the calendar's state and every change to it. Views read `state`, query events by day, and send actions.
@Observable
@MainActor
final class CalendarViewModel {
    struct State: Equatable {
        var visibleMonth: Date
        var selectedDay: Date
        var events: [CalendarEvent]
        var mode: CalendarMode
    }

    enum Action {
        case nextMonth
        case previousMonth
        case today
        case selectDay(Date)
        case addEvent(NewEvent)
        case deleteEvent(String)
        case setMode(CalendarMode)
    }

    private(set) var state: State
    let dates: CalendarDates
    private let repository: any EventRepository

    // No default State: the first month and day depend on today and the calendar.
    init(repository: any EventRepository, calendar: Calendar, today: Date) {
        let dates = CalendarDates(calendar: calendar, today: today)
        self.dates = dates
        self.repository = repository
        state = State(
            visibleMonth: dates.startOfMonth(today),
            selectedDay: today,
            events: repository.events(),
            mode: .month
        )
    }

    func send(_ action: Action) {
        switch action {
        case .nextMonth:
            shiftMonth(by: 1)
        case .previousMonth:
            shiftMonth(by: -1)
        case .today:
            state.visibleMonth = dates.startOfMonth(dates.today)
            state.selectedDay = dates.today
        case .selectDay(let day):
            selectDay(day)
        case .addEvent(let draft):
            addEvent(draft)
        case .deleteEvent(let id):
            repository.delete(id: id)
            state.events = repository.events()
        case .setMode(let mode):
            state.mode = mode
        }
    }

    // Events on one day, earliest first.
    func events(on day: Date) -> [CalendarEvent] {
        state.events
            .filter { dates.isSameDay($0.start, day) }
            .sorted { $0.start < $1.start }
    }

    private func shiftMonth(by months: Int) {
        guard let month = dates.shiftedMonth(state.visibleMonth, by: months) else { return }
        state.visibleMonth = month
        if let day = dates.day(sameNumberAs: state.selectedDay, in: month) {
            state.selectedDay = day
        }
    }

    private func selectDay(_ day: Date) {
        state.selectedDay = dates.startOfDay(day)
        if !dates.isSameMonth(day, state.visibleMonth) {
            state.visibleMonth = dates.startOfMonth(day)
        }
    }

    // The new event selects its own day, so the user sees it in the list straight away.
    private func addEvent(_ draft: NewEvent) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let start = draft.isAllDay ? dates.startOfDay(draft.start) : draft.start
        let end = draft.isAllDay ? start : max(draft.end, start)
        repository.add(
            CalendarEvent(
                id: UUID().uuidString,
                title: title,
                start: start,
                end: end,
                isAllDay: draft.isAllDay,
                color: draft.color
            )
        )
        state.events = repository.events()
        selectDay(start)
    }
}
