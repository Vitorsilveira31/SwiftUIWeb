import SwiftUI

struct CalendarDayCell: View {
    let number: Int
    let isInMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let dotColors: [EventColor]

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if isSelected {
                    Circle().fill(.tint).frame(width: 30, height: 30)
                } else if isToday {
                    Circle().strokeBorder(.tint, lineWidth: 1.5).frame(width: 30, height: 30)
                }
                Text("\(number)")
                    .font(.body.monospacedDigit())
                    .fontWeight(isSelected || isToday ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : Color.primary))
            }
            .frame(width: 30, height: 30)

            HStack(spacing: 3) {
                ForEach(Array(dotColors.enumerated()), id: \.offset) { item in
                    Circle()
                        .fill(item.element.color)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .contentShape(Rectangle())
        .opacity(isInMonth ? 1 : 0.35)
    }
}
