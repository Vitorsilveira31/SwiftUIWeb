import Testing
import SwiftUIWeb

/// A path with one pushed screen, so the stack renders its destination.
private func oneScreenPath() -> NavigationPath {
  var path = NavigationPath()
  path.append(1)
  return path
}

/// A screen pushed by a NavigationStack asks for its own navigation bar and tab bar, as SwiftUI lets it: the system
/// back button (`navigationBarBackButtonHidden`), the whole bar (`toolbar(.hidden, for: .navigationBar)`), and the
/// tab bar of an enclosing TabView (`toolbar(.hidden, for: .tabBar)`) while the requesting view is on screen.
@Suite
@MainActor
final class NavigationChromeRequestTests {
  private struct PushedScreen: View {
    let screen: AnyView
    var body: some View {
      NavigationStack(path: .constant(oneScreenPath())) {
        Text("Root")
      }
      .navigationDestination(for: Int.self) { _ in screen }
    }
  }

  private func backButtonCount(_ html: String) -> Int {
    html.components(separatedBy: "aria-label=\"Back\"").count - 1
  }

  @Test
  func testPushedScreenDrawsNoBackButtonOnTheWeb() {
    // As a website: the browser's back pops a pushed screen (every push is a history entry), so the bar draws none.
    let html = StaticHTMLFiberRenderer().render(PushedScreen(screen: AnyView(Text("Detail"))))
    _expectTrue(html.contains("Detail"))
    #expect(backButtonCount(html) == 0)
  }

