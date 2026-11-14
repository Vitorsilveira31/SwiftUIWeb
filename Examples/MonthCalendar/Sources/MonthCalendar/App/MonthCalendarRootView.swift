import SwiftUI

// The app's entry view. Both hosts load it: Darwin/Sources/Main.swift on iOS and Web/MonthCalendarWebApp.swift in
// the browser.
public struct MonthCalendarRootView: View {
    @State private var viewModel: CalendarViewModel

    public init() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let repository = InMemoryEventRepository(events: SampleEvents.make(today: today, calendar: calendar))
        _viewModel = State(initialValue: CalendarViewModel(repository: repository, calendar: calendar, today: today))
    }

    public var body: some View {
        NavigationStack {
            CalendarView(viewModel: viewModel)
                .navigationTitle(Strings.Screen.title)
        }
    }
}
