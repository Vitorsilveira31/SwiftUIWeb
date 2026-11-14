import SwiftUIWeb

/// The colors of Stayly: a deep teal for the brand, sand for the surfaces, a coral for the action that books and gold for ratings.
enum StaylyPalette {
  static let teal = Color(red: 0.05, green: 0.42, blue: 0.45)
  static let deepTeal = Color(red: 0.03, green: 0.25, blue: 0.29)
  static let sand = Color(red: 0.97, green: 0.94, blue: 0.89)
  static let coral = Color(red: 0.93, green: 0.42, blue: 0.31)
  static let gold = Color(red: 0.95, green: 0.74, blue: 0.22)

  static var brand: LinearGradient {
    LinearGradient(colors: [teal, deepTeal], startPoint: .topLeading, endPoint: .bottomTrailing)
  }
}
