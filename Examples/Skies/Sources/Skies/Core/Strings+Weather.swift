extension Strings {
    enum Weather {
        static let clearSkies = "Clear skies"
        static let clearNight = "A clear night"
        static let mostlyClear = "Mostly clear"
        static let partlyCloudy = "Partly cloudy"
        static let overcast = "Overcast"
        static let foggy = "Foggy"
        static let drizzle = "Drizzle"
        static let rain = "Rain"
        static let snow = "Snow"
        static let rainShowers = "Rain showers"
        static let snowShowers = "Snow showers"
        static let thunderstorms = "Thunderstorms"
        static let variableSkies = "Variable skies"
    }

    enum Summary {
        static let thunderstorms = "Thunderstorms in the forecast. Keep an eye on local alerts."
        static let weatherMoving = "A little weather moving through. Bring a layer and an umbrella."
        static let rainLikely = "Rain may be on the way. An umbrella could come in handy."
        static let breezy = "A breezy stretch ahead. Take a layer for the wind."
        static let quieterSky = "The day gives way to a quieter sky."
        static let cloudy = "A soft blanket of cloud over the city."
        static let sunny = "Some room for sunshine. A good moment to step outside."
    }

    enum UV {
        static let low = "Low"
        static let moderate = "Moderate"
        static let high = "High"
        static let veryHigh = "Very high"

        static func reading(_ index: Int, _ band: String) -> String {
            "\(index) · \(band)"
        }
    }
}
