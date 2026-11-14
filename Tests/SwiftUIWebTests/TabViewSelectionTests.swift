import Testing
@_spi(Renderer) import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebFiber

@MainActor private func genericIntegerTabs<Selection: Hashable>(
  selection: Binding<Selection>,
  general: Selection,
  wifi: Selection
) -> some View {
  TabView(selection: selection) {
    Tab("General", systemImage: "circle", value: general) { Text("General settings") }
    Tab("Wi-Fi", systemImage: "circle", value: wifi) { Text("Wi-Fi settings") }
  }
}

/// Records the selection a reactive host last rendered.
private final class SelectionBox<Value>: @unchecked Sendable {
  var value: Value
  init(_ value: Value) { self.value = value }
}

@Suite
@MainActor
struct TabViewSelectionTests {
  private enum SettingsTab: Hashable {
    case general
    case wifi
  }

  private struct StateBackedTabs: View {
    @State(memberID: 42) private var selected = 0
    var selectionValue: Int { selected }

    var body: some View {
      VStack {
        Text("selection-\(selected)")
        TabView(selection: $selected) {
          Tab("Settings", systemImage: "circle", value: 0) { Text("Settings panel") }
          Tab("Wi-Fi", systemImage: "circle", value: 1) { Text("Wi-Fi panel") }
        }
      }
    }
  }

  @Test
  func selectingTabUpdatesStateBackedSelection() {
    let view = StateBackedTabs()
    let tree = FiberTree(view)

    func findTab(_ node: _RenderNode) -> _RenderNode? {
      if node.attributes["role"] == "tab", node.attributes["data-tab-label"] == "Wi-Fi" {
        return node
      }
      for child in node.children {
        if let found = findTab(child) { return found }
      }
      return nil
    }

    guard let wifiTab = findTab(tree.renderNode) else {
      Issue.record("Expected a rendered Wi-Fi tab")
      return
    }
    tree.dispatch(event: "click", on: wifiTab)

    #expect(view.selectionValue == 1)
    #expect(tree.renderNode.htmlDescription.contains("data-selected-tab=\"1\""))
    #expect(tree.renderNode.htmlDescription.contains("Wi-Fi panel"))

    // SwiftUI-style view values are reconstructed as their parent body is
    // reevaluated. Stable lowered member IDs must reconnect the fresh wrapper
    // to the original StateStore box instead of resetting the selection.
    _ = tree.update(StateBackedTabs())
    #expect(tree.renderNode.htmlDescription.contains("data-selected-tab=\"1\""))
    #expect(tree.renderNode.htmlDescription.contains("Wi-Fi panel"))
  }

  @Test
  func selectingTabUpdatesHashableEnumBinding() throws {
    // A reactive selection: an unselected tab is only built once it is chosen.
    let box = SelectionBox<SettingsTab>(.general)
    struct Host: View {
      @State private var selection = SettingsTab.general
      let box: SelectionBox<SettingsTab>
      var body: some View {
        box.value = selection
        return TabView(selection: $selection) {
          Tab("General", systemImage: "circle", value: SettingsTab.general) { Text("General settings") }
          Tab("Wi-Fi", systemImage: "circle", value: SettingsTab.wifi) { Text("Wi-Fi settings") }
        }
      }
    }
    let tree = FiberTree(Host(box: box))

    func findTab(_ node: _RenderNode) -> _RenderNode? {
      if node.attributes["role"] == "tab", node.attributes["data-tab-label"] == "Wi-Fi" {
        return node
      }
      for child in node.children {
        if let found = findTab(child) { return found }
      }
      return nil
    }

    let wifiTab = try #require(findTab(tree.renderNode))
    tree.dispatch(event: "click", on: wifiTab)

    #expect(tree.renderNode.htmlDescription.contains("Wi-Fi settings"))
    #expect(box.value == .wifi)
  }

  @Test
  func selectingTabOwnedByViewStateUpdatesSelection() throws {
    struct Host: View {
      @State private var selected = "general"
      var body: some View {
        TabView(selection: $selected) {
          Tab("General", systemImage: "circle", value: "general") { Text("General settings") }
          Tab("Wi-Fi", systemImage: "circle", value: "wifi") { Text("Wi-Fi settings") }
        }
      }
    }
    let tree = FiberTree(Host())

    func findTab(_ node: _RenderNode) -> _RenderNode? {
      if node.attributes["role"] == "tab", node.attributes["data-tab-label"] == "Wi-Fi" {
        return node
      }
      for child in node.children {
        if let found = findTab(child) { return found }
      }
      return nil
    }

    let wifiTab = try #require(findTab(tree.renderNode))
    tree.dispatch(event: "click", on: wifiTab)

    #expect(tree.renderNode.htmlDescription.contains("data-selected-tab=\"wifi\""))
    #expect(tree.renderNode.htmlDescription.contains("Wi-Fi settings"))
  }

  @Test
  func genericTabViewOverloadRoundTripsIntegerSelections() throws {
    let box = SelectionBox<Int>(0)
    struct Host: View {
      @State private var selected = 0
      let box: SelectionBox<Int>
      var body: some View {
        box.value = selected
        return genericIntegerTabs(selection: $selected, general: 0, wifi: 1)
      }
    }
    let tree = FiberTree(Host(box: box))
    let wifiTab = try #require(findTab("Wi-Fi", in: tree.renderNode))

    tree.dispatch(event: "click", on: wifiTab)

    #expect(tree.renderNode.htmlDescription.contains("Wi-Fi settings"))
    #expect(box.value == 1)
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
}
