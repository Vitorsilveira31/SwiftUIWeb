import SwiftUIWeb

/// A ring drawn by trimming a circle, with the number that rolls beside it.
struct ProgressRingDemo: View {
  @State private var progress = 0.25

  var body: some View {
    VStack(spacing: 12) {
      ZStack {
        Circle().stroke(Color.primary.opacity(0.1), lineWidth: 12)
        Circle()
          .trim(from: 0, to: progress)
          .stroke(SiteTheme.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
          .rotationEffect(.degrees(-90))
        Text("\(Int(progress * 100))%")
          .font(.system(.title2, design: .rounded))
          .fontWeight(.bold)
          .contentTransition(.numericText(value: progress))
      }
      .frame(width: 104, height: 104)
      .animation(.easeInOut(duration: 0.9), value: progress)
      HStack(spacing: 8) {
        Button("25%") { progress = 0.25 }
        Button("60%") { progress = 0.6 }
        Button("100%") { progress = 1 }
      }
      .buttonStyle(.bordered)
    }
  }
}
