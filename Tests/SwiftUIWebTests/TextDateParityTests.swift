import Testing
import Foundation
@testable import SwiftUIWeb
@testable import SwiftUIWebInternationalization
import SwiftUIWebHTML

/// SwiftUI's date-bearing `Text` initializers: the Swift value is the static
/// fallback and the metadata lets the browser host localize and tick them.
@Suite
@MainActor
struct TextDateParityTests {
  private func html<V: View>(_ view: V) -> String { StaticHTMLFiberRenderer().render(view) }
  private let fixed = Date(timeIntervalSince1970: 1_800_000_000)

  @Test
  func dateStylesCarryTheirEpochAndLiveMarker() {
    let date = html(Text(fixed, style: .date))
    #expect(date.contains("data-text-date-style=\"date\""))
    #expect(date.contains("data-text-date-epoch=\"1800000000\""))
    #expect(date.contains("2027"))
    #expect(!date.contains("data-text-date-live"))
    let relative = html(Text(Date().addingTimeInterval(7_500), style: .relative))
    #expect(relative.contains("data-text-date-style=\"relative\""))
    #expect(relative.contains("data-text-date-live=\"true\""))
    #expect(relative.contains("2 hours, 4 minutes") || relative.contains("2 hours, 5 minutes"))
    #expect(html(Text(Date().addingTimeInterval(-90), style: .offset)).contains("-1 minute"))
    #expect(html(Text(Date().addingTimeInterval(-65), style: .timer)).contains("1:0"))
  }

  @Test
  func rangesAndTimerIntervalsUseSwiftUIShapes() {
    let range = html(Text(fixed...fixed.addingTimeInterval(5_400)))
    #expect(range.contains("data-text-date-kind=\"range\""))
    #expect(range.contains("data-text-date-end=\"1800005400\""))
    #expect(range.contains(" – "))
    let start = Date()
    let timer = html(Text(timerInterval: start...start.addingTimeInterval(600)))
    #expect(timer.contains("data-text-date-kind=\"timer-interval\""))
    #expect(timer.contains("data-text-date-live=\"true\""))
    #expect(timer.contains(">10:00<") || timer.contains(">9:59<"))
    let paused = html(Text(timerInterval: start...start.addingTimeInterval(3_700), pauseTime: start.addingTimeInterval(100), countsDown: false, showsHours: true))
    #expect(paused.contains(">1:40<"))
    #expect(paused.contains("data-text-date-pause="))
    #expect(!paused.contains("data-text-date-live"))
    #expect(html(Text(timerInterval: start...start.addingTimeInterval(3_700), pauseTime: start, showsHours: false)).contains(">61:40<"))
  }

  @Test
  func formatStylesComposeWithText() {
    let formatted = html(Text(fixed, format: .dateTime.year().month(.wide).day()))
    #expect(formatted.contains("2027"))
    #expect(formatted.contains("January"))
    #expect(!fixed.formatted(date: .abbreviated, time: .omitted).isEmpty)
  }

  @Test
  func durationTextsMatchSwiftUIStyles() {
    #expect(_DateDurationText.relative(seconds: 8_580) == "2 hours, 23 minutes")
    #expect(_DateDurationText.relative(seconds: -3_600) == "1 hour")
    #expect(_DateDurationText.relative(seconds: 0.4) == "0 seconds")
    #expect(_DateDurationText.offset(seconds: 7_300) == "+2 hours")
    #expect(_DateDurationText.offset(seconds: -45) == "-45 seconds")
    #expect(_DateDurationText.timer(seconds: 3_723, showsHours: true) == "1:02:03")
    #expect(_DateDurationText.timer(seconds: 3_723, showsHours: false) == "62:03")
    #expect(_DateDurationText.timer(seconds: 59, showsHours: true) == "0:59")
  }

  /// Intervals past 2^31 seconds (about 68 years) are counted in Int64: `Int` is 32 bits in the browser build, where
  /// these used to trap on a far date from the network. The browser side is checked by `make hostile-values-browser-test`.
  @Test
  func durationTextsCountPastThirtyTwoBits() {
    #expect(_DateDurationText.relative(seconds: 3e9) == "95 years, 1 month")
    #expect(_DateDurationText.offset(seconds: -3e9) == "-95 years")
    #expect(_DateDurationText.timer(seconds: 3e9, showsHours: true) == "833333:20:00")
    #expect(_DateDurationText.relative(seconds: 1e19) == "317097919837 years, 7 months")
    #expect(RelativeDateTimeFormatter().localizedString(for: Date(timeIntervalSince1970: 3e9), relativeTo: Date(timeIntervalSince1970: 0)) == "in 95 years")
    #expect(Duration.seconds(Int64.min).formatted(.units()) == "15250284452471w 3d 15h 30m 8s")
    #expect(Date.distantFuture.timeIntervalSinceReferenceDate == 63_113_904_000)
    #expect(Date.distantPast.timeIntervalSinceReferenceDate == -63_114_076_800)
    #expect(RelativeDateTimeFormatter().localizedString(for: .distantFuture, relativeTo: Date(timeIntervalSince1970: 0)) == "in 2032 years")
  }

  /// A whole number Int64 cannot hold is written as a plain number instead of trapping.
  @Test
  func hugeModifierValuesRenderWithoutTrapping() {
    let rendered = html(VStack {
      Text("a").opacity(1e300)
      Color.red.frame(minWidth: 1e300, maxWidth: .infinity)
      Text("b").frame(width: 3e9, height: 3e9)
      Text("c").offset(x: 1e300).padding(1e300)
    })
    #expect(rendered.contains("a"))
  }

  @Test
  func intlOptionsHaveDeterministicEnglishAndICUTemplates() {
    let options = _DateFormatOptions("weekday=long;year=numeric;month=short;day=numeric;hour=numeric;minute=2-digit")
    #expect(options.icuTemplate == "EEEEyMMMdjmm")
    #expect(options.englishText(for: fixed) == "Friday, Jan 15, 2027, 8:00 AM")
    #expect(_DateFormatOptions("year=numeric;month=numeric;day=2-digit").englishText(for: fixed) == "1/15/2027")
    #expect(_DateFormatOptions("hour=2-digit;minute=2-digit;hour12=false").englishText(for: fixed) == "08:00")
    #expect(_swiftUIWebEpochText(1.25) == "1.25")
    #expect(_swiftUIWebEpochText(-0.5) == "-0.5")
  }

  /// Int(Double) traps from 2^63 count units on (relative, offset) and from 2^63 seconds (timer). Such
  /// intervals render like a non-finite one instead of trapping.
  @Test
  func hugeIntervalsRenderWithoutTrapping() {
    #expect(_DateDurationText.relative(seconds: 1e27) == "")
    #expect(_DateDurationText.relative(seconds: -1e27) == "")
    #expect(_DateDurationText.offset(seconds: 1e27) == "")
    #expect(_DateDurationText.timer(seconds: 1e19, showsHours: true) == "0:00")
    #expect(_DateDurationText.timer(seconds: -1e19, showsHours: false) == "0:00")
    #expect(_DateDurationText.timer(seconds: 9e18, showsHours: true) == "2500000000000000:00:00")
    #expect(html(Text(Date(timeIntervalSince1970: 1e27), style: .relative)).contains("data-text-date-style=\"relative\""))
  }
}
