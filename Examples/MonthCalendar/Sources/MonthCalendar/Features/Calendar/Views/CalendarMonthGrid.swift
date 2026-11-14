import SwiftUI

// The six-week grid of day cells. A horizontal swipe changes the month; the grid slides in from the side of the change.
struct CalendarMonthGrid: View {
    let viewModel: CalendarViewModel
    let movesForward: Bool
    let onSelect: (CalendarGridDay) -> Void
    let onSwipe: (Bool) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    // 6 rows of 44 points with 4 points between them.
    private let gridHeight: CGFloat = 6 * 44 + 5 * 4

    var body: some View {
        ZStack {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(viewModel.dates.gridDays(for: viewModel.state.visibleMonth)) { day in
                    Button {
                        onSelect(day)
                    } label: {
                        CalendarDayCell(
                            number: viewModel.dates.dayNumber(day.date),
                            isInMonth: day.isInMonth,
                            isToday: viewModel.dates.isSameDay(day.date, viewModel.dates.today),
                            isSelected: viewModel.dates.isSameDay(day.date, viewModel.state.selectedDay),
                            dotColors: viewModel.events(on: day.date).prefix(3).map(\.color)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("day-\(viewModel.dates.dayKey(day.date))")
                }
            }
            .id(viewModel.state.visibleMonth)
            .transition(.push(from: movesForward ? .trailing : .leading))
        }
        .frame(height: gridHeight)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    // Only a mostly horizontal drag changes month, so vertical scrolling elsewhere is not affected.
                    guard abs(horizontal) > 60, abs(horizontal) > abs(vertical) else { return }
                    onSwipe(horizontal < 0)
                }
        )
        .padding(.horizontal, 16)
    }
}
