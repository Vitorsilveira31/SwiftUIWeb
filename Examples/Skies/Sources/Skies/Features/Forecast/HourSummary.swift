// One sentence about the selected hour, in the reference's voice.
enum HourSummary {
    static func text(for hour: HourVO) -> String {
        if hour.weatherCode >= 95 { return Strings.Summary.thunderstorms }
        if hour.precipitation > 0 { return Strings.Summary.weatherMoving }
        if hour.chance >= 50 { return Strings.Summary.rainLikely }
        if hour.windSpeed > 30 { return Strings.Summary.breezy }
        if !hour.isDay { return Strings.Summary.quieterSky }
        if hour.cloudCover > 70 { return Strings.Summary.cloudy }
        return Strings.Summary.sunny
    }
}
