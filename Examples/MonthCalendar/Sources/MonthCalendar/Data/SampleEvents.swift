import Foundation

enum SampleEvents {
    static let titles = [
        "Team standup", "Coffee with Ana", "Dentist", "Design review", "Gym",
        "Lunch with Marco", "Project planning", "Book club", "Call with the Lisbon office",
        "Birthday dinner", "Code review", "Yoga", "Ship release notes", "Parent-teacher meeting",
    ]

    // About 40 events spread from ten days before today to forty days after, so both the month view and the
    // 60-day agenda have content.
    static func make(today: Date, calendar: Calendar) -> [CalendarEvent] {
        var random = SeedRandom(seed: 20_261_111)
        let colors = EventColor.allCases
        var result: [CalendarEvent] = []
        for index in 0..<40 {
            let dayOffset = random.int(in: -10..<41)
            let title = titles[random.int(in: 0..<titles.count)]
            let color = colors[random.int(in: 0..<colors.count)]
            let isAllDay = random.int(in: 0..<8) == 0
            let startHour = random.int(in: 8..<18)
            let durationHours = random.int(in: 1..<4)

            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            let start: Date
            let end: Date
            if isAllDay {
                start = calendar.startOfDay(for: day)
                end = start
            } else {
                start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: day) ?? day
                end = start.addingTimeInterval(TimeInterval(durationHours * 3600))
            }
            result.append(
                CalendarEvent(
                    id: "seed-\(index)",
                    title: title,
                    start: start,
                    end: end,
                    isAllDay: isAllDay,
                    color: color
                )
            )
        }
        return result.sorted { $0.start < $1.start }
    }
}
