import Testing
import SwiftUIWeb

@Suite(.serialized)
@MainActor
struct AnyViewNavigationIdentityTests {
  @Test
  func keyedAnyViewStateReconcilesAfterNavigationPush() {
    struct ComparisonCard: View {
      @State private var expanded = false
      @State private var comment = ""

      var body: some View {
        VStack {
          Button(expanded ? "Hide previous version" : "Load previous version") {
            expanded.toggle()
          }
          if expanded {
            Text("Previous version loaded")
          }
          TextField("Reviewer comment", text: $comment)
        }
      }
    }

    struct ReviewDestination: View {
      @State private var selectedTab = "overview"

      var body: some View {
        ScrollView {
          VStack {
            Text("Production")
            HStack {
              VStack { Text("A station"); Text("Waiting Human") }
              Spacer()
              Text("Work 360")
            }
            HStack {
              Button("Overview") { selectedTab = "overview" }
              Button("Open reviews") { selectedTab = "reviews" }
            }
            switch selectedTab {
            case "reviews":
              VStack {
                Text("Workflow reviews")
                ForEach(["task-review-001"], id: \.self) { _ in
                  AnyView(ComparisonCard())
                }
                Text("Review history")
              }
            default:
              Text("Overview")
            }
          }
        }
      }
    }

    struct Root: View {
      @State private var path = NavigationPath()

      var body: some View {
        NavigationStack(path: $path) {
          Button("Open production") { path.append("review") }
            .navigationDestination(for: String.self) { _ in ReviewDestination() }
        }
      }
    }

    let root = Root()
    let tree = FiberTree(root)
    tree.dispatch(event: "click", on: button(named: "Open production", in: tree.root.renderNode))
    _ = tree.update(root)
    #expect(tree.renderNode.htmlDescription.contains("Production"))

    tree.dispatch(event: "click", on: button(named: "Open reviews", in: tree.root.renderNode))
    _ = tree.renderNode
    #expect(tree.renderNode.htmlDescription.contains("Workflow reviews"))

    tree.dispatch(event: "click", on: button(named: "Load previous version", in: tree.root.renderNode))
    _ = tree.renderNode
    #expect(tree.renderNode.htmlDescription.contains("Hide previous version"))
    #expect(tree.renderNode.htmlDescription.contains("Previous version loaded"))

    tree.dispatch(event: "click", on: button(named: "Hide previous version", in: tree.root.renderNode))
    _ = tree.renderNode
    #expect(!tree.renderNode.htmlDescription.contains("Previous version loaded"))
    #expect(tree.renderNode.htmlDescription.contains("Review history"))
  }

  private func button(named label: String, in node: _RenderNode) -> _RenderNode? {
    if node.events["click"] != nil && text(in: node) == label { return node }
    for child in node.children {
      if let match = button(named: label, in: child) { return match }
    }
    return nil
  }

  private func text(in node: _RenderNode) -> String {
    (node.text ?? "") + node.children.map(text(in:)).joined()
  }
}
