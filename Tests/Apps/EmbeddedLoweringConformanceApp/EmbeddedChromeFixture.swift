import SwiftUIWeb
import SwiftUIWebAVFoundation
import SwiftUIWebAVKit

private func pushedPath() -> NavigationPath {
  var path = NavigationPath()
  path.append(1)
  return path
}

/// Chrome that a view requests of its surroundings:
/// - a `VideoPlayer` fills a flexible frame inside a `GeometryReader` and keeps its element across a resize;
/// - a pushed screen hides the system back button and the enclosing TabView's tab bar while it is on screen;
/// - a pushed screen with no request keeps both the back button and the tab bar;
/// - two `toolbar(_:for:)` modifiers on one screen merge, so both bars are hidden.
struct EmbeddedChromeFixture: View {
  let onDone: () -> Void
  @State private var selection = 0

  var body: some View {
    VStack {
      Button("Return to conformance app") { onDone() }
      TabView(selection: $selection) {
        Tab("Player", systemImage: "play.rectangle", value: 0) {
          GeometryReader { proxy in
            VStack {
              Text("Reader height: \(Int(proxy.size.height))")
              VideoPlayer(player: AVPlayer())
                .accessibilityLabel("Trailer")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
          }
        }
        Tab("Hidden bar", systemImage: "rectangle.stack", value: 1) {
          NavigationStack(path: .constant(pushedPath())) {
            Text("Hidden bar root")
          }
          .navigationDestination(for: Int.self) { _ in
            Text("Own back and tab bar")
              .navigationBarBackButtonHidden(true)
              .toolbar(.hidden, for: .tabBar)
          }
        }
        Tab("Shown bar", systemImage: "square.stack", value: 2) {
          NavigationStack(path: .constant(pushedPath())) {
            Text("Shown bar root")
          }
          .navigationDestination(for: Int.self) { _ in
            Text("Default back and tab bar")
          }
        }
        Tab("Merged bars", systemImage: "square.on.square", value: 5) {
          NavigationStack(path: .constant(pushedPath())) {
            Text("Merged root")
          }
          .navigationDestination(for: Int.self) { _ in
            Text("Merged detail")
              .navigationTitle("Merged title")
              .toolbar(.hidden, for: .navigationBar)
              .toolbarVisibility(.hidden, for: .tabBar)
          }
        }
      }
    }
  }
}
