import SwiftUIWeb

/// Aspect boxes in a hugging stack, capped by the frame around them: SwiftUI proposes a frame's own height to what it holds, so
/// `.aspectRatio(2, .fit)` in `.frame(maxHeight: 80)` is 160 x 80 (Apple's `x-frame-max-hug`), a 0.5 box in it is 40 x 80, and with a
/// padding of 10 in between (`maxHeight: 120`) 50 x 100. The boxes CSS layout gives
/// are Apple's, and the blocks Swift sends must equal the page's analysis.
struct EmbeddedAspectFixture: View {
  let onDone: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      VStack(spacing: 8) {
        Text("Tiles")
        Color.green.aspectRatio(2, contentMode: .fit).frame(maxWidth: .infinity, maxHeight: 80)
        Color.orange.aspectRatio(0.5, contentMode: .fit).padding(10).frame(maxWidth: .infinity, maxHeight: 120)
        Color.blue.aspectRatio(2, contentMode: .fit).frame(maxWidth: .infinity)
      }
      .fixedSize(horizontal: false, vertical: true)
      .frame(width: 320)
    }
    .padding(16)
  }
}
