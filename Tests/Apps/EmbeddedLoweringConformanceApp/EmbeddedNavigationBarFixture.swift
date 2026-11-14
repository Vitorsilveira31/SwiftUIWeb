import SwiftUIWeb

/// Pushed screens and the navigation bar each one asks for:
/// - an inline title sits between the system back button and a trailing item, centred and truncated, not under them;
/// - a large title sits below the bar row, so the back button and the title never share a box;
/// - `toolbar(.hidden, for: .navigationBar)` reserves no space: the title and the bar are gone and the screen starts
///   at the top of the stack;
/// - two `toolbar(_:for:)` modifiers on one screen merge, so the navigation bar stays hidden.
struct EmbeddedNavigationBarFixture: View {
  let onDone: () -> Void

  var body: some View {
    NavigationStack {
      VStack {
        Button("Return to conformance app") { onDone() }
        NavigationLink("Inline title", value: "inline")
        NavigationLink("Large title", value: "large")
        NavigationLink("Hidden bar", value: "hidden")
        NavigationLink("Merged bars", value: "merged")
      }
    }
    .navigationDestination(for: String.self) { value in
      switch value {
      case "large":
        Text("Large detail")
          .navigationTitle("Audiolivro Grande")
          .navigationBarTitleDisplayMode(.large)
      case "hidden":
        Text("Hidden detail")
          .navigationTitle("Hidden title")
          .toolbar(.hidden, for: .navigationBar)
      case "merged":
        Text("Merged detail")
          .navigationTitle("Merged title")
          .toolbar(.hidden, for: .navigationBar)
          .toolbar(.hidden, for: .tabBar)
      default:
        Text("Inline detail")
          .navigationTitle("Audiolivro")
          .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
              Button("Edit") {}
            }
          }
      }
    }
  }
}
