import Foundation
import Testing

/// The C math functions, `String(format:)` conversions and `NotificationCenter.notifications(named:object:)`. Reference
/// values are the C library's (checked with arbitrary-precision arithmetic for the transcendental functions).
@Suite struct FoundationMathFormatTests {
  private func close(_ actual: Double, _ expected: Double, tolerance: Double = 1e-10) -> Bool {
    abs(actual - expected) <= tolerance
  }

  @Test func trigonometryOfKnownAngles() {
    #expect(close(_cmathSin(Double.pi / 6), 0.5))
    #expect(close(_cmathCos(Double.pi / 3), 0.5))
    #expect(close(_cmathTan(Double.pi / 4), 1))
    #expect(_cmathSin(0.0) == 0)
    #expect(_cmathCos(0.0) == 1)
    #expect(close(_cmathSin(Double.pi), 0))
    #expect(close(_cmathCos(Double.pi), -1))
    #expect(close(_cmathSin(-Double.pi / 2), -1))
    #expect(_cmathSin(-0.0).sign == .minus)
  }

  @Test func trigonometryOfLargeAndNegativeArguments() {
    #expect(close(_cmathSin(1_000_000), -0.34999350217129295211765248678077146906140660532871))
    #expect(close(_cmathCos(1_000_000), 0.93675212753314478693853253507491877570809780421236))
    #expect(close(_cmathSin(-12_345.678), 0.70408131375329891664088601883988489671293898322425))
    #expect(close(_cmathCos(-12_345.678), 0.71011935871614473950144892333424568426948350433808))
    #expect(close(_cmathTan(1_000), 1.47032415570271844598020880490391856915748389146711))
    #expect(close(_cmathTan(0.7), 0.84228838046307944812813500221293771718722125080419))
    #expect(close(_cmathSin(0.7), 0.64421768723769105367261435139872018306581384457368))
  }

  @Test func inverseTrigonometry() {
    #expect(close(_cmathAtan(3.5), 1.29249666778978526790309142140708168458531408411200))
    #expect(close(_cmathAsin(0.3), 0.30469265401539750797200296122752916695456003170677))
    #expect(close(_cmathAcos(-0.6), 2.21429743558818100603413092035707408014009529080285))
    #expect(close(_cmathAcos(1), 0))
    #expect(close(_cmathAcos(-1), Double.pi))
    #expect(close(_cmathAsin(1), Double.pi / 2))
    #expect(close(_cmathAtan2(-3, -4), -2.49809154479650885165983415456218024615565880825977))
    #expect(close(_cmathAtan2(5, -2), 1.95130270390726150553490960845018454659599041334563))
    #expect(close(_cmathAtan2(1, 0), Double.pi / 2))
    #expect(_cmathAtan2(0, -1) == Double.pi)
    #expect(_cmathAtan2(-0.0, 1).sign == .minus)
    #expect(close(_cmathAtan2(.infinity, -.infinity), 3 * Double.pi / 4))
    #expect(_cmathAsin(2).isNaN)
    #expect(_cmathAcos(-2).isNaN)
  }

  @Test func hyperbolicFunctions() {
    #expect(close(_cmathSinh(2), 3.62686040784701876766821398280126170488634201232113))
    #expect(close(_cmathCosh(-1.5), 2.35240961524324732576766796544164417017396074886536))
    #expect(close(_cmathTanh(0.3), 0.29131261245159090581822127282376592815359680491761))
    #expect(_cmathTanh(.infinity) == 1)
    #expect(_cmathTanh(-50) == -1)
    #expect(_cmathSinh(.infinity) == .infinity)
    #expect(_cmathCosh(0) == 1)
  }

  @Test func logarithmsAndPowersOfTwo() {
    #expect(close(_cmathLog2(360 / 7), 5.68449817427207060333582800015319238474343358244344))
    #expect(close(_cmathLog10(12_345), 4.09149109426795108184899676513017393756105641376818))
    #expect(_cmathLog2(1024) == 10)
    #expect(_cmathLog2(0.25) == -2)
    #expect(close(_cmathLog10(1_000), 3))
    #expect(_cmathLog2(0) == -.infinity)
    #expect(_cmathLog10(-1).isNaN)
    #expect(_cmathExp2(10) == 1024)
    #expect(_cmathExp2(-1074) == Double.leastNonzeroMagnitude)
    #expect(close(_cmathExp2(0.5), 1.41421356237309504880168872420969807856967187537693))
    #expect(close(_cmathExp2(-10.25), 0.00082118790552120560842883347288399892093753345933, tolerance: 1e-15))
    #expect(_cmathExp2(.infinity) == .infinity)
  }

