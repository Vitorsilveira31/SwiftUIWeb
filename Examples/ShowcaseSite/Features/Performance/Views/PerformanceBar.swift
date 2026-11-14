import SwiftUIWeb

/// One side of one metric: its name and its number on one line, its bar under them. The name has the whole width to itself, so a
/// long one ("SwiftUIWeb (worker not throttled)") wraps on its own line instead of over the bar.
struct PerformanceBar: View {
  let name: String
  let share: Double
  let text: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(name).font(.caption).foregroundStyle(.secondary)
        Spacer(minLength: 8)
        Text(text).font(.callout).monospacedDigit()
      }
      ProgressView(value: share).tint(tint)
    }
  }
}
