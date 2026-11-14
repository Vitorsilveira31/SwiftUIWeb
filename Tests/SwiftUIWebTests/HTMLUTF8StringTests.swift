import Testing
@testable import SwiftUIWebHTML

/// `String(htmlUTF8:)` stands in for `String(decoding:as: UTF8.self)` in the serializer (it keeps the module's
/// serialization stable, Documentation/Performance/BUILD_TIME.md): it must give the same string for every input,
/// ill-formed UTF-8 included.
@Suite
struct HTMLUTF8StringTests {
  @Test(arguments: [
    [UInt8](),
    Array("<div class=\"a\">ção ✓ 🎉</div>".utf8),
    Array(repeating: UInt8(ascii: "x"), count: 15),
    Array(repeating: UInt8(ascii: "x"), count: 16),
    [0xFF, 0x41, 0xC3],
    [0x61, 0xE2, 0x82, 0x62, 0xF0, 0x9F, 0x98],
    [0xED, 0xA0, 0x80, 0x00, 0x7A],
  ])
  func decodesLikeStringDecoding(_ bytes: [UInt8]) {
    bytes.withUnsafeBufferPointer { buffer in
      #expect(String(htmlUTF8: buffer) == String(decoding: buffer, as: UTF8.self))
      #expect(Array(String(htmlUTF8: buffer).utf8) == Array(String(decoding: buffer, as: UTF8.self).utf8))
    }
  }

  @Test
  func decodesALargeSerializationLikeStringDecoding() {
    var bytes = Array("<p title=\"ção\">".utf8)
    for index in 0..<4096 { bytes.append(index % 997 == 0 ? 0xC3 : UInt8(ascii: "a") + UInt8(index % 26)) }
    bytes.withUnsafeBufferPointer { buffer in
      #expect(String(htmlUTF8: buffer) == String(decoding: buffer, as: UTF8.self))
    }
  }
}
