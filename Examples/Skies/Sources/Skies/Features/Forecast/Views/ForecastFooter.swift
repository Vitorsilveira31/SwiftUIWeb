import SwiftUI

// The Open-Meteo credit, and which forecast is on screen and when it was made.
struct ForecastFooter: View {
    let source: ForecastSource
    let updated: String
    let loading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let url = Links.openMeteo {
                Link(Strings.Forecast.credit, destination: url)
                    .font(.caption)
            }
            Text(status)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("forecast-status")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 10)
    }

    private var status: String {
        let base = source == .sample ? Strings.Forecast.sampleForecast : Strings.Forecast.localTime(updated)
        return loading ? Strings.Forecast.updating(base) : base
    }
}
