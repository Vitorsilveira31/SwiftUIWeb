// Open-Meteo's JSON, as decoded with convertFromSnakeCase: `temperature_2m` arrives as
// `temperature2M`. Every hourly and daily array is parallel to its `time` array.
struct ForecastResponse: Decodable, Sendable {
    struct Current: Decodable, Sendable {
        let time: String
        let temperature2M: Double
        let apparentTemperature: Double
        let relativeHumidity2M: Double
        let isDay: Double
        let precipitation: Double
        let weatherCode: Double
        let cloudCover: Double
        let windSpeed10M: Double
        let pressureMsl: Double
    }

    struct Hourly: Decodable, Sendable {
        let time: [String]
        let temperature2M: [Double]
        let apparentTemperature: [Double]
        let relativeHumidity2M: [Double]
        let isDay: [Double]
        let precipitation: [Double]
        let weatherCode: [Double]
        let cloudCover: [Double]
        let windSpeed10M: [Double]
        let pressureMsl: [Double]
        let precipitationProbability: [Double]
    }

    struct Daily: Decodable, Sendable {
        let time: [String]
        let weatherCode: [Double]
        let temperature2MMax: [Double]
        let temperature2MMin: [Double]
        let sunrise: [String]
        let sunset: [String]
        let uvIndexMax: [Double]
        let precipitationProbabilityMax: [Double]
    }

    let current: Current
    let hourly: Hourly
    let daily: Daily
}
