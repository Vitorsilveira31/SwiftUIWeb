import SwiftUIWeb
import SwiftUIWebWeb

/// A registered DOM component that exercises every `DOMViewRepresentable`
/// lifecycle step in the Embedded browser: mount, update on a state change,
/// a message round trip from the component to Swift, and dispose when the
/// host leaves the page. The component itself, `showcase-counter`, is
/// registered by Tools/showcase-host.js. Tools/test-embedded-showcase.mjs
/// drives it from the Advanced page.
struct ShowcaseDOMCounter: DOMViewRepresentable {
  let count: Int
  let onTap: () -> Void

  final class Coordinator {
    var onTap: () -> Void
    var dismantled = false

    init(onTap: @escaping () -> Void) {
      self.onTap = onTap
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onTap: onTap)
  }

  func makeDOMView(context: Context) -> DOMView {
    let domView = DOMView(component: "showcase-counter", state: String(count))
    let coordinator = context.coordinator
    domView.onMessage = { _ in coordinator.onTap() }
    return domView
  }

  func updateDOMView(_ domView: DOMView, context: Context) {
    context.coordinator.onTap = onTap
    domView.state = String(count)
  }

  static func dismantleDOMView(_ domView: DOMView, coordinator: Coordinator) {
    coordinator.dismantled = true
  }
}

/// Owns the DOM component's inputs: the Swift counter it displays and whether it is mounted.
struct ShowcaseDOMComponentDemo: View {
  @State private var taps = 0
  @State private var showsComponent = true

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Swift taps: \(taps)")
      Button(showsComponent ? "Remove DOM component" : "Mount DOM component") {
        showsComponent.toggle()
      }
      if showsComponent {
        ShowcaseDOMCounter(count: taps, onTap: { taps += 1 })
          .frame(height: 44)
      }
    }
  }
}
