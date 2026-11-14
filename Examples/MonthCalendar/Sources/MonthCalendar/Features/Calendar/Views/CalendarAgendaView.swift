import SwiftUI

// Agenda mode: the next 60 days, one section per day, scrolled to today on appear.
struct CalendarAgendaView: View {
    let viewModel: CalendarViewModel

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(viewModel.dates.agendaDays(), id: \.self) { day in
                    let events = viewModel.events(on: day)
                    Section {
                        if events.isEmpty {
                            Text(Strings.Agenda.noEvents)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(events) { event in
                            CalendarEventRow(event: event) {
                                viewModel.send(.deleteEvent(event.id))
                            }
                        }
                    } header: {
                        Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    }
                    .id(viewModel.dates.dayKey(day))
                }
            }
            .onAppear {
                proxy.scrollTo(viewModel.dates.dayKey(viewModel.dates.today), anchor: .top)
            }
        }
    }
}
