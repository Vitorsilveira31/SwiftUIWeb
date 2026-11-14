// A browser stand-in for WeatherKit, so Apple's Food Truck weather screens run unmodified.
//
// WeatherKit needs an Apple developer entitlement and has no browser API. The forecast here is a deterministic
// demonstration (a mild day that warms into the afternoon and rains a little later), so the cards, the chart and the
// recommendation logic all have data to show.
import SwiftUIWeb
import SwiftUIWebCoreLocation

public enum WeatherCondition: String, Hashable, Sendable {
  case clear, mostlyClear, partlyCloudy, mostlyCloudy, cloudy, drizzle, rain, heavyRain, thunderstorms, snow, foggy, windy

  public var description: String {
    switch self {
    case .clear: return "Clear"
    case .mostlyClear: return "Mostly Clear"
    case .partlyCloudy: return "Partly Cloudy"
    case .mostlyCloudy: return "Mostly Cloudy"
    case .cloudy: return "Cloudy"
    case .drizzle: return "Drizzle"
    case .rain: return "Rain"
    case .heavyRain: return "Heavy Rain"
    case .thunderstorms: return "Thunderstorms"
    case .snow: return "Snow"
    case .foggy: return "Foggy"
    case .windy: return "Windy"
    }
  }
}

public struct CurrentWeather: Sendable {
  public let condition: WeatherCondition
  public let cloudCover: Double
  public let temperature: Measurement<UnitTemperature>
  public let symbolName: String
}

public struct MinuteWeather: Sendable {
  public let date: Date
  public let precipitationChance: Double
}

public struct HourWeather: Sendable {
  public let date: Date
  public let temperature: Measurement<UnitTemperature>
  public let isDaylight: Bool
}

public struct Forecast<Element: Sendable>: Sequence, Sendable {
  public let forecast: [Element]
  public func makeIterator() -> IndexingIterator<[Element]> { forecast.makeIterator() }
}

public struct Weather: Sendable {
  public let currentWeather: CurrentWeather
  public let minuteForecast: Forecast<MinuteWeather>?
  public let hourlyForecast: Forecast<HourWeather>
}

public struct WeatherQuery<Result: Sendable>: Sendable {
  let make: @Sendable (CLLocation) -> Result

  public static var hourly: WeatherQuery<Forecast<HourWeather>> {
    WeatherQuery<Forecast<HourWeather>> { DemoWeather.hours(for: $0) }
  }
}

public struct WeatherAttribution: Sendable {
  public let legalPageURL: URL
  public let combinedMarkLightURL: URL
  public let combinedMarkDarkURL: URL
}

public final class WeatherService: Sendable {
  public static let shared = WeatherService()

  public var attribution: WeatherAttribution {
    get async throws {
      let page = URL(string: "https://developer.apple.com/weatherkit/data-source-attribution/")!
      return WeatherAttribution(legalPageURL: page, combinedMarkLightURL: page, combinedMarkDarkURL: page)
    }
  }

  public func weather(for location: CLLocation) async throws -> Weather {
    let hours = DemoWeather.hours(for: location)
    let now = Date()
    let minutes = (0 ..< 60).map { MinuteWeather(date: now.addingTimeInterval(Double($0) * 60), precipitationChance: 0.05) }
    return Weather(
      currentWeather: CurrentWeather(
        condition: .partlyCloudy, cloudCover: 0.3,
        temperature: Measurement(value: 19, unit: UnitTemperature.celsius), symbolName: "cloud.sun"
      ),
      minuteForecast: Forecast(forecast: minutes),
      hourlyForecast: hours
    )
  }

  public func weather<Result>(for location: CLLocation, including query: WeatherQuery<Result>) async throws -> Result {
    query.make(location)
  }
}

enum DemoWeather {
  /// Twenty-four hours from the current hour: coolest before dawn, warmest mid-afternoon (UTC-agnostic, by clock hour).
  static func hours(for location: CLLocation) -> Forecast<HourWeather> {
    let start = Date()
    let entries = (0 ..< 24).map { offset -> HourWeather in
      let date = start.addingTimeInterval(Double(offset) * 3600)
      let hour = Calendar.current.component(.hour, from: date)
      let swing = 6 * sineApproximation(Double(hour - 9) / 24 * 2 * 3.141_592_653_589_793)
      return HourWeather(
        date: date,
        temperature: Measurement(value: 18 + swing, unit: UnitTemperature.celsius),
        isDaylight: hour >= 6 && hour < 19
      )
    }
    return Forecast(forecast: entries)
  }

  /// Bhaskara's sine approximation: no libm in the browser build, and a day's temperature curve needs no more.
  static func sineApproximation(_ radians: Double) -> Double {
    let pi = 3.141_592_653_589_793
    var x = radians
    while x > pi { x -= 2 * pi }
    while x < -pi { x += 2 * pi }
    let sign = x < 0 ? -1.0 : 1.0
    let value = abs(x)
    return sign * 16 * value * (pi - value) / (5 * pi * pi - 4 * value * (pi - value))
  }
}
