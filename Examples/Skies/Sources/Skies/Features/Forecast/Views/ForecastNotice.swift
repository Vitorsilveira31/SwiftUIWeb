import SwiftUI

// Shown when the request fails: the sample is on screen, and this offers another try.
struct ForecastNotice: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(Strings.Forecast.tryAgain, action: retry)
                .font(.footnote.weight(.semibold))
                .accessibilityIdentifier("retry-weather")
        }
        .cardStyle()
        .accessibilityIdentifier("network-notice")
    }
}
