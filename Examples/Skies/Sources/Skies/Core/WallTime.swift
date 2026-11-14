import Foundation

// Open-Meteo's wall-clock strings ("yyyy-MM-ddTHH:mm") are read by position, in the
// city's own zone: converting through the device zone would shift the day.
enum WallTime {
    static func hour(of time: String) -> Double {
        let hours = Int(time.dropFirst(11).prefix(2)) ?? 0
        let minutes = Int(time.dropFirst(14).prefix(2)) ?? 0
        return Double(hours) + Double(minutes) / 60
    }

    static func clock(_ time: String) -> String {
        let hours = Int(hour(of: time))
        let suffix = hours < 12 ? Strings.Time.am : Strings.Time.pm
        return "\(hours % 12 == 0 ? 12 : hours % 12):\(time.dropFirst(14).prefix(2)) \(suffix)"
    }

    static func hourLabel(_ time: String) -> String {
        let hours = Int(hour(of: time))
        let suffix = hours < 12 ? Strings.Time.am : Strings.Time.pm
        return "\(hours % 12 == 0 ? 12 : hours % 12)\(suffix)"
    }

    // "yyyy-MM-dd" to "Mon"; the date is a calendar day, so UTC is the honest zone.
    static func weekday(_ day: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: day) else { return Strings.Time.unknownDay }
        parser.dateFormat = "EEE"
        return parser.string(from: date)
    }
}
