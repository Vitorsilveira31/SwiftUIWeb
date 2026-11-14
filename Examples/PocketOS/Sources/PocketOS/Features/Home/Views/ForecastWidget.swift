import SwiftUI

// The forecast: the place, the temperature, the high and low, and the next three hours.
struct ForecastWidget: View {
    let forecast: Forecast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(forecast.place)
                .font(Voice.title(15))
            Text("\(forecast.temperature)°")
                .font(Voice.display(50))
                .lineLimit(1)
            Text(forecast.condition)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Text(Strings.Home.highLow(forecast.high, forecast.low))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                ForEach(forecast.hours.prefix(3)) { hour in
                    VStack(spacing: 3) {
                        Image(systemName: hour.symbol)
                            .font(.system(size: 13))
                        Text("\(hour.temperature)°")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .leading)
        .background(Color.gray.opacity(0.32), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityIdentifier("widget-forecast")
    }
}
