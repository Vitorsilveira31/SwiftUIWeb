import SwiftUI

// The calendar screen: the Month/Agenda switch, the chosen mode, and the add-event sheet.
struct CalendarView: View {
    let viewModel: CalendarViewModel
    @State private var isAddingEvent = false

    var body: some View {
        VStack(spacing: 0) {
            Picker(Strings.Screen.modeLabel, selection: modeBinding) {
                ForEach(CalendarMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            .accessibilityIdentifier("calendar-mode")

            switch viewModel.state.mode {
            case .month:
                CalendarMonthView(viewModel: viewModel)
            case .agenda:
                CalendarAgendaView(viewModel: viewModel)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingEvent = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Strings.Screen.addEvent)
                .accessibilityIdentifier("calendar-add")
            }
        }
        .sheet(isPresented: $isAddingEvent) {
            CalendarAddEventSheet(viewModel: viewModel)
        }
    }

    private var modeBinding: Binding<CalendarMode> {
        Binding(
            get: { viewModel.state.mode },
            set: { viewModel.send(.setMode($0)) }
        )
    }
}
