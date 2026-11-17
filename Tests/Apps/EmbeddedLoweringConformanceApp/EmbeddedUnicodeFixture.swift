import SwiftUIWeb

// String's Unicode semantics as an app relies on them: canonical equivalence in `==`, hashing and ordering, grapheme
// clusters, and case mapping. The browser build answers the standard library's Unicode data from the browser
// (Sources/CSwiftUIWebBrowserIO/UnicodeData.c, Tools/BrowserIO/unicode-data.mjs); the lines must read as Apple's Swift
// prints them (`Tools/test-embedded-lowering-runtime.mjs`).
struct EmbeddedUnicodeFixtureView: View {
  var body: some View {
    VStack {
      ForEach(EmbeddedUnicodeFixtureView.lines, id: \.self) { line in
        Text(line)
      }
    }
  }

  private static func scalarsText(_ text: String) -> String { text.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " ") }

  static var lines: [String] {
    let precomposed = "\u{E9}", combining = "e\u{301}"
    let equality = [
      precomposed == combining,
      "s\u{323}\u{307}" == "s\u{307}\u{323}",
      "\u{1E69}" == "s\u{323}\u{307}",
      "\u{AC00}" == "\u{1100}\u{1161}",
      "\u{212B}" == "\u{C5}",
      "e" == precomposed,
      "\u{1E9B}\u{323}" == "\u{17F}\u{323}\u{307}",
    ]
    let hashed = Set([precomposed, combining, "\u{1100}\u{1161}", "\u{AC00}"]).count
    let lookup = ["caf\u{E9}": 1]["cafe\u{301}"] ?? 0
    let order = [combining < "f", "\u{E0}" < "a\u{301}", "\u{1100}\u{1161}" < "\u{AC01}", "Z" < "a"]
    let counts = [
      combining.count, "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}".count, "\u{1F1E7}\u{1F1F7}\u{1F1FA}\u{1F1F8}".count,
      "\u{915}\u{94D}\u{937}\u{93F}".count, "\r\n".count, "\u{AC00}\u{11A8}".count, "\u{600}1".count,
      "\u{915}\u{93E}".count, "a\u{1F3FB}".count, "\u{1F44B}\u{1F3FD}".count, "\u{7}\u{301}".count,
      "\u{E0067}\u{E0062}".count, "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}".count,
    ]
    let characters = Array("ne\u{301}\u{1F44D}\u{1F3FB}x").map { Self.scalarsText(String($0)) }.joined(separator: ",")
    let cases = [
      "stra\u{DF}e".uppercased(), "\u{130}".lowercased(), "\u{1F80}".uppercased(), "\u{3A3}\u{39F}\u{3A3}".lowercased(),
      "\u{FB01}".uppercased(), "\u{10D0}".uppercased(), "\u{149}".uppercased(),
    ].map(Self.scalarsText).joined(separator: ",")
    let titles = ["\u{DF}", "\u{1C6}", "\u{1FB3}", "\u{149}", "\u{10D0}", "\u{FB01}", "\u{1FB7}", "a"].map {
      Self.scalarsText($0.unicodeScalars.first!.properties.titlecaseMapping)
    }.joined(separator: ",")
    let normalized = [
      String("\u{1E69}".unicodeScalars.first!.properties.canonicalCombiningClass.rawValue),
      String("\u{301}".unicodeScalars.first!.properties.canonicalCombiningClass.rawValue),
      String("\u{345}".unicodeScalars.first!.properties.canonicalCombiningClass.rawValue),
      String("\u{F73}".unicodeScalars.first!.properties.canonicalCombiningClass.rawValue),
    ].joined(separator: " ")
    return [
      "unicode equality: " + equality.map { $0 ? "1" : "0" }.joined(),
      "unicode hashing: \(hashed) \(lookup)",
      "unicode order: " + order.map { $0 ? "1" : "0" }.joined(),
      "unicode counts: " + counts.map(String.init).joined(separator: " "),
      "unicode characters: " + characters,
      "unicode case: " + cases,
      "unicode titlecase: " + titles,
      "unicode combining classes: " + normalized,
    ]
  }
}