  @Test func rootsAndDistances() {
    #expect(close(_cmathCbrt(10), 2.15443469003188372175929356651935049525934494219209))
    #expect(_cmathCbrt(-27) == -3)
    #expect(_cmathCbrt(8) == 2)
    #expect(_cmathHypot(3, 4) == 5)
    #expect(close(_cmathHypot(1e200, 1e200) / 1e200, 1.41421356237309504880168872420969807856967187537693, tolerance: 1e-15))
    #expect(_cmathHypot(.infinity, .nan) == .infinity)
    #expect(_cmathHypot(0, 0) == 0)
  }

  @Test func remainderAndExtrema() {
    #expect(_cmathFmod(10.5, 3) == 1.5)
    #expect(_cmathFmod(-7, 2.5) == -2)
    #expect(_cmathFmod(7, -2.5) == 2)
    #expect(_cmathFmod(1e15 + 3, 7) == 2)
    #expect(_cmathFmod(5, 0).isNaN)
    #expect(_cmathFmod(.infinity, 2).isNaN)
    #expect(_cmathFmod(3, .infinity) == 3)
    #expect(_cmathFmin(.nan, 2) == 2)
    #expect(_cmathFmin(1, .nan) == 1)
    #expect(_cmathFmin(-3, 4) == -3)
    #expect(_cmathFmax(.nan, 2) == 2)
    #expect(_cmathFmax(1, 9) == 9)
  }

  @Test func singlePrecisionIsTheDoubleResultRoundedToFloat() {
    // The Float overloads (Embedded only) round the Double result; the Double implementation is checked here.
    let sine = Float(_cmathSin(0.5))
    #expect(abs(sine - 0.47942554) < 1e-7)
    #expect(_cmathHypot(3, 4) == 5)
  }

  // MARK: printf conversions

  private func format(_ template: String, _ arguments: any _PrintfArgument...) -> String {
    _formatPrintf(template, arguments.map { $0._printfValue })
  }

  @Test func floatingPointRoundsHalfToEvenOnTheExactValue() {
    #expect(format("%.1f", 0.25 as Double) == "0.2")
    #expect(format("%.2f", 0.125 as Double) == "0.12")
    #expect(format("%.2f", 2.675 as Double) == "2.67")
    #expect(format("%.2f", 0.005 as Double) == "0.01")
    #expect(format("%.0f", 2.5 as Double) == "2")
    #expect(format("%.0f", 3.5 as Double) == "4")
    #expect(format("%.10f", 1.0 / 3.0 as Double) == "0.3333333333")
    #expect(format("%.2f", 1e-7 as Double) == "0.00")
    #expect(format("%.2f", -0.0 as Double) == "-0.00")
    #expect(format("%f", 1e20 as Double) == "100000000000000000000.000000")
  }

  @Test func widthsFlagsAndZeroPadding() {
    #expect(format("%5.1f|", 3.14159 as Double) == "  3.1|")
    #expect(format("%-8.3f|", -1.5 as Double) == "-1.500  |")
    #expect(format("%08.2f", -3.14159 as Double) == "-0003.14")
    #expect(format("%+.1f", 2.0 as Double) == "+2.0")
    #expect(format("% .1f", 2.0 as Double) == " 2.0")
    #expect(format("%+d", 5 as Int) == "+5")
    #expect(format("% d", 5 as Int) == " 5")
    #expect(format("%05d", -42 as Int) == "-0042")
    #expect(format("%.3d", 7 as Int) == "007")
    #expect(format("%-4d|", 7 as Int) == "7   |")
    #expect(format("%d", Int64.min) == "-9223372036854775808")
  }

