// Open-Meteo returns Celsius and km/h. The unit switch converts for display only.
enum TemperatureUnit: String, CaseIterable, Hashable, Sendable {
    case celsius = "C"
    case fahrenheit = "F"

    var label: String {
        self == .celsius ? Strings.Units.celsius : Strings.Units.fahrenheit
    }

    func temperature(_ celsius: Double) -> String {
        let value = self == .celsius ? celsius : celsius * 9 / 5 + 32
        return "\(Int(value.rounded()))°"
    }

    func wind(_ kilometresPerHour: Double) -> String {
        self == .celsius
            ? "\(Int(kilometresPerHour.rounded())) \(Strings.Units.kilometresPerHour)"
            : "\(Int((kilometresPerHour / 1.609344).rounded())) \(Strings.Units.milesPerHour)"
    }
}
