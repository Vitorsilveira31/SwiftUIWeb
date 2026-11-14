import SwiftUIWeb

struct EmbeddedBuilderIdentityFixture: View {
  @State private var showsFirstBranch = true
  @State private var ids = ["A", "B", "C"]
  @State private var selectedTab = "overview"

  var body: some View {
    VStack {
      Text("builder identity probe")
      EmbeddedBuilderStatefulButton(label: "before branch")
      Button("Toggle conditional branch") { showsFirstBranch.toggle() }
      if showsFirstBranch {
        EmbeddedBuilderStatefulButton(label: "first branch")
      } else {
        EmbeddedBuilderStatefulButton(label: "second branch")
      }
      EmbeddedBuilderStatefulButton(label: "after branch")
      Button("Reorder IDs") { ids = ["C", "A", "B"] }
      Button("Insert at beginning") { ids = ["X", "C", "A", "B"] }
      Button("Insert in middle") { ids = ["X", "C", "Y", "A", "B"] }
      Button("Remove inserted IDs") { ids = ["C", "A", "B"] }
      ForEach(ids, id: \.self) { id in
        EmbeddedBuilderStatefulButton(label: id)
      }
      // `.id(_:)` is generic, so the Int reaches _FiberKey through a generic initializer.
      ForEach([3, 8], id: \.self) { number in
        Text("generic id \(number)").id(number)
      }
      Button("Open review") { selectedTab = "reviews" }
      switch selectedTab {
      case "overview":
        if #available(macOS 14.0, *) {
          VStack {
            Text("Overview")
            ForEach(["review"], id: \.self) { _ in
              AnyView(EmbeddedStatefulComparisonFixture())
            }
          }
        } else {
          EmptyView()
        }
      case "reviews":
        if #available(macOS 14.0, *) {
          VStack {
            Text("Reviews")
            ForEach(["review"], id: \.self) { _ in
              AnyView(EmbeddedStatefulComparisonFixture())
            }
            Text("Review history")
          }
        } else {
          EmptyView()
        }
      default:
        EmptyView()
      }
    }
  }
}
