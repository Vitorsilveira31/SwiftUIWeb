// Locale preferences for `MeasurementFormatter`, shared by the browser and native-test builds. Foundation converts a
// measurement to the first unit in its region's preference list unless the unit is already in that list, and only
// then (`unitOptions` without `.providedUnit`). The lists are CLDR `unitPreferenceData` (usage "default") for the units
// WebFoundation models, checked against Foundation's output for the regions below: a unit in a list is kept, any other
// unit converts to the list's first entry. Identifiers are CLDR unit names.
//
// Foundation-free on purpose: the conversion itself lives with the unit classes, and these tables are tested natively.

enum _MeasurementPreferences {
  /// The region used for a language without one: Foundation completes `en` to `en_US`, and the other shipped languages to
  /// a region whose preferences are metric.
  /// Empty when the locale has no region and no implied one.
  static func effectiveRegion(_ region: String?, language: String?) -> String {
    if let region, !region.isEmpty { return region.uppercased() }
    return language?.lowercased() == "en" ? "US" : ""
  }

  /// Mass preferences. The United States uses pounds; the United Kingdom and Hong Kong keep every mass unit they are given.
  static func massIdentifiers(region: String) -> [String] {
    switch region {
    case "US": ["pound"]
    case "GB", "HK": ["kilogram", "gram", "pound", "ounce", "stone", "metric-ton"]
    default: ["kilogram"]
    }
  }

  /// Length preferences. Road distances are in miles in the United States and the United Kingdom.
  static func lengthIdentifiers(region: String) -> [String] {
    switch region {
    case "US", "GB": ["mile"]
    default: ["kilometer"]
    }
  }

  /// Temperature preferences. Fahrenheit is used in the United States and the Caribbean and Pacific territories below.
  static func temperatureIdentifiers(region: String) -> [String] {
    switch region {
    case "US", "BS", "BZ", "KY", "PR", "PW": ["fahrenheit"]
    default: ["celsius"]
    }
  }

  /// Whether `Intl.NumberFormat` knows the unit as a sanctioned simple unit (ECMA-402). Other units are named in English.
  static func hasIntlName(_ identifier: String) -> Bool {
    switch identifier {
    case "kilogram", "gram", "pound", "ounce", "stone", "celsius", "fahrenheit",
         "meter", "kilometer", "centimeter", "millimeter", "mile", "foot", "inch", "yard":
      true
    default:
      false
    }
  }
}
