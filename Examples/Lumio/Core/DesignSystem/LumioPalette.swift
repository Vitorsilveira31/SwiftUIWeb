import SwiftUIWeb

/// The colors of Lumio: a warm gradient for the brand and for what is new, soft grays for the rest.
enum LumioPalette {
  static let amber = Color(red: 1.00, green: 0.72, blue: 0.20)
  static let coral = Color(red: 0.98, green: 0.36, blue: 0.36)
  static let violet = Color(red: 0.55, green: 0.27, blue: 0.85)
  static let like = Color(red: 0.93, green: 0.18, blue: 0.30)

  static var brand: LinearGradient {
    LinearGradient(colors: [amber, coral, violet], startPoint: .bottomLeading, endPoint: .topTrailing)
  }
}
