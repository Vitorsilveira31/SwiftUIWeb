import Foundation

// Calendar arithmetic for the month grid, the weekday row and the agenda. Every computation goes through `calendar`,
// so the grid follows the user's locale and first weekday.
struct CalendarDates {
    let calendar: Calendar
    let today: Date

    // Very short weekday symbols start at Sunday; rotate them so the first column is the calendar's firstWeekday.
    var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return (0..<symbols.count).map { symbols[($0 + shift) % symbols.count] }
    }

    func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    func startOfMonth(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    func isSameDay(_ first: Date, _ second: Date) -> Bool {
        calendar.isDate(first, inSameDayAs: second)
    }

    func isSameMonth(_ first: Date, _ second: Date) -> Bool {
        calendar.isDate(first, equalTo: second, toGranularity: .month)
    }

    func dayNumber(_ date: Date) -> Int {
        calendar.component(.day, from: date)
    }

    // Always 42 cells (six weeks) so the grid height does not change between months.
    func gridDays(for month: Date) -> [CalendarGridDay] {
        let weekdayOfFirst = calendar.component(.weekday, from: month)
        let leading = (weekdayOfFirst - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leading, to: month) ?? month
        return (0..<42).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: gridStart) else { return nil }
            return CalendarGridDay(date: date, isInMonth: isSameMonth(date, month))
        }
    }

    // The next 60 days starting today, used by the agenda list.
    func agendaDays() -> [Date] {
        (0..<60).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    // yyyy-MM-dd, built from components so it does not depend on a formatter's time zone.
    func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        return "\(year)-\(pad(month))-\(pad(day))"
    }

    func shiftedMonth(_ month: Date, by months: Int) -> Date? {
        guard let target = calendar.date(byAdding: .month, value: months, to: month) else { return nil }
        return startOfMonth(target)
    }

    // Keeps the same day number where the new month has it, as the iOS Calendar does.
    func day(sameNumberAs day: Date, in month: Date) -> Date? {
        let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
        let target = min(dayNumber(day), daysInMonth)
        return calendar.date(byAdding: .day, value: target - 1, to: month)
    }

    func date(atHour hour: Int, on day: Date) -> Date? {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
    }

    private func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
