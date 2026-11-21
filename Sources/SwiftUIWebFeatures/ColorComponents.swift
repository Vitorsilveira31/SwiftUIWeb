@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
// Color components for code that asks for them (`Color.resolve(in:)`, `UIColor` conversions). Colors here are CSS
// values the browser resolves at paint time, so the components are read back from the value as written:
// `#RRGGBB[AA]`, `rgb()`/`rgba()`, `color(srgb ...)`, the light side of `light-dark()`, the fallback of `var()`, and
// `color-mix()` of those. Anything else (a system keyword the browser alone can resolve) reads as the keyword's
// light-scheme color.
extension Color {
  /// The color as the browser would paint it in the light scheme (see the notes above).
  public func resolve(in environment: EnvironmentValues) -> Resolved {
    let value = _CSSColorComponents.parse(cssValue)
    return Resolved(red: Float(value.red), green: Float(value.green), blue: Float(value.blue), opacity: Float(value.alpha))
  }
}

struct _CSSColorComponents {
  var red = 0.0, green = 0.0, blue = 0.0, alpha = 1.0

  static func parse(_ css: String) -> _CSSColorComponents {
    let text = css.trimmingASCIIWhitespace()
    if text.hasPrefix("#") { return hex(String(text.dropFirst())) }
    if let arguments = functionArguments(text, "light-dark") { return parse(topLevelSplit(arguments, ",").first ?? "") }
    if let arguments = functionArguments(text, "var") {
      let parts = topLevelSplit(arguments, ",")
      return parts.count > 1 ? parse(parts[1...].joined(separator: ",")) : _CSSColorComponents()
    }
    if let arguments = functionArguments(text, "color-mix") { return mix(arguments) }
    for name in ["rgba", "rgb"] {
      if let arguments = functionArguments(text, name) { return rgb(arguments) }
    }
    if let arguments = functionArguments(text, "color") { return colorFunction(arguments) }
    switch text.lowercased() {
    case "white", "canvas": return _CSSColorComponents(red: 1, green: 1, blue: 1)
    case "transparent": return _CSSColorComponents(red: 0, green: 0, blue: 0, alpha: 0)
    case "graytext": return _CSSColorComponents(red: 0.43, green: 0.43, blue: 0.43)
    default: return _CSSColorComponents()
    }
  }

  private static func hex(_ digits: String) -> _CSSColorComponents {
    var chars = Array(digits)
    if chars.count == 3 || chars.count == 4 { chars = chars.flatMap { [$0, $0] } }
    func byte(_ index: Int) -> Double {
      guard index + 1 < chars.count, let value = UInt8(String(chars[index...index + 1]), radix: 16) else { return 1 }
      return Double(value) / 255
    }
    return _CSSColorComponents(red: byte(0), green: byte(2), blue: byte(4), alpha: chars.count >= 8 ? byte(6) : 1)
  }

  private static func rgb(_ arguments: String) -> _CSSColorComponents {
    let separators = arguments.replacingOccurrences(of: "/", with: " ").replacingOccurrences(of: ",", with: " ")
    let numbers = separators.split(separator: " ").compactMap { piece -> Double? in
      piece.hasSuffix("%") ? Double(piece.dropLast()).map { $0 / 100 } : Double(piece)
    }
    guard numbers.count >= 3 else { return _CSSColorComponents() }
    return _CSSColorComponents(red: numbers[0] / 255, green: numbers[1] / 255, blue: numbers[2] / 255, alpha: numbers.count > 3 ? numbers[3] : 1)
  }

  private static func colorFunction(_ arguments: String) -> _CSSColorComponents {
    let numbers = arguments.replacingOccurrences(of: "/", with: " ").split(separator: " ").compactMap { Double($0) }
    guard numbers.count >= 3 else { return _CSSColorComponents() }
    return _CSSColorComponents(red: numbers[0], green: numbers[1], blue: numbers[2], alpha: numbers.count > 3 ? numbers[3] : 1)
  }

