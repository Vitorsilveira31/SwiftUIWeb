import SwiftUI
import SwiftUIWebBrowser
import Foundation

/// Every fixed surface, reachable from the view so the Embedded build keeps the code that the link needs.
enum ConsumerProbe {
  static func jsonSummary() -> String {
    let source = Data("{\"name\":\"sample\",\"count\":3,\"ratio\":0.5,\"tags\":[\"a\",true,null]}".utf8)
    guard let object = try? JSONSerialization.jsonObject(with: source) as? [String: Any] else { return "json: parse failed" }
    let name = object["name"] as? String ?? "?"
    let count = object["count"] as? Int ?? -1
    let ratio = object["ratio"] as? Double ?? -1
    let tags = object["tags"] as? [Any] ?? []
    let isNull = tags.last is NSNull
    let valid = JSONSerialization.isValidJSONObject(object)
    let written = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "?"
    let pretty = (try? JSONSerialization.data(withJSONObject: ["k": 1], options: [.prettyPrinted])).map { String(decoding: $0, as: UTF8.self) } ?? "?"
    return "json: \(name) \(count) \(ratio) \(isNull) \(valid) \(written) \(pretty)"
  }

  static func unitSummary() -> String {
    let weight = Measurement(value: 70.25, unit: UnitMass.kilograms)
    let rounded = weight.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0 ... 1))))
    let formatter = MeasurementFormatter()
    formatter.unitStyle = .medium
    formatter.numberFormatter.maximumFractionDigits = 1
    formatter.locale = Locale(identifier: "pt_BR")
    let text = formatter.string(from: weight)
    let converted = Measurement(value: 1_000, unit: UnitMass.grams).converted(to: .kilograms).value
    return "unit: \(rounded) | \(text) | \(converted) | \(Double(70.25).formatted())"
  }

  static func calendarSummary() -> String {
    let calendar = Calendar(identifier: .gregorian)
    return "calendar: \(calendar.weekdaySymbols.count) \(calendar.shortWeekdaySymbols.first ?? "") \(calendar.veryShortWeekdaySymbols.last ?? "") \(calendar.monthSymbols.first ?? "") \(calendar.shortMonthSymbols.last ?? "") \(calendar.firstWeekday)"
  }

  static func predicateSummary() -> String {
    let matches = NSPredicate(format: "SELF MATCHES %@", "[0-9]+").evaluate(with: "12345")
    let partial = NSPredicate(format: "SELF MATCHES %@", "[0-9]+").evaluate(with: "12a45")
    let like = NSPredicate(format: "SELF LIKE %@", "sam*").evaluate(with: "sample")
    let contains = NSPredicate(format: "SELF CONTAINS %@", "mp").evaluate(with: "sample")
    let wholeRegex = (try? Regex("[a-z]+")).map { "sample".wholeMatch(of: $0) != nil } ?? false
    return "predicate: \(matches) \(partial) \(like) \(contains) \(wholeRegex)"
  }

  @MainActor static func networkSummary() async -> String {
    let url = URL(string: "https://example.invalid/data")!
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    var result = "network:"
    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      result += " \(response.url?.absoluteString ?? "")"
    } catch {
      result += " failed"
    }
    _ = URLSession.shared.dataTask(with: url) { _, _, _ in }
    final class ProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {}
    var upload = URLRequest(url: url)
    upload.httpMethod = "POST"
    let body = Data("payload".utf8)
    let delegate = ProgressDelegate()
    if let (_, uploadResponse) = try? await URLSession.shared.upload(for: upload, from: body, delegate: delegate) {
      result += " upload \(uploadResponse.url?.absoluteString ?? "")"
    }
    if let (_, bodyResponse) = try? await URLSession.shared.data(for: upload, delegate: delegate) {
      result += " body \(bodyResponse.url?.absoluteString ?? "")"
    }
    let task = URLSession.shared.dataTask(with: url) { _, _, _ in }
    task.resume()
    task.cancel()
    return result
  }
}

struct ConsumerView: View {
  @State private var status = "idle"

  var body: some View {
    VStack(spacing: 8) {
      Circle().fill(Color.red).stroke(Color.blue, lineWidth: 1).frame(width: 40, height: 40)
      Text(status)
      Button("Run") {
        status = [
          ConsumerProbe.jsonSummary(),
          ConsumerProbe.unitSummary(),
          ConsumerProbe.calendarSummary(),
          ConsumerProbe.predicateSummary()
        ].joined(separator: "\n")
        Task { status += "\n" + (await ConsumerProbe.networkSummary()) }
      }
    }
  }
}

@main
struct ConsumerProbeApp: BrowserApp {
  var body: some View { WindowGroup { ConsumerView() } }
}
