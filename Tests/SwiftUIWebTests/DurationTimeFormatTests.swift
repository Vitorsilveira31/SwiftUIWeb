import Testing
import Foundation
@testable import SwiftUIWeb

/// `Duration.formatted(.time(pattern:))` and `BinaryInteger.formatted(_:)` with a style of another integer type. The
/// expected strings are Foundation's own output for the same values (macOS 27, en_US), digit grouping included
/// ("4,320"), which the browser's `Intl.NumberFormat` and, natively, NativeNumberFormatting.swift write.
@Suite
struct DurationTimeFormatTests {
  private let en = Locale(identifier: "en_US")

  private func line(_ duration: Duration) -> String {
    let patterns: [(String, Duration.TimeFormatStyle.Pattern)] = [
      ("hm", .hourMinute), ("hms", .hourMinuteSecond), ("ms", .minuteSecond), ("hm2", .hourMinute(padHourToLength: 2)),
      ("hms2f3", .hourMinuteSecond(padHourToLength: 2, fractionalSecondsLength: 3)),
      ("ms3f2", .minuteSecond(padMinuteToLength: 3, fractionalSecondsLength: 2)),
      ("hmsDown", .hourMinuteSecond(padHourToLength: 1, fractionalSecondsLength: 1, roundFractionalSeconds: .down)),
      ("hmUp", .hourMinute(padHourToLength: 1, roundSeconds: .up)),
    ]
    return patterns.map { "\($0.0)=\(duration.formatted(Duration.TimeFormatStyle(pattern: $0.1, locale: en)))" }.joined(separator: " ")
  }

  @Test
  func timePatternsMatchFoundation() {
    #expect(line(.seconds(0)) == "hm=0:00 hms=0:00:00 ms=0:00 hm2=00:00 hms2f3=00:00:00.000 ms3f2=000:00.00 hmsDown=0:00:00.0 hmUp=0:00")
    #expect(line(.seconds(59)) == "hm=0:01 hms=0:00:59 ms=0:59 hm2=00:01 hms2f3=00:00:59.000 ms3f2=000:59.00 hmsDown=0:00:59.0 hmUp=0:01")
    #expect(line(.seconds(3723)) == "hm=1:02 hms=1:02:03 ms=62:03 hm2=01:02 hms2f3=01:02:03.000 ms3f2=062:03.00 hmsDown=1:02:03.0 hmUp=1:03")
    #expect(line(.milliseconds(3_723_456)) == "hm=1:02 hms=1:02:03 ms=62:03 hm2=01:02 hms2f3=01:02:03.456 ms3f2=062:03.46 hmsDown=1:02:03.4 hmUp=1:03")
    #expect(line(.milliseconds(-3_723_456)) == "hm=-1:02 hms=-1:02:03 ms=-62:03 hm2=-01:02 hms2f3=-01:02:03.456 ms3f2=-062:03.46 hmsDown=-1:02:03.5 hmUp=-1:02")
    #expect(line(.seconds(90)) == "hm=0:02 hms=0:01:30 ms=1:30 hm2=00:02 hms2f3=00:01:30.000 ms3f2=001:30.00 hmsDown=0:01:30.0 hmUp=0:02")
    #expect(line(.milliseconds(89_500)) == "hm=0:01 hms=0:01:30 ms=1:30 hm2=00:01 hms2f3=00:01:29.500 ms3f2=001:29.50 hmsDown=0:01:29.5 hmUp=0:02")
    #expect(line(.milliseconds(90_500)) == "hm=0:02 hms=0:01:30 ms=1:30 hm2=00:02 hms2f3=00:01:30.500 ms3f2=001:30.50 hmsDown=0:01:30.5 hmUp=0:02")
    #expect(line(.seconds(259_205)) == "hm=72:00 hms=72:00:05 ms=4,320:05 hm2=72:00 hms2f3=72:00:05.000 ms3f2=4,320:05.00 hmsDown=72:00:05.0 hmUp=72:01")
    #expect(line(.milliseconds(59_999)) == "hm=0:01 hms=0:01:00 ms=1:00 hm2=00:01 hms2f3=00:00:59.999 ms3f2=001:00.00 hmsDown=0:00:59.9 hmUp=0:01")
    #expect(line(.seconds(4_000_000_000)) == "hm=1,111,111:07 hms=1,111,111:06:40 ms=66,666,666:40 hm2=1,111,111:07 hms2f3=1,111,111:06:40.000 ms3f2=66,666,666:40.00 hmsDown=1,111,111:06:40.0 hmUp=1,111,111:07")
    #expect(Duration.seconds(3723).formatted(.time(pattern: .hourMinuteSecond)) == "1:02:03")
    // Ties are decided on the duration, in integers: a Double near 0.575 is below it and would round to 0.57.
    let twoDigits = Duration.TimeFormatStyle(pattern: .minuteSecond(padMinuteToLength: 1, fractionalSecondsLength: 2), locale: en)
    #expect(Duration.milliseconds(575).formatted(twoDigits) == "0:00.58")
    #expect(Duration.milliseconds(545).formatted(twoDigits) == "0:00.54")
    #expect(Duration.milliseconds(-575).formatted(twoDigits) == "-0:00.58")
    #expect(Duration.milliseconds(-4).formatted(twoDigits) == "0:00.00")
  }

  /// Foundation traps here (it converts the duration to a narrower integer); this answers.
  @Test
  func extremeDurationsFormat() {
    #expect(!Duration.seconds(Int64.max).formatted(.time(pattern: .hourMinuteSecond)).isEmpty)
    #expect(Duration.seconds(Int64.min).formatted(.time(pattern: .minuteSecond)).hasPrefix("-"))
  }

  @Test
  func integersFormatWithAStyleOfAnotherWidth() {
    // The same text as the value's own integer style.
    #expect(Int64(3_000_000_000).formatted(.number.locale(en)) == IntegerFormatStyle<Int64>(locale: en).format(3_000_000_000))
    #expect(Int8(-5).formatted(.number.locale(en)) == "-5")
    #expect(Int64(1234).formatted(.percent.locale(en)) == IntegerFormatStyle<Int64>.Percent(locale: en).format(1234))
    #expect(Int64(1234).formatted(.currency(code: "USD").locale(en)) == IntegerFormatStyle<Int64>.Currency(code: "USD", locale: en).format(1234))
    // Foundation traps converting this to Int; it is formatted whole instead.
    #expect(UInt64.max.formatted(.number.locale(en)) == IntegerFormatStyle<UInt64>(locale: en).format(.max))
    #expect(UInt64.max.formatted(.number.locale(en)) == "18,446,744,073,709,551,615")
  }
}
