import SwiftUI

// One hour in the strip: its time, symbol, temperature and chance of rain.
struct HourCard: View {
    let title: String
    let symbol: String
    let primary: String
    let secondary: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 13) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(selected ? .white : .secondary)
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(selected ? .white : .orange)
                Text(primary)
                    .font(.headline)
                    .foregroundStyle(selected ? .white : .primary)
                Text(secondary)
                    .font(.caption2)
                    .foregroundStyle(selected ? .white : .secondary)
            }
            .frame(width: 88, height: 150)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selected ? Color.accentColor : Color.gray.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.Forecast.hourCardLabel(title, primary, secondary))
    }
}
