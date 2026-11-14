import SwiftUIWeb

/// The fixture for the view-transition browser test (`Tools/test-view-transition-browser.mjs`). A card and its detail are
/// one matched pair: only one of the two is on the page at a time, so the pair names one element. `Duplicate` adds a second
/// source with the same name, which the host guard must count and skip without changing the final DOM. `Bump` is an unrelated
/// change. `Zoom` pushes a destination that zooms from the root's `zoom` source, and `Back` pops it. `Pin` swaps a small
/// view for a big one that match only their top-leading corner (`properties: .position`, `anchor: .topLeading`). `Slow pin`
/// swaps them inside `withAnimation`, and `Value pin` with a change of the value an `.animation(_:value:)` above them names.
struct ViewTransitionRootView: View {
  @Namespace private var namespace
  @State private var isOpen = false
  @State private var showsDuplicate = false
  @State private var bumps = 0
  @State private var path = NavigationPath()
  @State private var pinned = false
  @State private var pinSteps = 0

  var body: some View {
    let ns = namespace
    let pathBinding = $path
    NavigationStack(path: $path) {
      VStack {
        Button("Toggle") { isOpen.toggle() }.accessibilityIdentifier("toggle")
        Button("Duplicate") { showsDuplicate.toggle() }.accessibilityIdentifier("duplicate")
        // An unrelated change: it can land while a transition of a swap above waits for its frame.
        Button("Bump") { bumps += 1 }.accessibilityIdentifier("bump")
        Text("bumps \(bumps)").accessibilityIdentifier("bumps")
        if isOpen {
          Text("Detail").matchedGeometryEffect(id: "hero", in: ns).accessibilityIdentifier("detail")
        } else {
          Text("Card").matchedGeometryEffect(id: "hero", in: ns).accessibilityIdentifier("card")
        }
        if showsDuplicate {
          Text("Second").matchedTransitionSource(id: "hero", in: ns).accessibilityIdentifier("second")
        }
        Text(isOpen ? "open" : "closed").accessibilityIdentifier("state")
        Button("Pin") { pinned.toggle() }.accessibilityIdentifier("pin")
        Button("Slow pin") { withAnimation(.linear(duration: 0.6)) { pinned.toggle() } }.accessibilityIdentifier("slow-pin")
        Button("Value pin") { pinned.toggle(); pinSteps += 1 }.accessibilityIdentifier("value-pin")
        VStack {
          if pinned {
            Text("Pinned").frame(width: 160, height: 60)
              .matchedGeometryEffect(id: "pin", in: ns, properties: .position, anchor: .topLeading)
              .accessibilityIdentifier("pinned")
          } else {
            Text("Pin").frame(width: 40, height: 20)
              .matchedGeometryEffect(id: "pin", in: ns, properties: .position, anchor: .topLeading)
              .accessibilityIdentifier("unpinned")
          }
        }
        .animation(.linear(duration: 0.9), value: pinSteps)
        Button("Zoom") { pathBinding.wrappedValue.append(1) }
          .matchedTransitionSource(id: "zoom", in: ns)
          .accessibilityIdentifier("zoom")
      }
      .navigationDestination(for: Int.self) { _ in
        VStack {
          Text("Zoomed").navigationTransition(.zoom(sourceID: "zoom", in: ns)).accessibilityIdentifier("zoomed")
          Button("Back") { pathBinding.wrappedValue.removeLast() }.accessibilityIdentifier("back")
        }
      }
    }
  }
}
