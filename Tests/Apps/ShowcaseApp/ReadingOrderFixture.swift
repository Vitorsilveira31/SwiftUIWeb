import SwiftUIWeb

/// Declaration-order fixture for `Tools/test-reading-order-browser.mjs`.
///
/// Every control carries an `accessibilityIdentifier` so the browser gate can
/// compare DOM order, Tab order, geometric order and accessibility-tree order
/// against the order written here. The route is intentionally not listed in the
/// Showcase sidebar; it is reached by path (`/readingOrder`) only.
struct ReadingOrderFixture: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      VStack(alignment: .leading, spacing: 8) {
        Text("Horizontal stack")
        HStack(spacing: 12) {
          Button("Alpha") {}.accessibilityIdentifier("order-h-alpha")
          Button("Beta") {}.accessibilityIdentifier("order-h-beta")
          Button("Gamma") {}.accessibilityIdentifier("order-h-gamma")
        }
      }
      VStack(alignment: .leading, spacing: 8) {
        Text("Vertical stack")
        VStack(alignment: .leading, spacing: 12) {
          Button("First") {}.accessibilityIdentifier("order-v-first")
          Button("Second") {}.accessibilityIdentifier("order-v-second")
          Button("Third") {}.accessibilityIdentifier("order-v-third")
        }
      }
      VStack(alignment: .leading, spacing: 8) {
        Text("Offset inside a vertical stack")
        VStack(alignment: .leading, spacing: 12) {
          Button("Offset leading") {}
            .offset(y: 60)
            .accessibilityIdentifier("order-offset-lead")
          Button("Offset trailing") {}.accessibilityIdentifier("order-offset-trail")
        }
      }
      VStack(alignment: .leading, spacing: 8) {
        Text("Overlay")
        Button("Primary action") {}
          .accessibilityIdentifier("order-overlay-base")
          .frame(width: 180, height: 44)
          .overlay(alignment: .topTrailing) {
            Button("Badge") {}.accessibilityIdentifier("order-overlay-badge")
          }
      }
      VStack(alignment: .leading, spacing: 8) {
        Text("ZStack layers")
        ZStack(alignment: .topLeading) {
          Button("Back layer") {}
            .accessibilityIdentifier("order-z-back")
            .frame(width: 180, height: 44)
          Button("Front layer") {}
            .accessibilityIdentifier("order-z-front")
            .frame(width: 180, height: 44)
        }
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
