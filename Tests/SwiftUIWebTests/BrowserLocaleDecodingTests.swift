import Testing
@testable import SwiftUIWebBrowserIO

/// The browser's zone offset, zone name and week decoders, driven with the bytes the host writes (`Tools/BrowserIO/browser-io.mjs`
/// writes an offset as `u32` of its two's complement, so it must read back as a signed 32-bit count of seconds).
@Suite struct BrowserLocaleDecodingTests {
  private func reader(_ build: (inout IOWriter) -> Void) -> IOReader {
    var writer = IOWriter()
    build(&writer)
    return IOReader(bytes: writer.bytes)
  }

  @Test func offsetsReadBackAsSignedSecondsEastOfUTC() {
    var negative = reader { $0.u32(1); $0.u32(UInt32(bitPattern: -10_800)) }  // UTC-3, as Sao Paulo
    #expect(BrowserIntl._decodeLocalOffset(&negative) == -10_800)
    var positive = reader { $0.u32(1); $0.u32(3_600) }  // UTC+1, as Lisbon in summer
    #expect(BrowserIntl._decodeLocalOffset(&positive) == 3_600)
    var absent = reader { $0.u32(0) }
    #expect(BrowserIntl._decodeLocalOffset(&absent) == nil)
  }

  @Test func timeZoneIdentifierIsTheHostsName() {
    var lisbon = reader { $0.u32(1); $0.text("Europe/Lisbon") }
    #expect(BrowserIntl._decodeTimeZoneIdentifier(&lisbon) == "Europe/Lisbon")
    var absent = reader { $0.u32(0) }
    #expect(BrowserIntl._decodeTimeZoneIdentifier(&absent) == nil)
  }

  @Test func weekInfoTurnsIntlsMondayFirstNumberingIntoFoundations() {
    // Intl's firstDay: 1 is Monday and 7 is Sunday. Foundation's firstWeekday: 1 is Sunday and 7 is Saturday.
    var monday = reader { $0.u32(1); $0.u32(1); $0.u32(4) }
    let european = BrowserIntl._decodeWeekInfo(&monday)
    #expect(european?.firstWeekday == 2)
    #expect(european?.minimumDays == 4)
    var sunday = reader { $0.u32(1); $0.u32(7); $0.u32(1) }
    #expect(BrowserIntl._decodeWeekInfo(&sunday)?.firstWeekday == 1)
    var saturday = reader { $0.u32(1); $0.u32(6); $0.u32(1) }
    #expect(BrowserIntl._decodeWeekInfo(&saturday)?.firstWeekday == 7)
    // A minimal-days count outside 1...7 is not a week: it falls back to one day.
    var odd = reader { $0.u32(1); $0.u32(1); $0.u32(9) }
    #expect(BrowserIntl._decodeWeekInfo(&odd)?.minimumDays == 1)
    // A first day outside 1...7 and an absent answer are both nil, so the calendar keeps Sunday.
    var invalid = reader { $0.u32(1); $0.u32(0); $0.u32(1) }
    #expect(BrowserIntl._decodeWeekInfo(&invalid) == nil)
    var absent = reader { $0.u32(0) }
    #expect(BrowserIntl._decodeWeekInfo(&absent) == nil)
  }
}
