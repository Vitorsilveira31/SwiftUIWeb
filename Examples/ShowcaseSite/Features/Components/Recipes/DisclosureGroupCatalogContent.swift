import SwiftUIWeb

/// A `DisclosureGroup` with its own `isExpanded` state, initialised from the knob; the group then opens and closes by itself.
struct DisclosureGroupCatalogContent: View {
  let title: String
  @State private var isExpanded: Bool

  init(title: String, startsExpanded: Bool) {
    self.title = title
    _isExpanded = State(initialValue: startsExpanded)
  }

  var body: some View {
    DisclosureGroup(title, isExpanded: $isExpanded) {
      Text("Shown when expanded")
    }
  }
}