  @Test
  func testPushedScreenKeepsTheToolbarItemsItDeclares() {
    let screen = AnyView(Text("Detail").toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") {} } })
    let html = StaticHTMLFiberRenderer().render(PushedScreen(screen: screen))
    _expectTrue(html.contains("Close"))
    #expect(backButtonCount(html) == 0)
  }

  @Test
  func testNavigationBarBackButtonHiddenRemovesOnlyTheSystemBackButton() {
    let screen = AnyView(
      VStack {
        Text("Detail")
        Button("Own back") {}
      }
      .navigationBarBackButtonHidden(true)
    )
    let html = StaticHTMLFiberRenderer().render(PushedScreen(screen: screen))
    _expectTrue(html.contains("Detail"))
    _expectTrue(html.contains("Own back"))
    #expect(backButtonCount(html) == 0)
  }

  @Test
  func testToolbarHiddenForNavigationBarRemovesBackButtonAndItems() {
    let screen = AnyView(
      Text("Detail")
        .toolbar { Text("Share item") }
        .toolbar(.hidden, for: .navigationBar)
    )
    let html = StaticHTMLFiberRenderer().render(PushedScreen(screen: screen))
    _expectTrue(html.contains("Detail"))
    #expect(backButtonCount(html) == 0)
    _expectFalse(html.contains("Share item"))
  }

  @Test
  func testToolbarHiddenForTabBarHidesTheTabBarWhileTheSelectedTabIsOnScreen() {
    struct Tabs: View {
      let hidesTabBar: Bool
      @State private var selection = 0
      var body: some View {
        TabView(selection: $selection) {
          Tab("Home", systemImage: "house", value: 0) {
            Text("Home content").toolbar(hidesTabBar ? .hidden : .visible, for: .tabBar)
          }
          Tab("Other", systemImage: "circle", value: 1) {
            Text("Other content")
          }
        }
      }
    }
    let shown = StaticHTMLFiberRenderer().render(Tabs(hidesTabBar: false))
    _expectTrue(shown.contains("tab-list"))
    let hidden = StaticHTMLFiberRenderer().render(Tabs(hidesTabBar: true))
    _expectTrue(hidden.contains("Home content"))
    _expectFalse(hidden.contains("tab-list"))
    _expectTrue(hidden.contains("data-tab-bar-hidden=\"true\""))
  }

  @Test
  func testToolbarHiddenForTabBarOnAPushedScreenHidesTheTabBar() {
    struct PushedInTab: View {
      let hidesTabBar: Bool
      @State private var selection = 0
      var body: some View {
        TabView(selection: $selection) {
          Tab("Home", systemImage: "house", value: 0) {
            NavigationStack(path: .constant(oneScreenPath())) {
              Text("Home root")
            }
            .navigationDestination(for: Int.self) { _ in
              Text("Pushed screen").toolbar(hidesTabBar ? .hidden : .visible, for: .tabBar)
            }
          }
          Tab("Other", systemImage: "circle", value: 1) {
            Text("Other content")
          }
        }
      }
    }
    let pushed = StaticHTMLFiberRenderer().render(PushedInTab(hidesTabBar: true))
    _expectTrue(pushed.contains("Pushed screen"))
    _expectFalse(pushed.contains("tab-list"))
    let visible = StaticHTMLFiberRenderer().render(PushedInTab(hidesTabBar: false))
    _expectTrue(visible.contains("tab-list"))
  }

  /// Two `toolbar(_:for:)` modifiers on one view merge: each placement keeps its own visibility, so the second one does
  /// not erase the first (SwiftUI treats the placements independently).
  @Test
  func testToolbarModifiersOnOneScreenMergeAcrossPlacements() {
    struct PushedInTab: View {
      @State private var selection = 0
      var body: some View {
        TabView(selection: $selection) {
          Tab("Home", systemImage: "house", value: 0) {
            NavigationStack(path: .constant(oneScreenPath())) {
              Text("Home root")
            }
            .navigationDestination(for: Int.self) { _ in
              Text("Pushed screen")
                .toolbar(.hidden, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
            }
          }
          Tab("Other", systemImage: "circle", value: 1) {
            Text("Other content")
          }
        }
      }
    }
    let html = StaticHTMLFiberRenderer().render(PushedInTab())
    _expectTrue(html.contains("Pushed screen"))
    #expect(backButtonCount(html) == 0)
    _expectFalse(html.contains("tab-list"))
  }

  /// `toolbarVisibility(_:for:)` (Apple's spelling) and `toolbar(_:for:)` share one record per placement.
  @Test
  func testToolbarVisibilitySpellingsMergeWithToolbar() {
    let screen = AnyView(
      Text("Detail")
        .toolbar(.hidden, for: .tabBar)
        .toolbarVisibility(.hidden, for: .navigationBar)
    )
    let html = StaticHTMLFiberRenderer().render(PushedScreen(screen: screen))
    #expect(backButtonCount(html) == 0)
  }

  /// A later declaration for the same placement wins, and an earlier one for another placement survives.
  @Test
  func testLastToolbarVisibilityWinsForEachPlacement() {
    let screen = AnyView(
      Text("Detail")
        .toolbar { Text("Share item") }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    )
    let html = StaticHTMLFiberRenderer().render(PushedScreen(screen: screen))
    _expectTrue(html.contains("Detail"))
    // The bar is shown: the screen's own item is drawn.
    _expectTrue(html.contains("Share item"))
    _expectFalse(html.contains("data-navigation-bar-hidden=\"true\""))
  }

  /// A hidden navigation bar is not drawn and reserves no space: the stack is marked, and its title bar is hidden in CSS.
  @Test
  func testHiddenNavigationBarIsMarkedSoItReservesNoSpace() {
    let screen = AnyView(
      Text("Detail")
        .navigationTitle("Hidden title")
        .toolbar(.hidden, for: .navigationBar)
    )
    let html = StaticHTMLFiberRenderer().render(PushedScreen(screen: screen))
    _expectTrue(html.contains("data-navigation-bar-hidden=\"true\""))
    #expect(backButtonCount(html) == 0)
  }

  /// A `ToolbarItem` in a screen's `toolbar` keeps its placement in the bar; it is not unwrapped into the content.
  @Test
  func testToolbarItemKeepsItsPlacementInThePushedBar() {
    let screen = AnyView(
      Text("Detail")
        .toolbar {
          ToolbarItem(placement: .navigationBarTrailing) {
            Button("Edit") {}
          }
        }
    )
    let html = StaticHTMLFiberRenderer().render(PushedScreen(screen: screen))
    _expectTrue(html.contains("data-toolbar-placement=\"navigation-bar-trailing\""))
    _expectTrue(html.contains("Edit"))
    _expectFalse(html.contains("data-navigation-bar-hidden=\"true\""))
  }
}
