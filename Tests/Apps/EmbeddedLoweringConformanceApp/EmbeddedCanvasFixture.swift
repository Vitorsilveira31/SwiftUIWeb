import SwiftUIWeb

/// Browser fixture for Canvas sizing. Each canvas paints its whole bounds, so Tools/test-canvas-browser.mjs can
/// check the resolved box, the backing store and the drawn pixels through the Embedded Swift + CSS layout +
/// JavaScript host path.
struct EmbeddedCanvasFixture: View {
  let onExit: @MainActor () -> Void
  @State private var subtreeIsDark = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button("Return to conformance app", action: onExit)
      VStack(alignment: .leading, spacing: 8) {
        Text("Framed height")
        Canvas { context, size in
          var fill = Path()
          fill.addRect(CGRect(origin: .zero, size: size))
          context.fill(fill, with: .color(.red))
        }
        .frame(height: 120)
        Text("Framed width and height")
        Canvas { context, size in
          var fill = Path()
          fill.addRect(CGRect(origin: .zero, size: size))
          context.fill(fill, with: .color(.green))
        }
        .frame(width: 200, height: 80)
        Text("Unframed")
        Canvas { context, size in
          var fill = Path()
          fill.addRect(CGRect(origin: .zero, size: size))
          context.fill(fill, with: .color(.blue))
        }
      }
      // A canvas whose subtree takes its own color scheme: its adaptive colors follow that scheme, not the page's.
      Text("Subtree scheme")
      Canvas { context, size in
        var fill = Path()
        fill.addRect(CGRect(origin: .zero, size: size))
        context.fill(fill, with: .color(.red))
      }
      .frame(height: 40)
      .environment(\.colorScheme, subtreeIsDark ? .dark : .light)
      Button("Toggle subtree scheme") { subtreeIsDark.toggle() }
      // Other greedy leaves at a frame owner boundary take the frame's height and the offered width.
      Text("Greedy leaves")
      Rectangle().fill(.purple).frame(height: 40).accessibilityIdentifier("canvas-fixture-rectangle")
      Color.orange.frame(height: 40).accessibilityIdentifier("canvas-fixture-color")
      GeometryReader { proxy in
        Text("Reader width \(Int(proxy.size.width))")
      }
      .frame(height: 40)
      .accessibilityIdentifier("canvas-fixture-reader")
    }
  }
}
