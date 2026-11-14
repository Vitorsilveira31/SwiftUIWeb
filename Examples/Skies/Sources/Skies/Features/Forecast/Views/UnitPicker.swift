import SwiftUI

// The °C / °F switch above the hero.
struct UnitPicker: View {
    let unit: TemperatureUnit
    let onSelect: (TemperatureUnit) -> Void

    var body: some View {
        HStack {
            Spacer()
            Picker(Strings.Forecast.units, selection: Binding(get: { unit }, set: { onSelect($0) })) {
                ForEach(TemperatureUnit.allCases, id: \.self) { option in
                    Text(option.label)
                        .accessibilityIdentifier("unit-\(option.rawValue.lowercased())")
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)
        }
    }
}
