import SwiftUI

// Month mode: header, weekday row, the six-week grid and the selected day's events.
struct CalendarMonthView: View {
    let viewModel: CalendarViewModel
    // Direction of the last month change, so the grid slides the right way.
    @State private var movesForward = true

    var body: some View {
        VStack(spacing: 8) {
            CalendarMonthHeader(
                visibleMonth: viewModel.state.visibleMonth,
                onToday: {
                    send(.today, forward: viewModel.dates.today > viewModel.state.visibleMonth)
                },
                onPrevious: { send(.previousMonth, forward: false) },
                onNext: { send(.nextMonth, forward: true) }
            )
            CalendarWeekdayRow(symbols: viewModel.dates.weekdaySymbols)
            CalendarMonthGrid(
                viewModel: viewModel,
                movesForward: movesForward,
                onSelect: { day in
                    send(.selectDay(day.date), forward: day.date > viewModel.state.visibleMonth)
                },
                onSwipe: { forward in
                    send(forward ? .nextMonth : .previousMonth, forward: forward)
                }
            )
            Divider()
            CalendarDayEventsList(viewModel: viewModel)
        }
    }

    private func send(_ action: CalendarViewModel.Action, forward: Bool) {
        movesForward = forward
        withAnimation(.snappy) {
            viewModel.send(action)
        }
    }
}
