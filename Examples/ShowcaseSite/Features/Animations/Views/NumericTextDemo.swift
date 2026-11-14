import SwiftUIWeb

/// A counter whose digits roll to the new value (`ContentTransition.numericText`).
struct NumericTextDemo: View {
  @State private var count = 128

  var body: some View {
    VStack(spacing: 12) {
      Text("\(count)")
        .font(.system(size: 56, weight: .bold, design: .rounded))
        .foregroundStyle(SiteTheme.accent)
        .contentTransition(.numericText(value: Double(count)))
        .animation(.snappy, value: count)
      HStack(spacing: 8) {
        Button("−7") { count -= 7 }
        Button("+7") { count += 7 }
        Button("+100") { count += 100 }
      }
      .buttonStyle(.bordered)
    }
  }
}
