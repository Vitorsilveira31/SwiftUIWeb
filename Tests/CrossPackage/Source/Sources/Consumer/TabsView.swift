// Apple-shaped TabView navigation, as an application writes it: a Binding built from a store, `Tab(value:)` inside a
// `ForEach`, a `TabSection` with its own `ForEach`, and tab modifiers. Every spelling here must compile in the
// application's own package, native and Embedded, with the same `TabContentBuilder` overloads Apple uses.
import SwiftUI

enum CrossSection: String, CaseIterable, Hashable {
  case inbox
  case drafts
  case archive

  var title: String { rawValue.capitalized }
}

enum CrossSectionGroup: String, CaseIterable, Hashable {
  case library

  var title: String { rawValue.capitalized }
  var sections: [CrossSection] { [.drafts, .archive] }
}

@MainActor final class CrossRouter {
  var section: CrossSection = .inbox
  func open(_ section: CrossSection) { self.section = section }
}

struct CrossTabsView: View {
  let router: CrossRouter
  let pendingCount: Int

  var body: some View {
    TabView(selection: Binding(get: { router.section }, set: { router.open($0) })) {
      ForEach(CrossSection.allCases.prefix(1), id: \.self) { section in
        Tab(section.title, systemImage: "tray", value: section) {
          Text(section.title)
        }
        .badge(pendingCount == 0 ? nil : Text("\(pendingCount)"))
      }
      ForEach(CrossSectionGroup.allCases, id: \.self) { group in
        TabSection(group.title) {
          ForEach(group.sections, id: \.self) { section in
            Tab(section.title, systemImage: "circle", value: section) {
              Text(section.title)
            }
          }
        }
      }
    }
    .tabViewStyle(.sidebarAdaptable)
  }
}

struct CrossPlainTabsView: View {
  @State private var selection: CrossSection = .inbox

  var body: some View {
    TabView(selection: $selection) {
      Tab("Inbox", systemImage: "circle", value: CrossSection.inbox) { Text("Inbox") }
      Tab("Archive", systemImage: "archivebox", value: CrossSection.archive) { Text("Archive") }
    }
  }
}
