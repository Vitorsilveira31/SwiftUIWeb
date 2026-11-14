import SwiftUIWeb

/// `.position(x:y:)` centres its content on a point of the space it takes, offering the content that whole space (a long text
/// wraps at its width). CSS layout must lay it out (`Tools/test-css-layout-fixtures-browser.mjs`).
struct EmbeddedPlacementFixture: View {
  let onDone: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      ZStack {
        Color.gray.opacity(0.1)
        Text("Centre at 60, 30").position(x: 60, y: 30)
        Text("Edge").position(x: 300, y: 90)
        Color.blue.opacity(0.3).frame(width: 40, height: 40).position(x: 200, y: 50)
      }
      .frame(width: 360, height: 120)
      ZStack {
        Text("A long caption the position offers the whole width to, so it wraps there").position(x: 180, y: 40)
      }
      .frame(width: 360, height: 80)
    }
    .padding(16)
  }
}