  @Test func integersInEveryRadix() {
    #expect(format("%d %i", 42 as Int, -7 as Int) == "42 -7")
    #expect(format("%x", 255 as Int) == "ff")
    #expect(format("%x", -1 as Int) == "ffffffff", "a negative value is its 32-bit pattern in a plain %x")
    #expect(format("%lx", -1 as Int) == "ffffffffffffffff")
    #expect(format("%hhx", -1 as Int) == "ff")
    #expect(format("%X", -255 as Int) == "FFFFFF01")
    #expect(format("%X", 255 as Int) == "FF")
    #expect(format("%#x", 255 as Int) == "0xff")
    #expect(format("%08x", 255 as Int) == "000000ff")
    #expect(format("%o", 8 as Int) == "10")
    #expect(format("%#o", 8 as Int) == "010")
    #expect(format("%u", UInt64.max) == "18446744073709551615")
    #expect(format("%.0d", 0 as Int) == "")
  }

  @Test func exponentialAndGeneralNotation() {
    #expect(format("%e", 12_345.678 as Double) == "1.234568e+04")
    #expect(format("%.3e", 0.000123456 as Double) == "1.235e-04")
    #expect(format("%E", 1e-10 as Double) == "1.000000E-10")
    #expect(format("%e", 0 as Double) == "0.000000e+00")
    #expect(format("%g", 0.0001 as Double) == "0.0001")
    #expect(format("%g", 1e-5 as Double) == "1e-05")
    #expect(format("%g", 123_456_789 as Double) == "1.23457e+08")
    #expect(format("%g", 100_000 as Double) == "100000")
    #expect(format("%g", 1_000_000 as Double) == "1e+06")
    #expect(format("%.3g", 3.14159 as Double) == "3.14")
    #expect(format("%#g", 1.0 as Double) == "1.00000")
    #expect(format("%g", 0 as Double) == "0")
    #expect(format("%.15g", 0.1 as Double) == "0.1")
    #expect(format("%.17g", 0.1 as Double) == "0.10000000000000001")
  }

  @Test func nonFiniteValues() {
    #expect(format("%f", Double.nan) == "nan")
    #expect(format("%F", Double.infinity) == "INF")
    #expect(format("%f", -Double.infinity) == "-inf")
  }

  @Test func textCharactersAndPercentSigns() {
    #expect(format("%c", 65 as Int) == "A")
    #expect(format("%s", "abc") == "abc")
    #expect(format("%5s|", "ab") == "   ab|")
    #expect(format("%-5s|", "ab") == "ab   |")
    #expect(format("%.2s", "abcdef") == "ab")
    #expect(format("%@", "x") == "x")
    #expect(format("%%") == "%")
    #expect(format("100%%") == "100%")
  }

