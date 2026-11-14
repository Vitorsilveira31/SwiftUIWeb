import SwiftUI
import SwiftUIWebBrowser
import Foundation
import Charts
import AVFoundation

struct Record: Codable { var id: Int }
struct Wide: Codable { var id: Int64; var small: UInt8 }
struct Stamp: Codable { var at: Date }

enum Hostile {
  static let calendar = Calendar(identifier: .gregorian)
  static func day(_ seconds: Double) -> String { "\(calendar.component(.day, from: Date(timeIntervalSince1970: seconds)))" }
  static func decode<T: Decodable>(_ type: T.Type, _ json: String, dates: Bool = false) -> String {
    let decoder = JSONDecoder()
    if dates { decoder.dateDecodingStrategy = .secondsSince1970 }
    do { return "\(try decoder.decode(type, from: Data(json.utf8)))" } catch { return "error" }
  }
  /// Seeded mutations of JSON documents, parsed by JSONSerialization and JSONDecoder in the 32-bit build: every one is
  /// answered. Tests/SwiftUIWebTests/JSONFuzzTests.swift runs a wider generator natively.
  static func jsonFuzz() -> String {
    var state: UInt64 = 0x5EED_0002
    func next(_ bound: Int) -> Int {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Int(truncatingIfNeeded: (state >> 33) % UInt64(bound))
    }
    let seeds = ["{\"id\":3000000000,\"b\":[1.5,-2e300,null],\"c\":\"\\u00e9\\ud83d\\ude00\"}", "[{\"a\":1},{\"a\":-9223372036854775808}]", "{\"d\":{\"x\":18446744073709551615}}", "\"\\u0000\"", "[true,false,null,0.1e-400]"]
    let alphabet = Array("{}[]\",:0123456789-+.eE\\u tfn".utf8) + [0xFF, 0xC3, 0xED, 0xA0, 0x80, 0]
    var parsed = 0, refused = 0
    for _ in 0 ..< 3_000 {
      var bytes = Array(seeds[next(seeds.count)].utf8)
      for _ in 0 ..< 1 + next(4) {
        switch next(5) {
        case 0 where !bytes.isEmpty: bytes[next(bytes.count)] = alphabet[next(alphabet.count)]
        case 1: bytes.insert(alphabet[next(alphabet.count)], at: next(bytes.count + 1))
        case 2 where !bytes.isEmpty: bytes.removeLast(1 + next(bytes.count))
        case 3: bytes = Array(repeating: UInt8(ascii: "["), count: 1 + next(3_000)) + bytes
        default: bytes += Array("1e99999".utf8)
        }
      }
      if (try? JSONSerialization.jsonObject(with: Data(bytes))) != nil { parsed += 1 } else { refused += 1 }
      _ = try? JSONDecoder().decode([Record].self, from: Data(bytes))
      _ = try? JSONDecoder().decode(Wide.self, from: Data(bytes))
    }
    return "\(parsed + refused) answered"
  }

