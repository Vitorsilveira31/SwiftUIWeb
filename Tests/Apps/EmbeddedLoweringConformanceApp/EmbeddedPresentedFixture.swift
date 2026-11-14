import SwiftUIWeb

/// A destination presented with `navigationDestination(isPresented:)` over a NavigationStack's root, which stays shown:
/// both are laid out in the stack's screen, the destination over the root. CSS layout must lay it out (`Tools/test-css-layout-fixtures-browser.mjs`).
struct EmbeddedPresentedFixture: View {
  let onDone: () -> Void
  @State private var presented = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      NavigationStack {
        VStack(alignment: .leading, spacing: 8) {
          Text("Root screen")
          Button("Present") { presented = true }
        }
        .navigationTitle("Stack")
        .navigationDestination(isPresented: $presented) {
          Text("Presented destination")
            .frame(width: 220, height: 80)
            .background(Color.blue.opacity(0.2))
        }
      }
      .frame(width: 360, height: 260)
    }
    .padding(16)
  }
}
