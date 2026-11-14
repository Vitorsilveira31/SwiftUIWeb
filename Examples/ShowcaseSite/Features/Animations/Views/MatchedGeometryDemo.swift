import SwiftUIWeb

/// A segmented control whose thumb slides to the chosen tab: the same view in a new place (`matchedGeometryEffect`).
struct MatchedGeometryDemo: View {
  @Namespace private var tabs
  @State private var selected = 0
  @Environment(\.colorScheme) private var colorScheme
  private static let names = ["Day", "Week", "Month"]

  var body: some View {
    HStack(spacing: 0) {
      ForEach(0..<Self.names.count, id: \.self) { index in
        Button(Self.names[index]) { withAnimation(.snappy) { selected = index } }
          .buttonStyle(.plain)
          .padding(.horizontal, 18)
          .padding(.vertical, 7)
          .matchedGeometryEffect(id: index, in: tabs)
      }
    }
    .background(alignment: .center) {
      // The thumb, as on iOS: white (a lighter gray in the dark) with a soft shadow. It takes the frame of the tab it is matched to.
      Capsule()
        .fill(colorScheme == .dark ? Color.white.opacity(0.22) : Color.white)
        .shadow(color: Color.black.opacity(0.16), radius: 3, x: 0, y: 1)
        .matchedGeometryEffect(id: selected, in: tabs, isSource: false)
    }
    .padding(3)
    .background(Capsule().fill(Color.primary.opacity(0.08)))
  }
}
