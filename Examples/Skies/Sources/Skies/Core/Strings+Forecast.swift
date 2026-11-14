extension Strings {
    enum Forecast {
        static let units = "Units"
        static let useMyLocation = "Use my location"
        static let failure = "Showing sample data. The forecast couldn’t be reached. Check your connection and try again."
        static let tryAgain = "Try again"
        static let credit = "Weather data by Open-Meteo · CC BY 4.0"
        static let sampleForecast = "Sample forecast"
        static let updatingForecast = "UPDATING FORECAST"
        static let rightNow = "RIGHT NOW"
        static let now = "Now"
        static let live = "Live"
        static let today = "Today"
        static let backToNow = "↶ Back to now"
        static let playSky = "Play sky animation"
        static let pauseSky = "Pause sky animation"
        static let theDayUnfolding = "The day, unfolding"
        static let chooseHour = "Choose an hour. Watch the sky change."
        static let next24Hours = "NEXT 24 HOURS"
        static let lookAhead = "A look ahead"

        static func localTime(_ updated: String) -> String {
            "Local forecast time \(updated)"
        }

        static func updating(_ status: String) -> String {
            "\(status) · updating"
        }

        static func hourForecast(_ clock: String) -> String {
            "\(clock) FORECAST"
        }

        static func dayHourForecast(_ weekday: String, _ clock: String) -> String {
            "\(weekday) · \(clock) FORECAST"
        }

        static func dayCount(_ count: Int) -> String {
            "\(count)-DAY FORECAST"
        }

        static func highLowFeels(high: String, low: String, feelsLike: String) -> String {
            "H \(high)   L \(low)  ·  Feels like \(feelsLike)"
        }

        static func hourCardLabel(_ title: String, _ primary: String, _ secondary: String) -> String {
            "\(title), \(primary), \(secondary)"
        }
    }

    enum Elements {
        static let title = "Out in the elements"
        static let wind = "Wind"
        static let humidity = "Humidity"
        static let feelsLike = "Feels like"
        static let rainChance = "Rain chance"
        static let pressure = "Pressure"
        static let uvIndex = "UV index"
        static let sun = "Sun"
        static let sunrise = "SUNRISE"
        static let sunset = "SUNSET"
        static let compass = "Wind compass"
        static let compassPoints = ["N", "E", "S", "W"]
    }

    enum Time {
        static let am = "am"
        static let pm = "pm"
        static let unknownDay = "—"
    }
}
