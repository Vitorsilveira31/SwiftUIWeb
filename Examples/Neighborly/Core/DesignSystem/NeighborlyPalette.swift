import SwiftUIWeb

/// The colors of Neighborly: a teal for the brand, a sunny yellow for the people in it, and the tokens of the page for the rest.
enum NeighborlyPalette {
  static let teal = Color(red: 0.0, green: 0.48, blue: 0.45)
  static let sea = Color(red: 0.16, green: 0.66, blue: 0.6)
  static let sun = Color(red: 1.0, green: 0.78, blue: 0.25)
  static let like = Color(red: 0.0, green: 0.48, blue: 0.45)
  static let canvas = Color.background
  static let card = Color.surface
  static let line = Color.border
  static let muted = Color.mutedForeground

  static var brand: LinearGradient {
    LinearGradient(colors: [teal, sea], startPoint: .topLeading, endPoint: .bottomTrailing)
  }
}
