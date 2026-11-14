// Open-Meteo's WMO weather codes as the words, symbols and precipitation the screen shows.
enum WeatherCondition {
    static func text(code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? Strings.Weather.clearSkies : Strings.Weather.clearNight
        case 1: return Strings.Weather.mostlyClear
        case 2: return Strings.Weather.partlyCloudy
        case 3: return Strings.Weather.overcast
        case 45, 48: return Strings.Weather.foggy
        case 51...57: return Strings.Weather.drizzle
        case 61...67: return Strings.Weather.rain
        case 71...77: return Strings.Weather.snow
        case 80...82: return Strings.Weather.rainShowers
        case 85, 86: return Strings.Weather.snowShowers
        case 95...: return Strings.Weather.thunderstorms
        default: return Strings.Weather.variableSkies
        }
    }

    static func symbol(code: Int, isDay: Bool) -> String {
        switch code {
        case 0, 1: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...: return "cloud.bolt.rain.fill"
        default: return "cloud.sun.fill"
        }
    }

    // Only wet hours animate precipitation in the sky.
    static func precipitation(code: Int, amount: Double) -> PrecipitationKind {
        guard amount >= 0.05 else { return .dry }
        switch code {
        case 95...: return .storm
        case 71...77, 85, 86: return .snow
        case 51...67, 80...82: return .rain
        default: return .dry
        }
    }
}
