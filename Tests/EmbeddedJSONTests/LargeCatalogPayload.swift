// A response shaped like a large catalog snapshot: a few hundred KB of nested objects, strings with escapes and non-ASCII
// text, integers and fractions. Used for the decode timing test.
enum LargeCatalogPayload {
  static func make(records: Int = 1_500) -> [UInt8] {
    var random = SplitMix64(state: 7)
    var json = "{\"items\":["
    for index in 0..<records {
      if index > 0 { json += "," }
      let price = Double(random.next() % 1_000_000) / 100
      json += "{\"id\":\(index),\"slug\":\"item-\(index)\",\"title\":\"Epis\\u00f3dio \(index) \\\"cut\\\" \u{65E5}\u{672C}\u{8A9E}\","
      json += "\"price\":\(price),\"ratio\":\(Double(random.next() % 1000) / 1000),\"active\":\(index % 3 == 0),\"parent\":null,"
      json += "\"tags\":[\"a\",\"b\",\"c\(index % 7)\"],\"meta\":{\"created\":\"2026-10-2\(index % 10)T10:00:00Z\",\"views\":\(random.next() % 100_000),\"notes\":[{\"k\":\"x\",\"v\":1.5e3},{\"k\":\"y\",\"v\":-2}]}}"
    }
    json += "],\"total\":\(records)}"
    return Array(json.utf8)
  }
}