  @Test func stringFormatKeepsFlagsAtEveryArity() {
    // The sparkline's change pill: `+` and `%%` must reach the output at one argument, not only at five or more.
    #expect(String(format: "%+.2f%%", 22.51 as Double) == "+22.51%")
    #expect(String(format: "%+.2f%%", -3.5 as Double) == "-3.50%")
    #expect(String(format: "$%.2f", 1234.5 as Double) == "$1234.50")
    #expect(String(format: "%+d %+d", 1 as Int, -2 as Int) == "+1 -2")
    #expect(String(format: "%-4d|%04d", 7 as Int, 42 as Int) == "7   |0042")
    #expect(String(format: "%x %X %o", 255 as Int, 255 as Int, 8 as Int) == "ff FF 10")
    #expect(String(format: "%e|%c|%#x", 1.5 as Double, 66 as Int, 16 as Int) == "1.500000e+00|B|0x10")
    #expect(String(format: "%@ %d %.1f %s", "a", 2 as Int, 3.25 as Double, "b") == "a 2 3.2 b")
    #expect(String(format: "%+d %+d %+d %+d %+d", 1 as Int, 2 as Int, 3 as Int, 4 as Int, 5 as Int) == "+1 +2 +3 +4 +5")
    #expect(
      String(format: "%+d%d%d%d%d%d%d%d%d%+d", 1 as Int, 2 as Int, 3 as Int, 4 as Int, 5 as Int, 6 as Int, 7 as Int,
             8 as Int, 9 as Int, 10 as Int) == "+123456789+10"
    )
    #expect(
      String(format: "%+.1f %+.1f %+.1f %+.1f %+.1f %+.1f", 1 as Double, -2 as Double, 3 as Double, 4 as Double,
             5 as Double, 6 as Double) == "+1.0 -2.0 +3.0 +4.0 +5.0 +6.0"
    )
  }

  @Test func positionsStarsAndMixedSequences() {
    #expect(format("%2$@ %1$@", "a", "b") == "b a")
    #expect(format("%*d", 5 as Int, 42 as Int) == "   42")
    #expect(format("%.*f", 2 as Int, 3.14159 as Double) == "3.14")
    #expect(format("%.1f %.2f %d %@ %x", 1.5 as Double, 0.33 as Double, 7 as Int, "hi", 255 as Int) == "1.5 0.33 7 hi ff")
    #expect(format("%{") == "%{")
  }

  @Test func rectangleJSONTemplateFromTheDemo() {
    let text = format(
      "{\"rotate\":%.1f,\"crop\":{\"x\":%.2f,\"y\":%.2f,\"width\":%.2f,\"height\":%.2f}}",
      90.0 as Double, 1.005 as Double, 0.5 as Double, 320.125 as Double, 240 as Double
    )
    #expect(text == "{\"rotate\":90.0,\"crop\":{\"x\":1.00,\"y\":0.50,\"width\":320.12,\"height\":240.00}}")
  }

  // MARK: NotificationCenter.notifications(named:object:)

  @Test func notificationsKeepWhatWasPostedBeforeTheIteration() async {
    let center = NotificationCenter()
    let name = Notification.Name("test.notifications.order")
    let sequence = center.notifications(named: name)
    center.post(name: name, object: nil)
    center.post(name: Notification.Name("test.notifications.other"), object: nil)
    center.post(name: name, object: nil)
    var iterator = sequence.makeAsyncIterator()
    #expect(await iterator.next()?.name == name)
    #expect(await iterator.next()?.name == name)
  }

  @Test func notificationsFromOneSenderOnly() async {
    let center = NotificationCenter()
    let name = Notification.Name("test.notifications.sender")
    let sender = NotificationTestSender()
    let other = NotificationTestSender()
    let sequence = center.notifications(named: name, object: sender)
    center._post(name: name, sender: other)
    center._post(name: name, sender: sender)
    var iterator = sequence.makeAsyncIterator()
    #expect(await iterator.next() != nil)
    // Only the sender's notification was kept, so a second wait ends only when the task is cancelled.
    let waiting = Task { () -> Notification? in
      var second = sequence.makeAsyncIterator()
      return await second.next()
    }
    waiting.cancel()
    #expect(await waiting.value == nil)
  }

  @Test func cancellingTheTaskEndsTheIterationAndDropsLaterNotifications() async {
    let center = NotificationCenter()
    let name = Notification.Name("test.notifications.cancel")
    let sequence = center.notifications(named: name)
    let waiting = Task { () -> Notification? in
      var iterator = sequence.makeAsyncIterator()
      return await iterator.next()
    }
    waiting.cancel()
    #expect(await waiting.value == nil)
    center.post(name: name, object: nil)
    var later = sequence.makeAsyncIterator()
    #expect(await later.next() == nil)
  }

  /// Native hosts post, iterate and cancel from different threads: a delivery racing a cancellation must resume the waiting
  /// iteration once (a second resume traps) and never leave it suspended.
  @Test func postingWhileIteratorsAreCancelledResumesEachOnce() async {
    let center = NotificationCenter()
    let name = Notification.Name("test.notifications.race")
    for _ in 0..<200 {
      let sequence = center.notifications(named: name)
      let waiting = Task { () -> Int in
        var iterator = sequence.makeAsyncIterator()
        var taken = 0
        while await iterator.next() != nil { taken += 1 }
        return taken
      }
      let poster = Task.detached {
        for _ in 0..<20 { center.post(name: name, object: nil) }
      }
      waiting.cancel()
      await poster.value
      _ = await waiting.value
    }
  }
}

/// A sender whose identity matters to `notifications(named:object:)`.
private final class NotificationTestSender: Sendable {}
