// The values whose encoded bytes are pinned by Fixtures/encode.txt (one output line per value, in this order).
struct SplitMix64 {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

enum EncodeCases {
  static func all() -> [EmbeddedJSONValue] {
    var cases: [EmbeddedJSONValue] = [.null, .bool(true), .bool(false), .array([]), .object([:])]
    var strings = ["", "plain", "quote\" back\\ slash/ tab\t nl\n cr\r bs\u{8} ff\u{C}", "caf\u{E9} \u{65E5}\u{672C}\u{8A9E} \u{1F600} e\u{301}", "\u{2028}\u{2029}\u{7F}\u{FFFF}", "</script> & <b>"]
    for scalar in 0..<32 { strings.append("a" + String(UnicodeScalar(UInt8(scalar))) + "b") }
    for string in strings { cases.append(.string(string)) }

    let numbers: [Double] = [
      0, -0.0, 1, -1, 42, 255, 65_535, 2_147_483_647, 2_147_483_648, -2_147_483_648, 4_294_967_296, 9_007_199_254_740_992,
      9_007_199_254_740_994, 1e15, 1e16, 1e17, 123_456_789_012_345_680, 9_223_372_036_854_774_784, -9_223_372_036_854_774_784,
      0.1, 0.5, 1.5, -1.5, 3.14159, 1.0 / 3, 2.0 / 3, 100.25, 1e-4, 1e-5, 1.5e-5, 1e-6, 1.5e-6, 1e-7, 1.5e-7, 1.234e-10,
      5e-324, 2.2250738585072014e-308, 4.5e15 + 0.5, 4_503_599_627_370_495.5, 1.0e-300, 0.30000000000000004,
    ]
    for number in numbers { cases.append(.number(number)) }
    var random = SplitMix64(state: 42)
    for _ in 0..<700 {
      let exponent = random.next() % 1086
      let bits = (random.next() & 1) << 63 | exponent << 52 | random.next() & 0xF_FFFF_FFFF_FFFF
      cases.append(.number(Double(bitPattern: bits)))
    }
    var scale = 1.0
    for index in 0..<13 {
      for _ in 0..<30 { cases.append(.number(Double(random.next() % 100_000_000) / scale)) }
      if index < 12 { scale *= 10 }
    }
    for _ in 0..<200 { cases.append(.number(Double(Int64(random.next() >> (2 + random.next() % 62))) * (random.next() & 1 == 0 ? 1 : -1))) }

    cases.append(.object(["b": .number(1), "a": .array([.number(2.5), .null, .string("x")]), "": .bool(true), "B": .object(["z": .null, "y": .object([:])])]))
    cases.append(.object(["z": .number(1), "\u{E9}": .number(2), "e\u{301}z": .number(3), "\u{1F600}": .number(4), "\u{FF5E}": .number(5), "a\"b": .number(6), "tab\t": .number(7), "Z": .number(8)]))
    cases.append(.array([.array([.array([.array([])])]), .object(["k": .array([.object([:])])])]))
    return cases
  }
}
