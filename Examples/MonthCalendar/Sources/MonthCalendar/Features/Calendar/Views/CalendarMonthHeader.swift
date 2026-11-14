import SwiftUI

struct CalendarMonthHeader: View {
    let visibleMonth: Date
    let onToday: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                .font(.title2.bold())
                .contentTransition(.opacity)
                .accessibilityIdentifier("calendar-title")
            Spacer()
            Button(Strings.Month.today) { onToday() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("calendar-today")
            Button { onPrevious() } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel(Strings.Month.previousMonth)
                .accessibilityIdentifier("calendar-prev")
            Button { onNext() } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel(Strings.Month.nextMonth)
                .accessibilityIdentifier("calendar-next")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}
