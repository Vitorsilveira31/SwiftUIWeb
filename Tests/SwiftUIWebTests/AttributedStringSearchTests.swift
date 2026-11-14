import Testing
@testable import SwiftUIWebFeatures

/// `AttributedString.range(of:)` finds the first, last or anchored match in linear time.
@Suite
struct AttributedStringSearchTests {
  private func offsets(_ range: Range<AttributedString.Index>?) -> [Int]? {
    range.map { [$0.lowerBound.offset, $0.upperBound.offset] }
  }

  @Test
  func searchFindsTheSameRangesLinearly() {
    let text = AttributedString("abcabcABC")
    #expect(offsets(text.range(of: "bc")) == [1, 3])
    #expect(offsets(text.range(of: "bc", options: .backwards)) == [4, 6])
    #expect(offsets(text.range(of: "BC", options: [.caseInsensitive, .backwards])) == [7, 9])
    #expect(offsets(text.range(of: "abc", options: .anchored)) == [0, 3])
    #expect(text.range(of: "bc", options: .anchored) == nil)
    #expect(offsets(text.range(of: "ABC", options: [.anchored, .backwards])) == [6, 9])
    #expect(text.range(of: "zz") == nil)
    // Quadratic for a search that compares at every start; linear here.
    let long = AttributedString(String(repeating: "a", count: 200_000) + "b")
    #expect(offsets(long.range(of: String(repeating: "a", count: 1_000) + "b")) == [199_000, 200_001])
  }
}
