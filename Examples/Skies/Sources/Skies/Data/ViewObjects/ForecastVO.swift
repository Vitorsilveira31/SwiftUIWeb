enum ForecastSource: Hashable, Sendable {
    case live
    case sample
}

struct ForecastVO: Hashable, Sendable {
    let current: HourVO
    let hours: [HourVO]       // the next 24 hours after the current one
    let days: [DayVO]         // seven days, today first
    let updated: String       // "yyyy-MM-dd · HH:mm" in the city's timezone
    let source: ForecastSource

    // The selected hourly card by id, or the current conditions for "now".
    func hour(_ selection: String) -> HourVO {
        hours.first { $0.id == selection } ?? current
    }

    func day(for hour: HourVO) -> DayVO? {
        let date = String(hour.time.prefix(10))
        return days.first { $0.id == date } ?? days.first
    }
}