  private static func mix(_ arguments: String) -> _CSSColorComponents {
    let parts = topLevelSplit(arguments, ",").dropFirst()
    var colors: [(_CSSColorComponents, Double?)] = []
    for part in parts {
      let pieces = part.trimmingASCIIWhitespace().split(separator: " ")
      guard let last = pieces.last else { continue }
      if last.hasSuffix("%"), let percent = Double(last.dropLast()) {
        colors.append((parse(pieces.dropLast().joined(separator: " ")), percent / 100))
      } else {
        colors.append((parse(part), nil))
      }
    }
    guard colors.count == 2 else { return colors.first?.0 ?? _CSSColorComponents() }
    let first = colors[0].1 ?? (1 - (colors[1].1 ?? 0.5))
    let second = colors[1].1 ?? (1 - first)
    let total = first + second
    let (a, b) = (colors[0].0, colors[1].0)
    let alpha = a.alpha * first / total + b.alpha * second / total
    func channel(_ x: Double, _ y: Double) -> Double {
      let weight = a.alpha * first + b.alpha * second
      return weight == 0 ? 0 : (x * a.alpha * first + y * b.alpha * second) / weight
    }
    return _CSSColorComponents(red: channel(a.red, b.red), green: channel(a.green, b.green), blue: channel(a.blue, b.blue), alpha: alpha)
  }

  private static func functionArguments(_ text: String, _ name: String) -> String? {
    let lower = text.lowercased()
    guard lower.hasPrefix(name + "("), text.hasSuffix(")") else { return nil }
    return String(text.dropFirst(name.count + 1).dropLast())
  }

  private static func topLevelSplit(_ text: String, _ separator: Character) -> [String] {
    var parts: [String] = []
    var depth = 0
    var current = ""
    for character in text {
      if character == "(" { depth += 1 }
      if character == ")" { depth -= 1 }
      if character == separator && depth == 0 { parts.append(current); current = "" } else { current.append(character) }
    }
    parts.append(current)
    return parts
  }
}

private extension String {
  func trimmingASCIIWhitespace() -> String {
    var slice = Substring(self)
    while let first = slice.first, first == " " || first == "\n" || first == "\t" { slice = slice.dropFirst() }
    while let last = slice.last, last == " " || last == "\n" || last == "\t" { slice = slice.dropLast() }
    return String(slice)
  }

  func replacingOccurrences(of target: Character, with replacement: Character) -> String {
    String(map { $0 == target ? replacement : $0 })
  }
}

// MARK: UIColor construction and components

public extension UIColor {
  init(_ color: Color) { self.init(css: color.cssValue) }
  init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    // CSS clamps a channel to 0...255 anyway; clamping first keeps a component from data (NaN, 1e10) from trapping Int().
    func channel(_ value: CGFloat) -> Int { value.isNaN ? 0 : Int((min(max(value, 0), 1) * 255).rounded()) }
    let opacity = alpha.isNaN ? 0 : min(max(alpha, 0), 1)
    self.init(css: "rgba(\(channel(red)), \(channel(green)), \(channel(blue)), \(opacity))")
  }
  init(white: CGFloat, alpha: CGFloat) { self.init(red: white, green: white, blue: white, alpha: alpha) }

  static let label = UIColor(css: "light-dark(#000000, #FFFFFF)")
  static let secondaryLabel = UIColor(css: "light-dark(rgb(60 60 67 / 0.6), rgb(235 235 245 / 0.6))")
  static let tertiaryLabel = UIColor(css: "light-dark(rgb(60 60 67 / 0.3), rgb(235 235 245 / 0.3))")
  static let separator = UIColor(css: "light-dark(rgb(60 60 67 / 0.29), rgb(84 84 88 / 0.6))")
  static let clear = UIColor(css: "transparent")
  static let black = UIColor(css: "#000000")
  static let white = UIColor(css: "#FFFFFF")
  static let systemBlue = UIColor(css: "light-dark(#0088FF, #0091FF)")

  func getRed(_ red: UnsafeMutablePointer<CGFloat>?, green: UnsafeMutablePointer<CGFloat>?, blue: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) -> Bool {
    let value = _CSSColorComponents.parse(css)
    red?.pointee = value.red; green?.pointee = value.green; blue?.pointee = value.blue; alpha?.pointee = value.alpha
    return true
  }
}

public extension Color {
  @_disfavoredOverload init(_ uiColor: UIColor) { self.init(css: uiColor.css) }
}
