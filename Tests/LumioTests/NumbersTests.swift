import Testing
@testable import Lumio

struct NumbersTests {
  @Test func smallCountsStayWhole() {
    #expect(Numbers.compact(0) == "0")
    #expect(Numbers.compact(999) == "999")
  }

  @Test func thousandsGetASeparatorAndTensOfThousandsAK() {
    #expect(Numbers.compact(1_284) == "1,284")
    #expect(Numbers.compact(1_004) == "1,004")
    #expect(Numbers.compact(12_400) == "12.4K")
  }

  @Test func millionsGetAnM() {
    #expect(Numbers.compact(1_300_000) == "1.3M")
  }
}
