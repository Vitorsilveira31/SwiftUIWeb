import SwiftUIWeb

/// `TabView(selection:)` with `Tab(value:)`, `ForEach` of tabs and a `TabSection`, shaped like an application's
/// adaptive navigation. Apple's `TabContentBuilder` must accept every child here on Embedded too.
private enum TabFixtureSection: String, CaseIterable, Hashable {
  case inbox
  case drafts
  case archive
}

private enum TabFixtureGroup: String, CaseIterable, Hashable {
  case library

  var sections: [TabFixtureSection] { [.drafts, .archive] }
}

struct EmbeddedTabViewFixture: View {
  @State private var selection: TabFixtureSection = .inbox

  var body: some View {
    VStack {
      Text("Selected: \(selection.rawValue)")
      TabView(selection: Binding(get: { selection }, set: { selection = $0 })) {
        Tab("Inbox", systemImage: "tray", value: TabFixtureSection.inbox) {
          Text("Inbox content")
        }
        .badge(2)
        ForEach(TabFixtureGroup.allCases, id: \.self) { group in
          TabSection(group.rawValue) {
            ForEach(group.sections, id: \.self) { section in
              Tab(section.rawValue, systemImage: "circle", value: section) {
                Text("\(section.rawValue) content")
              }
            }
          }
        }
      }
      .tabViewStyle(.sidebarAdaptable)
    }
  }
}
