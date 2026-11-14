import SwiftUIWeb

/// A pill that slides to the chosen tab: the same view in a new place (`matchedGeometryEffect`).
struct MatchedGeometryDemo: View {
  @Namespace private var tabs
  @State private var selected = 0
  private static let names = ["Day", "Week", "Month"]

  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<Self.names.count, id: \.self) { index in
        Button(Self.names[index]) { withAnimation(.snappy) { selected = index } }
          .buttonStyle(.plain)
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .matchedGeometryEffect(id: index, in: tabs)
      }
    }
    .background(alignment: .center) {
      Capsule()
        .fill(SiteTheme.accent.opacity(0.25))
        .matchedGeometryEffect(id: selected, in: tabs, isSource: false)
    }
    .padding(4)
    .background(Capsule().fill(Color.primary.opacity(0.06)))
  }
}
