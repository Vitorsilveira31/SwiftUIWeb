import SwiftUI

// The events of the selected day, under the grid.
struct CalendarDayEventsList: View {
    let viewModel: CalendarViewModel

    var body: some View {
        let selectedDay = viewModel.state.selectedDay
        let events = viewModel.events(on: selectedDay)
        List {
            Section(selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day())) {
                if events.isEmpty {
                    ContentUnavailableView(
                        Strings.Month.noEvents,
                        systemImage: "calendar",
                        description: Text(Strings.Month.noEventsDetail)
                    )
                    .listRowBackground(Color.clear)
                }
                ForEach(events) { event in
                    CalendarEventRow(event: event) {
                        viewModel.send(.deleteEvent(event.id))
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}
