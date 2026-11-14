// Apple-shaped application source. Tools/test-cross-package-consumer.mjs lowers it the way the browser build does,
// then compiles the lowered result in a separate package that depends on SwiftUIWeb, the way an application does.
// Codable lowering is Embedded-only (its `Embedded*` decoder does not exist natively), so it is not in this fixture.
import Foundation
import SwiftUI

private struct TitleStyleKey: EnvironmentKey {
  static let defaultValue = "plain"
}

extension EnvironmentValues {
  var titleStyle: String {
    get { self[TitleStyleKey.self] }
    set { self[TitleStyleKey.self] = newValue }
  }
}

struct ContentView: View {
  @State private var count = 0

  var body: some View {
    VStack {
      Text("cross.greeting")
        .lineLimit(1)
        .environment(\.titleStyle, "bold")
      Text("Count \(count)")
    }
    .environment(\.lineLimit, 2)
    .environment(\.colorScheme, .dark)
    .environment(\.locale, Locale(identifier: "pt-BR"))
  }
}

/// A longer `.environment` chain with conditional and optional values: the shape that once produced "failed to produce
/// diagnostic for expression" after lowering.
struct StyledView: View {
  var isDark: Bool
  var timeZoneOffset: Int?

  var body: some View {
    Text("styled")
      .environment(\.titleStyle, isDark ? "bold" : "plain")
      .environment(\.colorScheme, isDark ? .dark : .light)
      .environment(\.timeZone, TimeZone(secondsFromGMT: timeZoneOffset ?? -10_800) ?? .current)
      .environment(\.lineLimit, timeZoneOffset == nil ? nil : 3)
      .environment(\.locale, Locale(identifier: isDark ? "en_US" : "pt-BR"))
      .environment(\.titleStyle, "chained")
  }
}

func fetchStatus(_ url: URL) async throws -> Int {
  let (_, response) = try await URLSession.shared.data(from: url)
  guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
  return http.statusCode
}
