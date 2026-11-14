import SwiftUIWeb

/// The colors of Seekr: four clear hues for the wordmark, one indigo-to-teal gradient for the mark and the links. The text keeps the
/// theme's own colors, so the app reads in light and dark.
enum SeekrPalette {
  static let indigo = Color(red: 0.24, green: 0.36, blue: 0.94)
  static let coral = Color(red: 0.95, green: 0.38, blue: 0.36)
  static let amber = Color(red: 0.98, green: 0.70, blue: 0.16)
  static let teal = Color(red: 0.10, green: 0.62, blue: 0.56)

  static var brand: LinearGradient {
    LinearGradient(colors: [indigo, teal], startPoint: .topLeading, endPoint: .bottomTrailing)
  }
}
