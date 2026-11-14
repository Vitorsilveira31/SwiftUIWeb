import Testing
@_spi(Renderer) import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebFiber

/// Apple's optional-value tab declarations (`Tab` with `Value == T?`) and
/// `TabView(selection:)` over an optional binding.
private enum OptionalPane: Hashable {
  case general
  case wifi
}

@MainActor private func optionalTabs(_ selection: Binding<OptionalPane?>) -> some View {
  TabView(selection: selection) {
    Tab("General", systemImage: "gear", value: OptionalPane.general) { Text("General settings") }
    Tab("Wi-Fi", systemImage: "wifi", value: OptionalPane.wifi, role: nil) { Text("Wi-Fi settings") }
    TabSection {
      Tab("Privacy", systemImage: "lock", value: OptionalPane.general) { Text("Privacy settings") }
    } header: {
      Text("More")
    }
  }
}

/// Records the selection a reactive host last rendered.
private final class OptionalSelectionBox<Value>: @unchecked Sendable {
  var value: Value
  init(_ value: Value) { self.value = value }
}

@Suite
@MainActor
struct TabViewOptionalSelectionTests {
  @Test
  func optionalSelectionIsSetToSomeWhenTabIsTapped() throws {
    let box = OptionalSelectionBox<OptionalPane?>(nil)
    struct Host: View {
      @State private var selection: OptionalPane?
      let box: OptionalSelectionBox<OptionalPane?>
      var body: some View {
        box.value = selection
        return optionalTabs($selection)
      }
    }
    let tree = FiberTree(Host(box: box))

    // A nil selection shows the first tab without writing it into the binding.
    #expect(tree.renderNode.htmlDescription.contains("General settings"))
    #expect(box.value == nil)

    let wifiTab = try #require(findTab("Wi-Fi", in: tree.renderNode))
    tree.dispatch(event: "click", on: wifiTab)

    #expect(tree.renderNode.htmlDescription.contains("Wi-Fi settings"))
    #expect(box.value == .wifi)
  }

  @Test
  func optionalTabTagTracksOptionalBindingStateChanges() throws {
    struct Host: View {
      @State private var selection: OptionalPane? = .wifi
      var body: some View {
        optionalTabs($selection)
      }
    }
    let tree = FiberTree(Host())
    #expect(tree.renderNode.htmlDescription.contains("Wi-Fi settings"))

    let generalTab = try #require(findTab("General", in: tree.renderNode))
    tree.dispatch(event: "click", on: generalTab)
    #expect(tree.renderNode.htmlDescription.contains("General settings"))
  }

  @Test
  func sectionTitledByStringLiteralCompilesWithOptionalSelection() throws {
    struct Host: View {
      @State private var selection: OptionalPane?
      var body: some View {
        TabView(selection: $selection) {
          TabSection("Library") {
            Tab("Saved", systemImage: "bookmark", value: OptionalPane.wifi) { Text("Saved settings") }
          }
          TabSection {
            Tab("Archive", systemImage: "archivebox", value: OptionalPane.general) { Text("Archive settings") }
          }
        }
      }
    }
    let tree = FiberTree(Host())
    let savedTab = try #require(findTab("Saved", in: tree.renderNode))
    tree.dispatch(event: "click", on: savedTab)
    #expect(tree.renderNode.htmlDescription.contains("Saved settings"))
  }

  @Test
  func optionalValueTabInitializersCompileWithOptionalSelection() {
    // Each spelling below resolves its `Value == T?` overload against an optional binding.
    @MainActor func _check(_ selection: Binding<Int?>) -> some View {
      TabView(selection: selection) {
        Tab("Title", systemImage: "star", value: 1) { Text("one") }
        Tab(LocalizedStringKey("Key"), systemImage: "star", value: 2) { Text("two") }
        Tab("Role", systemImage: "star", value: 3, role: .search) { Text("three") }
        Tab(value: 4) { Text("four") } label: { Text("Label") }
        Tab(value: 5) { Text("five") }
      }
    }
    _ = _check(Binding(get: { nil }, set: { _ in }))
  }
}

extension TabViewOptionalSelectionTests {
  /// The spellings Apple's SwiftUI accepts (checked against the iOS and macOS SDKs); each must compile here too.
  @Test
  func tabInitializerSpellingsCompileAsInSwiftUI() {
    @MainActor func stringTabs(_ selection: Binding<String>) -> some View {
      TabView(selection: selection) {
        Tab("A", systemImage: "a", value: "a") { Text("a") }
        Tab(LocalizedStringKey("B"), systemImage: "b", value: "b") { Text("b") }
        Tab("C", systemImage: "c", value: "c", role: .search) { Text("c") }
        Tab(value: "d") { Text("d") }
        Tab(value: "e", role: nil) { Text("e") }
        Tab(value: "f") { Text("f") } label: { Text("L") }
        Tab(value: "g", role: nil) { Text("g") } label: { Text("L") }
        Tab(value: "h", content: { Text("h") }, label: { Text("L") })
        TabSection("S") { Tab("i", systemImage: "i", value: "i") { Text("i") } }
        TabSection { Tab("j", systemImage: "j", value: "j") { Text("j") } }
      }
    }
    @MainActor func optionalTabs(_ selection: Binding<OptionalPane?>) -> some View {
      TabView(selection: selection) {
        Tab("Q", systemImage: "q", value: OptionalPane.general) { Text("q") }
        Tab(value: OptionalPane.wifi) { Text("w") }
        TabSection { Tab("R", systemImage: "r", value: OptionalPane.wifi) { Text("r") } }
      }
    }
    @MainActor func untagged() -> some View {
      TabView {
        Tab(role: .search) { Text("search") }
        Tab("T", systemImage: "t") { Text("t") }
        Tab { Text("untagged") }
      }
    }
    _ = stringTabs(Binding.constant("a"))
    _ = optionalTabs(Binding.constant(nil))
    _ = untagged()
  }
}

private func findTab(_ label: String, in node: _RenderNode) -> _RenderNode? {
  if node.attributes["role"] == "tab", node.attributes["data-tab-label"] == label {
    return node
  }
  for child in node.children {
    if let found = findTab(label, in: child) { return found }
  }
  return nil
}