  static let cases: [(String, () -> String)] = [
    ("json-fuzz", { jsonFuzz() }),
    ("format-trailing-percent", { String.localizedStringWithFormat("Save 20%!", "x") }),
    ("format-huge-width", { "\(String(format: "%99999999999d", 1).count) \(String(format: "%.900000000f", 1.0).count)" }),
    ("regex-allowlist-lines", { "\((try? Regex("^[a-z]+$")).map { "ok\n<script>".contains($0) } ?? true)" }),
    ("regex-catastrophic", { "\((try? Regex("(a+)+$")).map { (String(repeating: "a", count: 40) + "!").firstMatch(of: $0) != nil } ?? true)" }),
    ("regex-nested-groups", { (try? Regex(String(repeating: "(", count: 5_000) + String(repeating: ")", count: 5_000))) == nil ? "refused" : "parsed" }),
    ("cmtime-huge", { "\(CMTime(seconds: 1e17, preferredTimescale: 600).value == Int64.max)" }),
    ("url-query-in-fragment", { "\(URL(string: "https://a.example/#x?next=evil")?.query ?? "nil")" }),
    ("url-components-authority", { var c = URLComponents(); c.scheme = "https"; c.host = "example.com"; c.path = "@evil.com"; return c.url?.absoluteString ?? "nil" }),
    ("uicolor-nan", { _ = UIColor(red: .nan, green: 2, blue: -1, alpha: 1e300); return "made" }),
    ("attributed-fold", { "\(AttributedString("İSTANBUL ﬁ straße").range(of: "stanbul", options: .caseInsensitive) != nil)" }),
    ("calendar-1e300", { day(1e300) }),
    ("calendar-inf", { day(.infinity) }),
    ("calendar-2038", { let c = calendar.dateComponents([.year, .month, .day, .hour], from: Date(timeIntervalSince1970: 3e9)); return "\(c.year ?? -1)-\(c.month ?? -1)-\(c.day ?? -1)" }),
    ("calendar-1e12", { day(1e12) }),
    ("calendar-add-days", { "\(calendar.date(byAdding: .day, value: Int.max, to: Date(timeIntervalSince1970: 0)).map { "\($0.timeIntervalSince1970)" } ?? "nil")" }),
    ("components-between", { "\(calendar.dateComponents([.day], from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 1e15)).day ?? -1)" }),
    ("relative-1e27", { RelativeDateTimeFormatter().localizedString(for: Date(timeIntervalSince1970: 1e27), relativeTo: Date(timeIntervalSince1970: 0)) }),
    ("relative-3e9", { RelativeDateTimeFormatter().localizedString(for: Date(timeIntervalSince1970: 3e9), relativeTo: Date(timeIntervalSince1970: 0)) }),
    ("date-format-3e9", { Date(timeIntervalSince1970: 3e9).formatted(date: .abbreviated, time: .shortened) }),
    ("date-format-1e300", { Date(timeIntervalSince1970: 1e300).formatted(date: .abbreviated, time: .shortened) }),
    ("iso-3e9", { Date(timeIntervalSince1970: 3e9).formatted(.iso8601) }),
    ("iso-1e300", { Date(timeIntervalSince1970: 1e300).formatted(.iso8601) }),
    ("compact-3e9", { (3e9).formatted(.number.notation(.compactName)) }),
    ("compact-1e31", { (1e31).formatted(.number.notation(.compactName)) }),
    ("compact-inf", { Double.infinity.formatted(.number.notation(.compactName)) }),
    ("number-3e9", { (3e9).formatted(.number) }),
    ("number-1e300", { (1e300).formatted(.number) }),
    ("percent-1e300", { (1e300).formatted(.percent) }),
    ("currency-1e300", { (1e300).formatted(.currency(code: "USD")) }),
    ("int64-max", { "\(Int64.max)" }),
    ("duration-1e12", { Duration.seconds(1e12).formatted(.units()) }),
    ("duration-int64-min", { Duration.seconds(Int64.min).formatted(.units()) }),
    ("distant-future-relative", { RelativeDateTimeFormatter().localizedString(for: .distantFuture, relativeTo: Date(timeIntervalSince1970: 0)) + " | " + "\(Date.distantFuture.timeIntervalSinceReferenceDate)" }),
    ("json-int-3e9", { decode(Record.self, "{\"id\":3000000000}") }),
    ("json-int-frac", { decode(Record.self, "{\"id\":1.9}") }),
    ("json-int-1e300", { decode(Record.self, "{\"id\":1e300}") }),
    ("json-int64-uint8", { decode(Wide.self, "{\"id\":9000000000000000000,\"small\":300}") }),
    ("json-date-1e300", { decode(Stamp.self, "{\"at\":1e300}", dates: true) }),
    ("json-date-then-calendar", { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970; guard let s = try? decoder.decode(Stamp.self, from: Data("{\"at\":1e300}".utf8)) else { return "error" }; return "\(calendar.component(.day, from: s.at))" }),
    ("json-deep", { decode(Record.self, String(repeating: "[", count: 100_000)) }),
    ("timezone", { "\(TimeZone(identifier: "GMT+99999999999")?.secondsFromGMT() ?? -1) \(TimeZone(identifier: "GMT+")?.secondsFromGMT() ?? -1)" }),
    ("markdown-brackets", { let start = Date(); _ = try? AttributedString(markdown: String(repeating: "[", count: 28) + "x" + String(repeating: "](", count: 28)); return "\(Date().timeIntervalSince(start))" }),
    ("json-serialization-3e9", { (try? JSONSerialization.jsonObject(with: Data("{\"id\":3000000000,\"big\":1e300}".utf8))).map { "\($0)" } ?? "error" }),
    ("regex-ignorecase-eszett", { "\((try? Regex("(?i)[a-z]+")).map { "straße".firstMatch(of: $0) != nil } ?? false)" }),
    ("regex-long-run", { "\((try? Regex("^a+b")).map { String(repeating: "a", count: 100_000).firstMatch(of: $0) != nil } ?? false)" }),
    ("regex-deep-group", { "\((try? Regex("(ab)+c")).map { (String(repeating: "ab", count: 50_000) + "c").firstMatch(of: $0) != nil } ?? false)" }),
    ("int64-number", { Int64(3_000_000_000).formatted(.number) }),
    ("duration-time", { Duration.seconds(259_205).formatted(.time(pattern: .minuteSecond)) + " " + Duration.milliseconds(-3_723_456).formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 2, fractionalSecondsLength: 3))) }),
    ("number-formatter-3e9", { NumberFormatter().string(from: NSNumber(value: 3_000_000_000.5)) ?? "nil" }),
    ("nsnumber-int-3e9", { "\(NSNumber(value: 3e9).intValue > 0) \(NSNumber(value: 1e300).intValue != 7)" }),
    ("measurement-3e9", { Measurement(value: 3e9, unit: UnitLength.meters).formatted() }),
    ("url-append-component", { URL(string: "https://api.example.test/users/")!.appendingPathComponent("42?role=admin#x").absoluteString }),
    ("string-format-1e17", { String(format: "%.2f", 1e17) }),
    ("calendar-add-month-far", { "\(calendar.date(byAdding: .month, value: 1, to: Date(timeIntervalSince1970: 1e16)).map { "\($0.timeIntervalSince1970)" } ?? "nil")" }),
    ("calendar-from-hours", { "\(calendar.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 1_000_000)).map { "\($0.timeIntervalSince1970)" } ?? "nil")" }),
    ("cookie-2040", { HTTPCookie(properties: [.name: "a", .value: "b", .domain: "", .path: "/", .expires: Date(timeIntervalSince1970: 2_200_000_000)]).map { HTTPCookieStorage.shared.setCookie($0); return "set" } ?? "nil" }),
    ("replacing-many-cr", { let start = Date(); _ = String(repeating: "\r", count: 100_000).replacingOccurrences(of: "\r\n", with: "\n"); return Date().timeIntervalSince(start) < 2 ? "fast" : "slow" }),
    ("url-host", { ["https://evil\\@ok.example/", "https://ok.example\\@evil.example/", "https:evil.example/x"].map { URL(string: $0)?.host ?? "nil" }.joined(separator: ",") }),
  ]
}

