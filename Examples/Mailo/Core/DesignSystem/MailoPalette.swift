import SwiftUIWeb

/// The colors of Mailo: a sun for the mark and the stars, sea blue for the actions, soft paper for the surfaces.
enum MailoPalette {
  static let sun = Color(red: 1.00, green: 0.74, blue: 0.22)
  static let coral = Color(red: 0.95, green: 0.45, blue: 0.25)
  static let sea = Color(red: 0.16, green: 0.42, blue: 0.62)
  static let star = Color(red: 0.93, green: 0.62, blue: 0.08)
  static let paper = Color(red: 0.98, green: 0.97, blue: 0.94)
  static let selection = Color(red: 0.99, green: 0.93, blue: 0.80)
  static let muted = Color(red: 0.42, green: 0.45, blue: 0.50)
  static let avatars = [sea, Color(red: 0.42, green: 0.55, blue: 0.30), Color(red: 0.62, green: 0.32, blue: 0.48), Color(red: 0.70, green: 0.38, blue: 0.22)]

  static var mark: LinearGradient {
    LinearGradient(colors: [sun, coral], startPoint: .bottomLeading, endPoint: .topTrailing)
  }
}
