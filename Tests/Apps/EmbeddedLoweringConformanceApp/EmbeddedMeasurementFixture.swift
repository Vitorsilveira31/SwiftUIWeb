import SwiftUIWeb


// Foundation's MeasurementFormatter as an app writes it. en_US converts to the locale's preferred units (pounds,
// Fahrenheit) and pt_BR keeps metric. The browser build names the units with the host's Intl formatter, so the
// names and the numbers follow the locale.
struct EmbeddedMeasurementFixtureView: View {
  var body: some View {
    VStack {
      ForEach(EmbeddedMeasurementFixtureView.lines, id: \.self) { line in
        Text(line)
      }
    }
  }

  static var lines: [String] {
    let weight = Measurement(value: 5, unit: UnitMass.kilograms)
    let temperature = Measurement(value: 20, unit: UnitTemperature.celsius)
    var result: [String] = []
    for (name, identifier, style) in [("en_US", "en_US", Formatter.UnitStyle.medium),
                                       ("pt_BR", "pt_BR", .medium),
                                       ("en_US long", "en_US", .long),
                                       ("pt_BR long", "pt_BR", .long)] {
      let formatter = MeasurementFormatter()
      formatter.locale = Locale(identifier: identifier)
      formatter.unitStyle = style
      result.append("\(name): \(formatter.string(from: weight)) | \(formatter.string(from: temperature))")
    }
    let provided = MeasurementFormatter()
    provided.locale = Locale(identifier: "en_US")
    provided.unitOptions = [.providedUnit]
    result.append("en_US provided: \(provided.string(from: weight)) | \(provided.string(from: temperature))")
    // Foundation's NSUnit equality: the same class and symbol, with the same hash.
    let equal = [UnitMass.kilograms == UnitMass.kilograms,
                 UnitMass.kilograms == UnitMass.grams,
                 UnitTemperature.celsius == UnitTemperature.kelvin,
                 Unit(symbol: "kg") == Unit(symbol: "kg"),
                 Unit(symbol: "kg") == UnitMass.kilograms,
                 Set([Unit(symbol: "x"), Unit(symbol: "x")]).count == 1]
    result.append("unit equality: \(equal.map { $0 ? "same" : "different" }.joined(separator: " "))")
    // NSKeyedArchiver rejects an object that is not NSCoding (Foundation throws NSCocoaError 4866).
    let rejected = (try? NSKeyedArchiver.archivedData(withRootObject: NSObject(), requiringSecureCoding: true)) == nil
    result.append("archive rejects NSObject: \(rejected ? "true" : "false")")
    return result
  }
}
