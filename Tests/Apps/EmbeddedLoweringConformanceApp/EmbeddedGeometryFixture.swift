import SwiftUIWeb

/// Browser fixture for GeometryReader, onGeometryChange and coordinate
/// spaces, and for the geometry an `.animation(_:value:)` animates. Tools/test-geometry-browser.mjs
/// drives it through the real Embedded Swift + CSS layout + JavaScript host path.
struct EmbeddedGeometryFixture: View {
  let onExit: @MainActor () -> Void
  @State private var boxHeight = 40.0
  @State private var measuredHeight = 0.0
  @State private var heightChanges = 0
  @State private var measuredWidth = 0
  @State private var rowMinY = -1.0
  @State private var rowChanges = 0
  @State private var expanded = false
  @State private var extraWidth = 0.0
  @State private var showsMeasuredPanel = false

  var body: some View {
    VStack(spacing: 8) {
      Button("Return to conformance app", action: onExit)
      Button("Grow measured box") { boxHeight += 20 }
      Text("Measured height: \(Int(measuredHeight))")
      Text("Height changes: \(heightChanges)")
      Text("Measured width: \(measuredWidth)")
      Text("Row scrollView minY: \(Int(rowMinY))")
      Color.blue
        .frame(width: 120, height: boxHeight)
        .onGeometryChange(for: Double.self, of: { $0.size.height }) { height in
          measuredHeight = height
          heightChanges += 1
        }
      // Only a change of `expanded` animates; the other width changes below the same modifier snap.
      VStack(spacing: 2) {
        Color.orange.frame(height: 8)
        Color.purple.frame(width: 60, height: 8)
      }
      .frame(width: 100 + (expanded ? 120 : 0) + extraWidth)
      .animation(.linear(duration: 0.6), value: expanded)
      HStack {
        Button("Toggle animated value") { expanded.toggle() }
        Button("Widen without the animated value") { extraWidth += 40 }
      }
      Color.green
        .frame(maxWidth: .infinity)
        .frame(height: 10)
        .onGeometryChange(for: Int.self, of: { Int($0.size.width) }) { measuredWidth = $0 }
      ScrollView {
        VStack(spacing: 0) {
          GeometryReader { proxy in
            Text("Reader minY: \(Int(proxy.frame(in: .named("geometry-scroll")).minY))")
          }
          .frame(height: 40)
          Color.gray
            .frame(height: 30)
            .onGeometryChange(for: Double.self) { proxy in
              proxy.frame(in: .scrollView).minY
            } action: { _, newValue in
              rowMinY = newValue
              rowChanges += 1
            }
          ForEach(0..<40, id: \.self) { index in
            Text("Geometry row \(index)").frame(height: 24)
          }
        }
      }
      .coordinateSpace(name: "geometry-scroll")
      .frame(height: 200)
      Button("Toggle measured panel") { showsMeasuredPanel.toggle() }
        .sheet(isPresented: $showsMeasuredPanel) { EmbeddedMeasuredPanel() }
    }
  }
}

/// A panel sized from its measured content, as a dialog that hugs it, presented in a sheet: 600 points tall until the content
/// is measured. SwiftUI applies the measurement before the first frame shows the panel, so it is never seen at 600.
private struct EmbeddedMeasuredPanel: View {
  @State private var contentHeight: Double?

  var body: some View {
    VStack(spacing: 0) {
      Text("Measured panel content")
        .padding(10)
        .onGeometryChange(for: Double.self, of: { $0.size.height }) { contentHeight = $0 }
      Spacer(minLength: 0)
    }
    .frame(width: 200, height: contentHeight.map { $0 + 40 } ?? 600)
    .background(Color.yellow)
    .accessibilityIdentifier("measured-panel")
  }
}
