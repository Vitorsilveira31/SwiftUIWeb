import Testing
@testable import Mailo

struct MailTimeTests {
  @Test func aMessageOfYesterdayAndOfEarlierDaysHasADate() {
    #expect(MailTime.label(for: 5) == "Yesterday")
    #expect(MailTime.label(for: 1) == "Oct 26")
    #expect(MailTime.label(for: 4) == "Oct 17")
  }

  @Test func aMessageOfTodayHasItsTime() {
    #expect(MailTime.label(for: 14) == "16:26")
    #expect(MailTime.label(for: 0) == "00:00")
  }

  @Test func theSameIdAlwaysGivesTheSameTime() {
    #expect(MailTime.label(for: 37) == MailTime.label(for: 37))
  }
}