struct HostileValuesView: View {
  @State private var result = "idle"
  @State private var hugeDate: Date?
  @State private var hugeLayout = -1

  var body: some View {
    VStack(spacing: 4) {
      Text(result).accessibilityIdentifier("result")
      ForEach(0..<Hostile.cases.count, id: \.self) { index in
        Button(Hostile.cases[index].0) { result = "\(Hostile.cases[index].0): " + Hostile.cases[index].1() }
      }
      Button("text-date-styles") { hugeDate = Date(timeIntervalSince1970: 1e27); result = "text-date-styles: shown" }
      Button("text-timer-1e19") { hugeDate = Date(timeIntervalSince1970: 1e19); result = "text-timer-1e19: shown" }
      ForEach(0..<20, id: \.self) { item in
        Button("layout-\(item)") { hugeLayout = item; result = "layout-\(item): shown" }
      }
      if let hugeDate {
        Text(hugeDate, style: .relative)
        Text(hugeDate, style: .timer)
        Text(hugeDate, style: .offset)
        Text(hugeDate, style: .date)
        Text(timerInterval: Date(timeIntervalSince1970: 0)...hugeDate)
      }
      if hugeLayout == 0 { Text("wide").frame(width: 3e9, height: 3e9) }
      if hugeLayout == 1 { Text("off").offset(x: 3e9, y: -3e9) }
      if hugeLayout == 2 { Text("pad").padding(3e9) }
      if hugeLayout == 3 { ProgressView(value: 3e9, total: 1) }
      if hugeLayout == 4 { Color.red.frame(minWidth: 1e300, maxWidth: .infinity) }
      if hugeLayout == 5 { Text("op").opacity(1e300) }
      if hugeLayout == 6 { Text("rot").rotationEffect(.degrees(1e300)) }
      if hugeLayout == 7 { Text("scale").scaleEffect(1e300) }
      if hugeLayout == 8 { Text("\(1e17, specifier: "%.2f")") }
      if hugeLayout == 9 { Text("nan").foregroundStyle(.secondary.opacity(.nan)) }
      if hugeLayout == 10 { Text("font").font(.custom("Helvetica", size: 1e20)) }
      if hugeLayout == 11 { TimelineView(.periodic(from: Date(timeIntervalSince1970: 0), by: 1.0 / 60)) { context in Text("tick \(context.date.timeIntervalSince1970 > 0)") } }
      if hugeLayout == 12 { Text("pad2").padding(4e18).padding(5e18) }
      if hugeLayout == 13 { Chart { BarMark(x: .value("x", "a"), y: .value("y", 5e9)) }.chartYAxis { AxisMarks { value in AxisValueLabel { Text("\(value.as(Int.self) ?? 0)") } } }.frame(width: 200, height: 120) }
      if hugeLayout == 15 { MeshGradient(width: 70_000, height: 70_000, points: [], colors: []).frame(width: 40, height: 40) }
      if hugeLayout == 16 { Grid { GridRow { Text("a").gridCellColumns(Int.max); Text("b").gridCellColumns(2) } } }
      if hugeLayout == 17 {
        Canvas { context, _ in
          context.fill(Path(CGRect(x: 0, y: 0, width: 500, height: 500)), with: .radialGradient(
            Gradient(colors: [.red, .blue]), startCenter: .zero, startRadius: 0,
            endCenter: CGPoint(x: 100, y: 0), endRadius: 100.000_000_1, options: .repeat))
        }.frame(width: 60, height: 60)
      }
      if hugeLayout == 18 { Text("spring").offset(x: 1).animation(.interpolatingSpring(mass: 1, stiffness: 100, damping: 5, initialVelocity: 1e300), value: hugeLayout) }
      if hugeLayout == 19 { Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: 1e9, y: 0)) }.strokedPath(StrokeStyle(lineWidth: 2, dash: [1e-300, 1e-300])).frame(width: 10, height: 10) }
      if hugeLayout == 14 { TabView { Text("a").tabItem { Text("A") }.badge("2000000000"); Text("b").tabItem { Text("B") }.badge("2000000000") }.tabViewStyle(.sidebarAdaptable) }
    }
  }
}

@main
struct HostileValuesApp: BrowserApp {
  var body: some Scene { WindowGroup { HostileValuesView() } }
}
