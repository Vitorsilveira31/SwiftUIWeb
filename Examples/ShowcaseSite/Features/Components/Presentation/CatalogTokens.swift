import SwiftUIWeb

/// The words a knob offers (`title`, `blue`) and the SwiftUI values they stand for. The same words are written in the code
/// the catalog shows, so the reader sees both sides of one choice.
enum CatalogTokens {
  static let fonts = ["largeTitle", "title", "headline", "body", "caption"]
  static let colors = ["primary", "secondary", "blue", "red", "green", "orange"]

  static func font(_ token: String) -> Font {
    switch token {
    case "largeTitle": return .largeTitle
    case "title": return .title
    case "headline": return .headline
    case "caption": return .caption
    default: return .body
    }
  }

  static func color(_ token: String) -> Color {
    switch token {
    case "secondary": return .secondary
    case "blue": return .blue
    case "red": return .red
    case "green": return .green
    case "orange": return .orange
    default: return .primary
    }
  }
}
