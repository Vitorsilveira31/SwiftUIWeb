import Foundation

// The same public Open-Meteo endpoint and parameters as the reference app. The
// `current` and `hourly` lists share one set of variables; `pressure_msl` is added
// to them for the pressure tile.
struct OpenMeteoForecastRepository: ForecastRepository {
    private static let common = "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,cloud_cover,wind_speed_10m,pressure_msl"

    func forecast(for city: CityVO) async throws -> ForecastVO {
        let text = "https://api.open-meteo.com/v1/forecast?latitude=\(city.latitude)&longitude=\(city.longitude)&timezone=auto&forecast_days=7&current=\(Self.common)&hourly=\(Self.common),precipitation_probability&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,precipitation_probability_max"
        guard let url = URL(string: text) else { throw ForecastError.unavailable }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ForecastError.unavailable }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let wire = try decoder.decode(ForecastResponse.self, from: data)
        return try ForecastMapper.make(wire)
    }
}
