import SwiftUIWeb
import SwiftUIWebWeb
import SwiftUIWebBrowser
import SwiftUIWebMapKit
import SwiftUIWebCharts

/// Showcase is the one framework tour. The focused examples that used to be
/// separate executables are represented here as real, interactive sections so
/// there is one maintained app to exercise the public API.
private enum ShowcaseSection: String, CaseIterable, Hashable {
  case gettingStarted = "Getting Started"
  case components = "Components"
  case layout = "Layout"
  case navigation = "Navigation"
  case presentation = "Presentation"
  case forms = "Forms"
  case collections = "Collections"
  case state = "State & Bindings"
  case themes = "Themes"
  case responsive = "Responsive"
  case advanced = "Advanced"
  /// Hidden from the sidebar; reached only by path for the reading-order gate.
  case readingOrder = "Reading order"
  /// Hidden from the sidebar; reached only by path for the button-highlight shape gate.
  case buttonShape = "Button shape"
  /// Hidden from the sidebar; reached only by path for the render-commit benchmark.
  case renderBenchSmall = "Render benchmark: small updates"
  /// Hidden from the sidebar; reached only by path for the render-commit benchmark.
  case renderBenchList = "Render benchmark: keyed list"
  case stackDepth = "Stack depth probe"
  /// Hidden from the sidebar; reached only by path for the browser table performance gate.
  case tablePerformance = "Table performance"
}

private extension ShowcaseSection {
  var token: String {
    switch self {
    case .gettingStarted: return "gettingStarted"
    case .components: return "components"
    case .layout: return "layout"
    case .navigation: return "navigation"
    case .presentation: return "presentation"
    case .forms: return "forms"
    case .collections: return "collections"
    case .state: return "state"
    case .themes: return "themes"
    case .responsive: return "responsive"
    case .advanced: return "advanced"
    case .readingOrder: return "readingOrder"
    case .buttonShape: return "buttonShape"
    case .renderBenchSmall: return "renderBenchSmall"
    case .renderBenchList: return "renderBenchList"
    case .stackDepth: return "stackDepth"
    case .tablePerformance: return "tablePerformance"
    }
  }
}

private func showcaseAnchor(_ text: String) -> String {
  var bytes: [UInt8] = []
  for byte in text.utf8 {
    let value = (65...90).contains(byte) ? byte + 32 : byte
    if (97...122).contains(value) || (48...57).contains(value) { bytes.append(value) }
    else if bytes.last != 45 { bytes.append(45) }
  }
  return String(decoding: bytes, as: UTF8.self)
}

private enum ShowcaseRoute: Hashable {
  case detail(String)
}

private struct ShowcaseRow: Identifiable, Hashable {
  let id: Int
  let title: String
  let status: String
}

private struct ShowcaseOutlineNode: Identifiable {
  let id: Int
  var title: String
  var symbol: String
  var children: [ShowcaseOutlineNode]?
}

private struct ShowcaseTriangle: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let minX = rect.origin.x
    let minY = rect.origin.y
    let maxX = minX + rect.size.width
    let maxY = minY + rect.size.height
    path.move(to: CGPoint(x: minX + rect.size.width / 2, y: minY))
    path.addLine(to: CGPoint(x: maxX, y: maxY))
    path.addLine(to: CGPoint(x: minX, y: maxY))
    path.closeSubpath()
    return path
  }
}

private struct ShowcasePrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(10)
      .foregroundStyle(.white)
      .background(configuration.isPressed ? Color.blue.opacity(0.75) : Color.blue)
      .clipShape(Capsule())
  }
}

private struct ShowcaseSecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .foregroundStyle(Color.cardForeground)
      .background(configuration.isPressed ? Color.accent : Color.muted)
      .border(Color.border)
      .cornerRadius(8)
      .opacity(configuration.isPressed ? 0.78 : 1)
  }
}

private enum ShowcaseDocumentError: Error, CustomStringConvertible {
  case notRegularFile

  var description: String { "The selected document is not a regular file" }
}

private struct ShowcaseTextDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.plainText] }
  static var writableContentTypes: [UTType] { [.plainText] }
  var text: String

  init(text: String = "SwiftUIWeb file export\n") { self.text = text }

  init(configuration: FileDocumentReadConfiguration) throws {
    guard let bytes = configuration.file.regularFileContents else {
      throw ShowcaseDocumentError.notRegularFile
    }
    text = String(decoding: bytes, as: UTF8.self)
  }

  func fileWrapper(configuration: FileDocumentWriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: Data(text.utf8))
  }
}

private struct ShowcaseFlowLayout: Layout {
  var columns: Int = 3
  var itemSpacing: CGFloat = 10

  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
    let count = max(1, columns)
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let cellWidth = sizes.map(\.width).max() ?? 0
    let cellHeight = sizes.map(\.height).max() ?? 0
    let rows = (sizes.count + count - 1) / count
    let width = proposal.width ?? CGFloat(count) * cellWidth + CGFloat(count - 1) * itemSpacing
    let height = proposal.height ?? CGFloat(rows) * cellHeight + CGFloat(max(0, rows - 1)) * itemSpacing
    return CGSize(width: width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
    let count = max(1, columns)
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let cellWidth = sizes.map(\.width).max() ?? 0
    let cellHeight = sizes.map(\.height).max() ?? 0
    for index in subviews.indices {
      let row = index / count
      let column = index % count
      let x = bounds.origin.x + CGFloat(column) * (cellWidth + itemSpacing)
      let y = bounds.origin.y + CGFloat(row) * (cellHeight + itemSpacing)
      subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: cellWidth, height: cellHeight))
    }
  }
}

private struct ShowcaseMotionValue {
  var scale: Double = 1
  var offset: Double = 0
}

/// Documentation chrome is a native document host; previews below it are
/// separate semantic layout roots. It does not override framework components.
private struct DocsChrome: ViewModifier {
  let role: String
  let tag: String
  func _apply(to node: _RenderNode, context: inout _RenderContext) {
    if node.kind == .text {
      let text = _RenderNode(kind: .text, text: node.text)
      node.text = nil; node.children = [text]
    }
    if case .element(let existing) = node.kind,
       tag == "div", ["button", "a", "input", "select", "textarea"].contains(existing) {
      // Documentation styling must not turn native controls into inert divs.
    } else { node.kind = .element(tag) }
    node.classes = []
    node.styles = [:]
    node.attributes.removeValue(forKey: "data-layout-kind")
    node.attributes["data-docs-part"] = role
    node.attributes["data-native-layout"] = role == "shell" ? "document" : "chrome"
  }
}
private struct DocsRoute: ViewModifier {
  let route: String
  let current: Bool
  func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-docs-route"] = route
    if current { node.attributes["aria-current"] = "page" }
    else { node.attributes.removeValue(forKey: "aria-current") }
  }
}
private extension View {
  func docs(_ role: String, tag: String = "div") -> ModifiedContent<Self, DocsChrome> { modifier(DocsChrome(role: role, tag: tag)) }
  func docsRoute(_ route: String, current: Bool = false) -> ModifiedContent<Self, DocsRoute> { modifier(DocsRoute(route: route, current: current)) }
}
private extension ShowcaseSection {
  var routePath: String { self == .gettingStarted ? "/" : "/" + token }
}

private struct DocsPreview: ViewModifier {
  func body(content: Content) -> some View {
    VStack(alignment: .leading, spacing: 0) { content }.docs("preview")
  }
}

private struct ShowcaseCard<Content: View>: View {
  let title: String
  let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).docs("example-title", tag: "h2").accessibilityIdentifier("showcase-example-title")
      VStack(alignment: .leading, spacing: 14) { content }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(AttributeModifier(attributes: ["data-layout-root": "preview"]))
        .accessibilityIdentifier("showcase-demo-surface")
        .modifier(DocsPreview())
    }
    .docs("example", tag: "section")
    .id("showcase-card-" + showcaseAnchor(title))
    .accessibilityIdentifier("showcase-example-card")
  }
}

private struct BoundCounter: View {
  @Binding var value: Int
  @State private var localCount = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Child binding: \(value)")
      HStack {
        Button("Decrease") { value -= 1 }
        Button("Increase") { value += 1 }
      }
      Text("Child-local state: \(localCount)")
        .font(.caption)
        .foregroundStyle(.secondary)
      Button("Change local state") { localCount += 1 }
    }
  }
}

private struct ShowcaseAppView: View {
  @Environment(\.colorScheme) private var colorScheme
  @State private var section: ShowcaseSection = .gettingStarted
  @State private var topicSearch = ""
  @State private var showTopics = false
  @State private var selectedTab = "Home"
  @State private var optionalTab: String?
  @State private var motionExpanded = false
  @State private var path = NavigationPath()
  @State private var darkMode: Bool? = nil
  @State private var isEnabled = true
  @State private var isExpanded = true
  @State private var showSheet = false
  @State private var showCover = false
  @State private var showPopover = false
  @State private var showAlert = false
  @State private var showConfirmation = false
  @State private var showToast = false
  @State private var name = "Taylor"
  @State private var secret = ""
  @State private var notes = "A multiline editor backed by Binding."
  @State private var choice = "Swift"
  @State private var progress = 0.65
  @State private var quantity = 2
  @State private var accent = Color.blue
  @State private var birthday = Date()
  @State private var counter = 0
  @State private var customLayoutVertical = false
  @State private var rows = [
    ShowcaseRow(id: 1, title: "Stable identity", status: "Ready"),
    ShowcaseRow(id: 2, title: "Fiber reconciliation", status: "Ready"),
    ShowcaseRow(id: 3, title: "WASM browser runtime", status: "Ready")
  ]
  @State private var outlineNodes = [
    ShowcaseOutlineNode(id: 1, title: "SwiftUIWeb", symbol: "folder.fill", children: [
      ShowcaseOutlineNode(id: 2, title: "Sources", symbol: "folder", children: [
        ShowcaseOutlineNode(id: 3, title: "Views.swift", symbol: "doc.text", children: nil),
        ShowcaseOutlineNode(id: 4, title: "OutlineGroup.swift", symbol: "doc.text", children: nil)
      ]),
      ShowcaseOutlineNode(id: 5, title: "Examples", symbol: "folder", children: [
        ShowcaseOutlineNode(id: 6, title: "ShowcaseApp", symbol: "rectangle.3.group", children: nil)
      ])
    ]),
    ShowcaseOutlineNode(id: 7, title: "Documentation", symbol: "folder", children: [
      ShowcaseOutlineNode(id: 8, title: "ARCHITECTURE.md", symbol: "doc.plaintext", children: nil)
    ])
  ]
  @State private var nextOutlineID = 100
  @State private var dropMessage = "Drop text, a URL, or a file here"
  @State private var dropTargeted = false
  @State private var modernScrollOffset = 0.0
  @State private var modernScrollPhase: ScrollPhase = .idle
  @State private var modernScrollPosition = ScrollPosition(idType: Int.self)
  @State private var railScrollPosition = ScrollPosition(idType: Int.self)
  @State private var rtlScrollPosition = ScrollPosition(idType: Int.self)
  @State private var meshAlternate = false
  @State private var animationTrigger = 0
  @State private var showFileImporter = false
  @State private var showFileExporter = false
  @State private var showFileMover = false
  @State private var exportedFile: URL?
  @State private var fileMessage = "No file selected"
  @State private var pastedText = "Nothing pasted yet"

  var body: some View {
    VStack(spacing: 0) {
      ShowcaseHeader(topicsVisible: showTopics, onTopics: { showTopics.toggle() }, onExamples: {
        section = .components; path.removeAll(); showTopics = false
      }, onDocumentation: {
        section = .gettingStarted; path.removeAll(); showTopics = false
      }, onToggleTheme: { darkMode = !(darkMode ?? (colorScheme == .dark)) })
      HStack(alignment: .top, spacing: 0) {
        VStack(alignment: .leading, spacing: 14) {
          HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter", text: $topicSearch)
              .accessibilityLabel("Filter topics")
              .accessibilityIdentifier("showcase-topic-filter")
          }
          .docs("filter")
          Button("Close menu") { showTopics = false }
            .buttonStyle(.plain).docs("drawer-close", tag: "button")
            .accessibilityIdentifier("showcase-drawer-close")
          topicGroup("OVERVIEW", [.gettingStarted])
          topicGroup("FUNDAMENTALS", [.layout, .state, .themes, .responsive])
          topicGroup("COMPONENTS", [.components, .forms, .collections])
          topicGroup("PATTERNS", [.navigation, .presentation, .advanced])
          Spacer()
          Text("Swift Embedded")
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .accessibilityIdentifier("showcase-runtime-label")
        }
        .docs("sidebar", tag: "nav")
        .accessibilityLabel("Documentation topics")
        .modifier(AttributeModifier(attributes: ["id": "showcase-topics", "data-docs-drawer": showTopics ? "open" : "closed"]))
        .accessibilityIdentifier(showTopics ? "showcase-sidebar-open" : "showcase-sidebar")

        NavigationStack(path: $path) {
          VStack(alignment: .leading, spacing: 0) {
              VStack(alignment: .leading, spacing: 14) {
                Text("SwiftUIWeb  /  " + section.rawValue)
                  .docs("breadcrumb")
                  .accessibilityIdentifier("showcase-breadcrumb")
                Text(section.rawValue).docs("title", tag: "h1")
                  .accessibilityIdentifier("showcase-page-title")
                  .documentHead { HeadElement.meta(name: "description", content: "SwiftUIWeb showcase: " + section.rawValue) }
                Text(sectionSummary).docs("summary", tag: "p")
                  .accessibilityIdentifier("showcase-page-summary")
              }
              .docs("intro", tag: "header")
              .accessibilityIdentifier("showcase-page-intro")

              showcaseContent
                .docs("examples")
                .id(section.token)
                .accessibilityIdentifier("showcase-examples")

              HStack {
                Text("Live SwiftUI examples running on Embedded Swift.")
                  .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset examples") { resetDemo() }.buttonStyle(.plain)
              }
              .docs("footer", tag: "footer")
              .accessibilityIdentifier("showcase-page-footer")
            }
            .docs("article", tag: "article")
            .accessibilityIdentifier("showcase-article")
          .navigationDestination(for: ShowcaseRoute.self) { route in
            switch route {
            case .detail(let title):
              VStack(alignment: .leading, spacing: 20) {
                Button("‹ Back to navigation") { path.removeLast() }
                  .buttonStyle(.plain)
                  .foregroundStyle(Color.blue)
                  .accessibilityIdentifier("showcase-route-back")
                Text(title).font(.largeTitle).bold()
                Text("A typed destination, with its state retained by NavigationStack.")
                  .foregroundStyle(.secondary)
                HStack {
                  Button("Push another detail") { path.append(ShowcaseRoute.detail("Next detail")) }
                  Button("Replace this detail") { path.removeLast(); path.append(ShowcaseRoute.detail("Replaced detail")) }
                  Button("Pop to root") { path.removeAll() }
                }
              }.padding(54).accessibilityIdentifier("showcase-destination").modifier(DocsLayoutRoot())
            }
          }
        }.modifier(AttributeModifier(attributes: ["data-docs-part": "main", "data-native-layout": "chrome"]))
         .accessibilityIdentifier("showcase-stack")

        VStack(alignment: .leading, spacing: 12) {
          Text("On this page").font(.caption).bold()
          ForEach(pageTopics, id: \.self) { title in
            Link(title, destination: URL(string: "#showcase-card-" + showcaseAnchor(title))!)
              .font(.caption)
          }
          Divider().padding(.vertical, 4)
          Text("LIVE EXAMPLES").font(.caption).bold().foregroundStyle(.secondary)
          Text("Change a value and the view updates in place.")
            .font(.caption).foregroundStyle(.secondary)
        }
        .docs("toc", tag: "aside")
        .accessibilityIdentifier("showcase-on-this-page")
      }.docs("workspace")
        .accessibilityIdentifier("showcase-workspace")
    }
    .docs("shell")
    .onOpenURL { url in
      var raw = url.absoluteString
      if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
        let authority = raw.dropFirst(raw.hasPrefix("https://") ? 8 : 7)
        raw = authority.firstIndex(of: "/").map { String(authority[$0...]) } ?? "/"
      }
      // The host passes a path, optionally with a query or fragment. No route
      // table lives in the reusable runtime.
      let pathPart = String(raw.split(separator: "?", maxSplits: 1).first ?? "").split(separator: "#", maxSplits: 1).first.map(String.init) ?? "/"
      if let destination = ShowcaseSection.allCases.first(where: { $0.routePath == pathPart || $0.routePath + "/" == pathPart }) {
        section = destination; path.removeAll(); showTopics = false
      }
    }
    .accessibilityIdentifier("showcase-shell")
    .preferredColorScheme(darkMode.map { $0 ? .dark : .light })
    .sheet(isPresented: $showSheet) {
      ShowcaseSheet(title: "Bottom sheet") { showSheet = false }
    }
    .fullScreenCover(isPresented: $showCover) {
      ShowcaseSheet(title: "Full-screen cover") { showCover = false }
    }
    .popover(isPresented: $showPopover) {
      VStack(spacing: 10) {
        Text("Popover content").font(.headline)
        Button("Dismiss") { showPopover = false }
      }.padding(24)
    }
    .alert("Delete this item?", isPresented: $showAlert, actions: {
      Button("Delete", role: .destructive) { if !rows.isEmpty { rows.removeLast() } }
      Button("Cancel", role: .cancel) {}
    })
    .confirmationDialog("Choose an action", isPresented: $showConfirmation) {
      Button("Duplicate") {}
      Button("Share") { showToast = true }
      Button("Cancel", role: .cancel) {}
    }
    .overlay(alignment: .bottomTrailing) {
      if showToast {
        HStack(spacing: 8) {
          Image(systemName: "checkmark.circle.fill")
          Text("Action completed")
          Button("Close") { showToast = false }
        }
        .padding(14).background(Color.card).foregroundStyle(Color.cardForeground)
        .cornerRadius(10).padding(20)
      }
    }
  }

  private var pageTopics: [String] {
    switch section {
    case .gettingStarted: return ["Typography", "Composition", "Modifiers"]
    case .components: return ["Buttons", "Feedback", "Controls", "Values", "Semantic content", "Disclosure"]
    case .layout: return ["Stacks and flexible space", "Lazy grids", "Geometry", "Custom Layout and AnyLayout", "IDE-style split view", "Master/detail"]
    case .navigation: return ["Typed navigation", "Split navigation"]
    case .presentation: return ["Presentations", "Keyboard and controls", "Overlay"]
    case .forms: return []
    case .collections: return ["List and identity", "ScrollViewReader", "Modern ScrollView", "Table", "OutlineGroup — file tree", "OutlineGroup — nested navigation", "Drag and drop"]
    case .state: return ["State and Binding", "Tabs"]
    case .themes: return ["Color scheme"]
    case .responsive: return ["ViewThatFits", "ResponsiveView"]
    case .advanced: return ["Browser-neutral integrations", "MeshGradient", "SVG Shapes and gradients", "State-driven motion", "Phase and keyframe animation", "Accessibility and loading", "File import and export", "PasteButton"]
    case .readingOrder: return []
    case .buttonShape: return []
    case .renderBenchSmall: return []
    case .renderBenchList: return []
    case .stackDepth: return []
    case .tablePerformance: return []
    }
  }

  private func showcaseContains(_ value: String, _ query: String) -> Bool {
    if query.isEmpty { return true }
    let haystack = Array(value.lowercased().utf8)
    let needle = Array(query.lowercased().utf8)
    if needle.isEmpty { return true }
    if needle.count > haystack.count { return false }
    var start = 0
    while start + needle.count <= haystack.count {
      var matched = true
      var offset = 0
      while offset < needle.count {
        if haystack[start + offset] != needle[offset] { matched = false; break }
        offset += 1
      }
      if matched { return true }
      start += 1
    }
    return false
  }

  private func topicGroup(_ title: String, _ entries: [ShowcaseSection]) -> some View {
    let items = entries.filter { showcaseContains($0.rawValue, topicSearch) }
    return VStack(alignment: .leading, spacing: 5) {
      if !items.isEmpty {
        Text(title).font(.caption).bold().foregroundStyle(.secondary)
          .docs("group-title", tag: "h2").accessibilityIdentifier("showcase-nav-group-title")
        ForEach(items, id: \.self) { item in
          Button {
            section = item; path.removeAll(); showTopics = false
          } label: {
            HStack(spacing: 10) {
              Image(systemName: icon(for: item)).frame(width: 16, height: 16)
              Text(item.rawValue)
              Spacer()
            }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("showcase-topic-" + item.token)
          .docs("topic", tag: "button")
          .docsRoute(item.routePath, current: item == section)
          .accessibilityLabel(item.rawValue)
          .accessibilityIdentifier("showcase-topic-" + item.token)
        }
      }
    }.docs("group")
  }

  private var sectionSummary: String {
    switch section {
    case .gettingStarted: return "The smallest useful SwiftUIWeb screen: views, modifiers, and state-driven composition."
    case .components: return "Controls and semantic content rendered with native HTML primitives."
    case .layout: return "Stacks, spacers, grids, frames, alignment, and geometry."
    case .navigation: return "Typed routes, push/pop, replacement, toolbar, and split navigation."
    case .presentation: return "Sheets, covers, popovers, alerts, confirmation dialogs, and overlays."
    case .forms: return "Bindings, validation, text input, selection, and submit actions."
    case .collections: return "Stable IDs, insertion, deletion, scrolling, and tabular content."
    case .state: return "State ownership, child bindings, conditional branches, and tabs."
    case .themes: return "A live color-scheme switch with reusable design tokens."
    case .responsive: return "One view hierarchy with compact and regular compositions."
    case .advanced: return "Browser-neutral integrations and accessibility-oriented APIs."
    case .readingOrder: return "Declaration-order fixture for the browser reading-order gate."
    case .buttonShape: return "Shape fixture for the browser button-highlight gate."
    case .renderBenchSmall: return "Small-update fixture for the render-commit benchmark."
    case .renderBenchList: return "Keyed 1000-row list fixture for the render-commit benchmark."
    case .stackDepth: return "Nested erased views to a chosen depth, to measure the WebAssembly call stack."
    case .tablePerformance: return "Two-thousand-row Table fixture for the browser performance gate."
    }
  }

  @ViewBuilder
  private var showcaseContent: some View {
    switch section {
    case .gettingStarted: gettingStarted
    case .components: components
    case .layout: layout
    case .navigation: navigation
    case .presentation: presentation
    case .forms: forms
    case .collections: collections
    case .state: state
    case .themes: themes
    case .responsive: responsive
    case .advanced: advanced
    case .readingOrder: ReadingOrderFixture()
    case .buttonShape: ButtonShapeFixture()
    case .renderBenchSmall: RenderCommitSmallUpdatesFixture()
    case .renderBenchList: RenderCommitListFixture()
    case .stackDepth: StackDepthFixture()
    case .tablePerformance: TablePerformanceFixture()
    }
  }

  private var gettingStarted: some View {
    VStack(alignment: .leading, spacing: 14) {
      ShowcaseCard("Typography") {
        Text("Large title").font(.largeTitle)
        Text("Headline").font(.headline)
        Text("Body text and interpolation: count = \(counter)")
        Text("Caption and secondary text").font(.caption).foregroundStyle(.secondary)
      }
      ShowcaseCard("Composition") {
        HStack { Text("Leading"); Spacer(); Text("Trailing") }
        ZStack { Text("ZStack layer").padding(22).background(Color.purple).foregroundStyle(.white).cornerRadius(10) }
        Divider()
        Button("Increment") { counter += 1 }.buttonStyle(ShowcasePrimaryButtonStyle())
        Link("Open Swift.org", destination: URL(string: "https://swift.org")!)
        if counter > 0 { Text("Conditional content is visible.").foregroundStyle(.green) }
      }
      ShowcaseCard("Modifiers") {
        Text("Padding, frame, background, border, corner radius, opacity")
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.blue.opacity(0.12))
          .border(Color.blue)
          .cornerRadius(8)
          .opacity(isEnabled ? 1 : 0.45)
        Toggle("Enabled", isOn: $isEnabled)
      }
    }
  }

  private var components: some View {
    VStack(alignment: .leading, spacing: 26) {
      ShowcaseCard("Buttons") {
        HStack {
          Button("Default") {}.buttonStyle(ShowcaseSecondaryButtonStyle())
          Button("Primary") {}.buttonStyle(ShowcasePrimaryButtonStyle())
        }
        Button("Disabled") {}
          .buttonStyle(ShowcaseSecondaryButtonStyle())
          .disabled(true)
      }
      ShowcaseCard("Feedback") {
        ProgressView(value: progress)
        ProgressView("Loading…")
        Gauge(value: progress, in: 0...1) { Text("Completion") }
        ContentUnavailableView("Nothing here", systemImage: "tray")
      }
      ShowcaseCard("Controls") {
        Toggle("Notifications", isOn: $isEnabled)
        Picker("Language", selection: $choice) {
          Option("Swift", value: "Swift")
          Option("WebAssembly", value: "WebAssembly")
          Option("WASI", value: "WASI")
        }
        Slider(value: $progress, in: 0...1, step: 0.05)
      }
      ShowcaseCard("Slider value labels") {
        Slider(value: $progress, in: 0...1, step: 0.05, minimumValueLabel: Text("0%"), maximumValueLabel: Text("100%")) {
          Text("Progress")
        }
      }
      ShowcaseCard("Values") {
        Stepper("Quantity", value: $quantity, in: 0...10)
        ColorPicker("Accent", selection: $accent, supportsOpacity: false)
        Menu("More actions") {
          Button("Reset") { resetDemo() }
          Button("Delete", role: .destructive) { showAlert = true }
        }
      }
      ShowcaseCard("Semantic content") {
        Label("Settings", systemImage: "gearshape")
        LabeledContent("Status", value: "Ready")
        GroupBox("Account") { LabeledContent("Plan", value: "SwiftUIWeb") }
      }
      ShowcaseCard("Disclosure") {
        DisclosureGroup("Details", isExpanded: $isExpanded) {
          Text("DisclosureGroup preserves its state.")
        }
        AsyncImage(url: nil) { phase in
          if phase.error != nil { Text("Image unavailable").foregroundStyle(.secondary) }
          else { Text("Image loading…") }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var layout: some View {
    VStack(alignment: .leading, spacing: 14) {
      ShowcaseCard("Stacks and flexible space") {
        HStack { Text("HStack"); Spacer(); Text("Trailing") }
          .frame(maxWidth: .infinity)
        VStack { Text("VStack"); Spacer(minLength: 4); Text("with Spacer") }
          .frame(height: 90)
          .border(Color.gray)
        ZStack { Text("ZStack").padding(24).background(Color.purple).foregroundStyle(.white) }
      }
      ShowcaseCard("Lazy grids") {
        LazyVGrid(columns: [GridItem(.flexible(minimum: 0)), GridItem(.flexible(minimum: 0))], spacing: 8) {
          ForEach(1...6, id: \.self) { index in
            Text("Cell \(index)").frame(maxWidth: .infinity).padding(12).background(Color.blue.opacity(0.12)).cornerRadius(8)
          }
        }
        LazyHGrid(rows: [GridItem(.flexible(minimum: 0)), GridItem(.flexible(minimum: 0))], spacing: 8) {
          ForEach(1...4, id: \.self) { index in Text("H\(index)").padding(12).border(Color.gray) }
        }
      }
      ShowcaseCard("Geometry") {
        GeometryReader { proxy in
          Text("Available size: \(proxy.size.width) × \(proxy.size.height)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.green.opacity(0.12))
        }
        .frame(height: 80)
      }
      ShowcaseCard("Custom Layout and AnyLayout") {
        Toggle("Vertical arrangement", isOn: $customLayoutVertical)
        let selected: AnyLayout = customLayoutVertical
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
          : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        selected {
          Text("Runtime")
            .padding(10)
            .background(Color.blue.opacity(0.14))
            .cornerRadius(8)
          Text("switching")
            .padding(10)
            .background(Color.green.opacity(0.14))
            .cornerRadius(8)
          Text("keeps identity")
            .padding(10)
            .background(Color.orange.opacity(0.14))
            .cornerRadius(8)
        }
        ShowcaseFlowLayout(columns: 3, itemSpacing: 8) {
          ForEach(1...6, id: \.self) { index in
            Text("Flow \(index)")
              .frame(width: 72, height: 28)
              .background(Color.purple.opacity(0.14))
              .cornerRadius(6)
          }
        }
        GridLayout(horizontalSpacing: 8, verticalSpacing: 8) {
          GridRow { Text("Grid A"); Text("Grid B") }
          GridRow { Text("Grid C"); Text("Grid D") }
        }
      }
      ShowcaseCard("IDE-style split view") {
        HSplitView {
          VStack(alignment: .leading, spacing: 8) {
            Text("Navigator").font(.headline)
            ForEach(["Project", "Sources", "Tests"], id: \.self) { item in
              Text(item).padding(6).frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .padding(10)
          VSplitView {
            Text("Editor").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(12)
            Text("Inspector").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(12)
          }
        }
        .frame(height: 220)
        .border(Color.border)
      }
      ShowcaseCard("Master/detail") {
        HSplitView {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.id) { row in
              Button(row.title) { choice = row.title }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .padding(10)
          VStack(alignment: .leading, spacing: 8) {
            Text("Selected item").font(.headline)
            Text(choice)
            Text("Drag the divider or use Arrow keys when it has focus.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(14)
        }
        .frame(height: 170)
        .border(Color.border)
      }
      ShowcaseCard("Divider limits") {
        HSplitView {
          Text("Min 120, max 240")
            .padding(10)
            .frame(minWidth: 120, idealWidth: 160, maxWidth: 240, maxHeight: .infinity, alignment: .topLeading)
          Text("Flexible pane")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
        }
        .frame(height: 100)
        .border(Color.border)
      }
    }
  }

  private var navigation: some View {
    VStack(alignment: .leading, spacing: 14) {
      ShowcaseCard("Typed navigation") {
        NavigationLink("Push a detail", value: ShowcaseRoute.detail("Detail route"))
        HStack {
          Button("Push programmatically") { path.append(ShowcaseRoute.detail("Programmatic route")) }
          Button("Pop") { path.removeLast() }.disabled(path.isEmpty)
          Button("Pop to root") { path.removeAll() }.disabled(path.isEmpty)
        }
        Button("Replace current route") {
          path.removeLast(); path.append(ShowcaseRoute.detail("Replaced route"))
        }.disabled(path.isEmpty)
      }
      ShowcaseCard("Split navigation") {
        Text("The documentation shell uses ordinary stacks. This example demonstrates an independent NavigationSplitView.")
          .foregroundStyle(.secondary)
        NavigationSplitView {
          Text("Sidebar").padding(12)
        } detail: {
          Text("Detail column").padding(12)
        }.frame(height: 140)
      }
    }
  }

  private var presentation: some View {
    VStack(alignment: .leading, spacing: 14) {
      ShowcaseCard("Presentations") {
        HStack {
          Button("Sheet") { showSheet = true }
          Button("Full screen") { showCover = true }
          Button("Popover") { showPopover = true }
        }
        HStack {
          Button("Alert") { showAlert = true }
          Button("Confirmation") { showConfirmation = true }
          Button("Toast") { showToast = true }
        }
      }
      ShowcaseCard("Keyboard and controls") {
        ShowcaseInteractionLab()
      }
      ShowcaseCard("Overlay") {
        Text("The toast is an ordinary overlay view. Tap Toast above, then dismiss it.")
        Button("Show toast") { showToast = true }.buttonStyle(ShowcasePrimaryButtonStyle())
      }
    }
  }

  private var forms: some View {
    Form {
      Section("Profile") {
        TextField("Name", text: $name)
        SecureField("Password", text: $secret)
        TextEditor(text: $notes).frame(height: 90)
        Picker("Language", selection: $choice) {
          Option("Swift", value: "Swift")
          Option("WebAssembly", value: "WebAssembly")
        }
        DatePicker("Date", selection: $birthday)
        Toggle("Notifications", isOn: $isEnabled)
        Slider(value: $progress, in: 0...1)
      }
      Section("Validation") {
        if name.isEmpty {
          Text("Name is required").foregroundStyle(.red)
        }
        Button("Save") { showToast = true }
          .disabled(name.isEmpty || secret.isEmpty)
          .buttonStyle(ShowcasePrimaryButtonStyle())
        Button("Reset") { name = "Taylor"; secret = ""; notes = "" }
      }
    }
    .onSubmit { showToast = true }
  }

  private var collections: some View {
    VStack(alignment: .leading, spacing: 14) {
      ShowcaseCard("List and identity") {
        HStack {
          Button("Insert") {
            let next = (rows.map(\.id).max() ?? 0) + 1
            rows.append(ShowcaseRow(id: next, title: "Inserted row \(next)", status: "New"))
          }
          Button("Delete last") { if !rows.isEmpty { rows.removeLast() } }.disabled(rows.isEmpty)
          Button("Confirmation") { showConfirmation = true }
        }
        List {
          ForEach(rows, id: \.id) { row in
            HStack { Text(row.title); Spacer(); Text(row.status).foregroundStyle(.secondary) }
              .id(row.id)
          }
        }
        .frame(height: 160)
      }
      ShowcaseCard("ScrollViewReader") {
        ScrollViewReader { proxy in
          VStack {
            Button("Scroll to row 8") { proxy.scrollTo(8, anchor: .center) }
            ScrollView(.horizontal) {
              HStack {
                ForEach(1...12, id: \.self) { number in
                  Text("\(number)").id(number).padding(12).background(Color.blue.opacity(0.12)).cornerRadius(8)
                }
              }
            }
          }
        }
      }
      ShowcaseCard("Modern ScrollView") {
        Text("Offset: \(Int(modernScrollOffset)) px • \(modernScrollPhase)")
          .font(.caption)
        Button("Jump to item 40") { modernScrollPosition.scrollTo(id: 40, anchor: .center) }
        Button("Scroll to bottom edge") { modernScrollPosition.scrollTo(edge: .bottom) }
        Button("Scroll to offset 300") { modernScrollPosition.scrollTo(y: 300) }
        Button("Animate to top edge") { withAnimation { modernScrollPosition.scrollTo(edge: .top) } }
        Text("Positioned by user: \(modernScrollPosition.isPositionedByUser)")
          .font(.caption)
        Button("Scroll rail to trailing edge") { railScrollPosition.scrollTo(edge: .trailing) }
        Button("Scroll rail to x 120") { railScrollPosition.scrollTo(x: 120) }
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(1...40, id: \.self) { number in
              Text("Chip \(number)").padding(8).background(Color.blue.opacity(0.08)).id(number)
            }
          }
          .scrollTargetLayout()
        }
        .scrollPosition($railScrollPosition)
        Button("RTL leading edge") { rtlScrollPosition.scrollTo(edge: .leading) }
        Button("RTL trailing edge") { rtlScrollPosition.scrollTo(edge: .trailing) }
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(1...20, id: \.self) { number in
              Text("RTL \(number)").padding(8).background(Color.green.opacity(0.1)).id(number)
            }
          }
          .scrollTargetLayout()
        }
        .environment(\.layoutDirection, .rightToLeft)
        .scrollPosition($rtlScrollPosition)
        ScrollView {
          LazyVStack(spacing: 8) {
            ForEach(1...80, id: \.self) { number in
              Text("Virtual item \(number)")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(8)
                .id(number)
                .scrollTransition(axis: .vertical) { content, phase in
                  phase.isIdentity ? content : content.opacity(0.45).scaleEffect(0.97)
                }
            }
          }
          .scrollTargetLayout()
        }
        .frame(height: 220)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition($modernScrollPosition)
        .onScrollGeometryChange(for: Double.self, of: { $0.contentOffset.y }) { _, value in
          modernScrollOffset = value
        }
        .onScrollPhaseChange { _, phase in
          modernScrollPhase = phase
        }
      }
      ShowcaseCard("Table") {
        Table(rows) {
          TableColumn("Title", value: \ShowcaseRow.title)
          TableColumn("Status", value: \ShowcaseRow.status)
        }
      }
      ShowcaseCard("OutlineGroup — file tree") {
        HStack {
          Button("Add file") {
            let id = nextOutlineID
            nextOutlineID += 1
            let file = ShowcaseOutlineNode(id: id, title: "Generated-\(id).swift", symbol: "doc.text", children: nil)
            if let index = outlineNodes.firstIndex(where: { $0.title == "SwiftUIWeb" }) {
              outlineNodes[index].children = (outlineNodes[index].children ?? []) + [file]
            }
          }
          Button("Remove file") {
            guard let index = outlineNodes.firstIndex(where: { $0.title == "SwiftUIWeb" }),
                  var children = outlineNodes[index].children,
                  children.count > 1 else { return }
            children.removeLast()
            outlineNodes[index].children = children
          }
        }
        OutlineGroup(outlineNodes, children: \.children) { node in
          HStack(spacing: 8) {
            Image(systemName: node.symbol)
              .foregroundStyle(node.children == nil ? Color.secondary : Color.accent)
            Text(node.title)
          }
        }
      }
      ShowcaseCard("OutlineGroup — nested navigation") {
        Text("Expand a branch to browse the same recursive model used by a navigation sidebar.")
          .font(.caption)
          .foregroundStyle(.secondary)
        OutlineGroup(outlineNodes, children: \.children) { node in
          NavigationLink(node.title, value: ShowcaseRoute.detail(node.title))
        }
      }
      ShowcaseCard("Drag and drop") {
        Text("Reorderable content")
          .font(.headline)
        ForEach(rows, id: \.id) { row in
          HStack {
            Image(systemName: "line.3.horizontal")
            Text(row.title)
            Spacer()
          }
          .padding(8)
          .background(Color.blue.opacity(0.08))
          .cornerRadius(6)
          .draggable(row.title)
          .dropDestination(for: String.self, action: { titles, _ in
            guard let title = titles.first,
                  let source = rows.firstIndex(where: { $0.title == title }),
                  let destination = rows.firstIndex(where: { $0.id == row.id }),
                  source != destination else { return false }
            let moved = rows.remove(at: source)
            rows.insert(moved, at: min(destination, rows.count))
            dropMessage = "Moved \(moved.title)"
            return true
          }, isTargeted: { dropTargeted = $0 })
        }
        Text(dropMessage)
          .font(.caption)
          .foregroundStyle(dropTargeted ? Color.accent : Color.secondary)
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(dropTargeted ? Color.accent.opacity(0.12) : Color.muted)
          .cornerRadius(6)
          .dropDestination(for: String.self, action: { values, _ in
            guard let value = values.first else { return false }
            dropMessage = "Received: \(value)"
            return true
          }, isTargeted: { dropTargeted = $0 })
        HStack {
          Text("Files / external URLs")
          Spacer()
          Text("Drag from Finder or another tab")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onDrop(of: [.fileURL, .url, .data], isTargeted: $dropTargeted) { providers in
          guard let provider = providers.first else { return false }
          let name = provider.suggestedName ?? provider.registeredTypeIdentifiers.first ?? "item"
          dropMessage = "Received \(name) (loadable on demand)"
          return true
        }
      }
    }
  }

  private var state: some View {
    VStack(alignment: .leading, spacing: 14) {
      ShowcaseCard("State and Binding") {
        Text("Parent state: \(counter)").font(.title2)
        BoundCounter(value: $counter)
        if counter.isMultiple(of: 2) {
          Text("Conditional branch A").foregroundStyle(.green)
        } else {
          Text("Conditional branch B").foregroundStyle(.orange)
        }
      }
      ShowcaseCard("Tabs") {
        TabView(selection: $selectedTab) {
          Text("Home tab").tag("Home").tabItem { Label("Home", systemImage: "house") }
          Text("Settings tab").tag("Settings").tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .frame(height: 90)
        Button("Select Settings") { selectedTab = "Settings" }
        // Optional selection: the tabs are tagged with non-optional values and the binding is `String?`.
        TabView(selection: $optionalTab) {
          Tab("Alpha", systemImage: "a.circle", value: "alpha") { Text("Alpha panel") }
          Tab("Beta", systemImage: "b.circle", value: "beta") { Text("Beta panel") }
        }
        .frame(height: 90)
        Text("Optional tab: \(optionalTab ?? "none")")
      }
    }
  }

  private var themes: some View {
    ShowcaseCard("Color scheme") {
      Toggle("Dark mode", isOn: Binding(get: { darkMode ?? (colorScheme == .dark) }, set: { darkMode = $0 }))
      Text(colorScheme == .dark ? "Dark scheme" : "Light scheme").font(.title2)
      HStack {
        Text("Background").padding(12).background(Color.background)
        Text("Accent").padding(12).background(accent).foregroundStyle(.white)
      }
      Text("preferredColorScheme propagates through the environment.")
        .foregroundStyle(.secondary)
    }
  }

  private var responsive: some View {
    VStack(alignment: .leading, spacing: 14) {
      ShowcaseCard("ViewThatFits") {
        ViewThatFits(in: .horizontal) {
          HStack { Image(systemName: "rectangle.split.3x1"); Text("Wide layout with all controls"); Spacer(); Button("Action") {} }
          VStack(alignment: .leading) { Text("Compact layout"); Button("Action") {} }
        }
      }
      ShowcaseCard("ResponsiveView") {
        ViewThatFits(in: .horizontal) {
          HStack { Image(systemName: "ipad"); Text("Regular composition with sidebar") }
          VStack { Image(systemName: "iphone"); Text("Compact composition") }
        }
      }
    }
  }

  private var advanced: some View {
    VStack(alignment: .leading, spacing: 14) {
      ShowcaseCard("Browser-neutral integrations") {
        Canvas { context, _ in
          let size = CGSize(width: 320, height: 120)
          var background = Path()
          background.addRect(CGRect(origin: CGPoint(x: 0, y: 0), size: size))
          let gradient = Gradient(colors: [Color.blue.opacity(0.9), Color.purple.opacity(0.8)])
          context.fill(background, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: size.height)))
          var line = Path()
          line.move(to: CGPoint(x: 12, y: 92))
          line.addLine(to: CGPoint(x: 72, y: 66))
          line.addLine(to: CGPoint(x: 132, y: 74))
          line.addLine(to: CGPoint(x: 192, y: 38))
          line.addLine(to: CGPoint(x: 252, y: 52))
          line.addLine(to: CGPoint(x: 308, y: 18))
          context.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
          context.draw(Text("Canvas 2D"), at: CGPoint(x: 14, y: 16), anchor: .topLeading)
        }
        .frame(height: 120)
        Chart {
          PointMark(x: .value("X", 1), y: .value("Value", 3))
          PointMark(x: .value("X", 2), y: .value("Value", 7))
          PointMark(x: .value("X", 3), y: .value("Value", 5))
        }.frame(height: 140)
        Map().frame(height: 240)
        WebContentView(url: "data:text/html,%3Chtml%3E%3Cbody%20style%3D%27font-family%3Asystem-ui%3Bpadding%3A24px%3Bbackground%3A%23f6f7f9%27%3E%3Ch2%3ESwiftUIWeb%20WebView%3C%2Fh2%3E%3Cp%3EEmbedded%20iframe%20content%20loaded%20successfully.%3C%2Fp%3E%3C%2Fbody%3E%3C%2Fhtml%3E", title: "Embedded WebView")
          .frame(height: 140)
        ShareLink(item: "SwiftUIWeb")
      }
      ShowcaseCard("Canvas symbols") {
        // A tagged symbol drawn at a known top-left position; a system image with a two-entry palette; and one at the
        // secondary hierarchical level. The browser test samples the ink of each drawing.
        Canvas { context, _ in
          if let badge = context.resolveSymbol(id: "badge") {
            context.draw(badge, at: CGPoint(x: 10, y: 10), anchor: .topLeading)
          }
          var palette = context.resolve(Image(systemName: "star.fill"))
          palette.shading = .palette([.color(Color.red), .color(Color.blue)])
          context.draw(palette, at: CGPoint(x: 150, y: 10), anchor: .topLeading)
          var secondary = context.resolve(Image(systemName: "star.fill"))
          secondary.shading = .style(HierarchicalShapeStyle.secondary)
          context.draw(secondary, at: CGPoint(x: 200, y: 10), anchor: .topLeading)
        } symbols: {
          Text("Badge").tag("badge")
        }
        .frame(width: 300, height: 48)
        .accessibilityIdentifier("showcase-canvas-symbols")
      }
      ShowcaseCard("Foreground levels") {
        // Inside `.foregroundStyle(.red, .blue)`, primary text is red, `.secondary` text is blue, and a canvas fill
        // of the secondary level is blue as well. The browser test compares the rendered paints.
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 12) {
            Text("a").foregroundStyle(.primary).accessibilityIdentifier("showcase-level-primary")
            Text("b").foregroundStyle(.secondary).accessibilityIdentifier("showcase-level-secondary")
          }
          Canvas { context, _ in
            var band = Path()
            band.addRect(CGRect(x: 0, y: 0, width: 40, height: 10))
            context.fill(band, with: .style(HierarchicalShapeStyle.secondary))
          }
          .frame(width: 40, height: 10)
        }
        .foregroundStyle(Color.red, Color.blue)
      }
      ShowcaseCard("Palette shading") {
        // Three 100pt bands: a palette paints with its first entry, a second palette
        // with its first entry, and an empty palette paints nothing. The browser test
        // samples the band centers.
        Canvas { context, _ in
          var first = Path()
          first.addRect(CGRect(x: 0, y: 0, width: 100, height: 10))
          context.fill(first, with: .palette([.color(Color.red), .color(Color.green)]))
          var second = Path()
          second.addRect(CGRect(x: 100, y: 0, width: 100, height: 10))
          context.fill(second, with: .palette([.color(Color.green), .color(Color.blue)]))
          var empty = Path()
          empty.addRect(CGRect(x: 200, y: 0, width: 100, height: 10))
          context.fill(empty, with: .palette([]))
        }
        .frame(width: 300, height: 10)
      }
      ShowcaseCard("Gradient shading style") {
        // `Shading.style` with a gradient resolves its unit points against the painted path: black at the left
        // edge of the band, white at its right edge.
        Canvas { context, _ in
          var band = Path()
          band.addRect(CGRect(x: 0, y: 0, width: 200, height: 10))
          context.fill(band, with: .style(LinearGradient(colors: [Color.black, Color.white], startPoint: .leading, endPoint: .trailing)))
        }
        .frame(width: 200, height: 10)
      }
      ShowcaseCard("ShapeView stacking") {
        // fill, then stroke over it on one shape; a stroke then a fill; and a strokeBorder over a fill.
        HStack(spacing: 12) {
          Circle()
            .fill(Color.red)
            .stroke(Color.blue, lineWidth: 4)
            .frame(width: 40, height: 40)
            .accessibilityIdentifier("showcase-shape-stacked-fill-stroke")
          Circle()
            .stroke(Color.blue, lineWidth: 4)
            .fill(Color.red)
            .frame(width: 40, height: 40)
            .accessibilityIdentifier("showcase-shape-stacked-stroke-fill")
          Rectangle()
            .fill(Color.green)
            .strokeBorder(Color.blue, lineWidth: 4)
            .frame(width: 40, height: 40)
            .accessibilityIdentifier("showcase-shape-stroke-border")
          Circle()
            .stroke(lineWidth: 4)
            .fill(Color.blue)
            .frame(width: 40, height: 40)
            .accessibilityIdentifier("showcase-shape-outline-fill")
        }
      }
      ShowcaseCard("Gradient spread") {
        // Three side-by-side 10pt-high bands: linear repeat, linear mirror, radial repeat. Canvas
        // has no tiling mode, so the browser test samples pixels to check the expanded ramps.
        Canvas { context, _ in
          let ramp = Gradient(colors: [Color.black, Color.white])
          var repeatBand = Path()
          repeatBand.addRect(CGRect(x: 0, y: 0, width: 240, height: 10))
          context.fill(repeatBand, with: .linearGradient(ramp, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 40, y: 0), options: [.repeat]))
          var mirrorBand = Path()
          mirrorBand.addRect(CGRect(x: 240, y: 0, width: 240, height: 10))
          context.fill(mirrorBand, with: .linearGradient(ramp, startPoint: CGPoint(x: 240, y: 0), endPoint: CGPoint(x: 280, y: 0), options: [.mirror]))
          var radialBand = Path()
          radialBand.addRect(CGRect(x: 480, y: 0, width: 240, height: 10))
          context.fill(radialBand, with: .radialGradient(ramp, center: CGPoint(x: 600, y: 5), startRadius: 0, endRadius: 10, options: [.repeat]))
        }
      }
      ShowcaseCard("Tiled image shading") {
        // A 2x2 PNG (red, green / blue, white) tiled at scale 10. The second band moves the
        // tile grid with `origin`.
        Canvas { context, _ in
          let tile = Image("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGP4z8DAAMIM/4EAAB/uBfsL2WiLAAAAAElFTkSuQmCC")
          var tiled = Path()
          tiled.addRect(CGRect(x: 0, y: 0, width: 100, height: 10))
          context.fill(tiled, with: .tiledImage(tile, origin: CGPoint(x: 0, y: 0), scale: 10))
          var offset = Path()
          offset.addRect(CGRect(x: 200, y: 0, width: 100, height: 10))
          context.fill(offset, with: .tiledImage(tile, origin: CGPoint(x: 203, y: 0), scale: 10))
        }
      }
      ShowcaseCard("Image paint") {
        // The same 2x2 PNG as an ImagePaint: as a background (scale 10 gives 20pt tiles), with a
        // sub-rect (the left half, 10pt wide), as a shape fill and as a text style.
        let tile = Image("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGP4z8DAAMIM/4EAAB/uBfsL2WiLAAAAAElFTkSuQmCC")
        Text("Background")
          .padding(12)
          .background(.image(tile, scale: 10))
          .accessibilityIdentifier("showcase-image-paint-background")
        Text("Left half")
          .padding(12)
          .background(.image(tile, sourceRect: CGRect(x: 0, y: 0, width: 0.5, height: 1), scale: 10))
          .accessibilityIdentifier("showcase-image-paint-sub-rect")
        HStack(spacing: 12) {
          Circle()
            .fill(.image(tile, scale: 10))
            .frame(width: 60, height: 60)
            .accessibilityIdentifier("showcase-image-paint-shape")
          Text("Image text")
            .font(.title)
            .foregroundStyle(.image(tile, scale: 10))
            .accessibilityIdentifier("showcase-image-paint-text")
        }
      }
      ShowcaseCard("Elliptical gradient") {
        // Shape and background elliptical gradients. The shape's ellipse is inscribed in its 200x100 bounds, so
        // the 0.5 end radius touches the edges; the browser test checks the radial gradient and its stops.
        Rectangle()
          .fill(.ellipticalGradient(colors: [Color.black, Color.white], startRadiusFraction: 0, endRadiusFraction: 0.5))
          .frame(width: 200, height: 100)
          .accessibilityIdentifier("showcase-elliptical-shape")
        Text("Elliptical background")
          .padding(12)
          .background(.ellipticalGradient(colors: [Color.black, Color.white], startRadiusFraction: 0.25, endRadiusFraction: 0.5))
          .accessibilityIdentifier("showcase-elliptical-background")
      }
      ShowcaseCard("AnyGradient shading") {
        // A Gradient wrapped in AnyGradient paints a Canvas band like the plain Gradient would. The browser
        // test samples the ends of the ramp: black at the left edge, white at the right.
        Canvas { context, size in
          var band = Path()
          band.addRect(CGRect(x: 0, y: 0, width: size.width, height: 10))
          let ramp = AnyGradient(Gradient(colors: [Color.black, Color.white]))
          context.fill(band, with: .linearGradient(ramp, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: 0)))
        }
        .accessibilityIdentifier("showcase-any-gradient-canvas")
      }
      ShowcaseCard("DOMViewRepresentable") {
        ShowcaseDOMComponentDemo()
      }
      ShowcaseCard("MeshGradient") {
        Text("Canvas 2D mesh interpolation")
          .font(.caption)
          .foregroundStyle(.secondary)
        MeshGradient(
          width: 3,
          height: 3,
          points: [
            .init(0, 0), .init(0.5, 0), .init(1, 0),
            .init(0, 0.5), .init(0.5, 0.45), .init(1, 0.5),
            .init(0, 1), .init(0.5, 1), .init(1, 1)
          ],
          colors: meshAlternate
            ? [.orange, .red, .purple, .blue, .white, .orange, .green, .blue, .purple]
            : [.blue, .purple, .orange, .green, .white, .red, .purple, .blue, .orange],
          background: .black,
          smoothsColors: true,
          colorSpace: .perceptual
        )
        .frame(height: 180)
        .cornerRadius(12)
        .animation(.easeInOut(duration: 0.4), value: meshAlternate)
        Button(meshAlternate ? "Show first palette" : "Animate palette") {
          withAnimation(.easeInOut(duration: 0.4)) { meshAlternate.toggle() }
        }
        .buttonStyle(ShowcaseSecondaryButtonStyle())
        Text("The same SwiftUI MeshGradient value works as a view or a background style; the browser rasterizer stays private and retained across resizes.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      ShowcaseCard("SVG Shapes and gradients") {
        HStack(spacing: 12) {
          ShowcaseTriangle()
            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
            .frame(width: 72, height: 64)
          RoundedRectangle(cornerRadius: 12)
            .strokeBorder(
              AngularGradient(colors: [.orange, .pink, .purple, .orange], center: .center),
              lineWidth: 5
            )
            .frame(width: 72, height: 64)
          Circle()
            .fill(RadialGradient(colors: [.white, .blue], center: .center, startRadius: 0, endRadius: 48))
            .frame(width: 64, height: 64)
        }
        .padding(8)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 12))
        // Semantic and adaptive colors stay unresolved until the browser
        // paints them, so SVG fills, strokes and gradient stops follow the
        // active color scheme exactly like text and backgrounds do.
        HStack(spacing: 12) {
          Circle()
            .fill(Color.background)
            .frame(width: 32, height: 32)
            .accessibilityIdentifier("showcase-shape-semantic-fill")
          Circle()
            .stroke(Color("light-dark(#0b6bcb, #7cc4ff)"), lineWidth: 3)
            .frame(width: 32, height: 32)
            .accessibilityIdentifier("showcase-shape-adaptive-stroke")
          Capsule()
            .fill(LinearGradient(colors: [Color.background, Color("light-dark(#0b6bcb, #7cc4ff)").opacity(0.5)], startPoint: .leading, endPoint: .trailing))
            .frame(width: 72, height: 32)
            .accessibilityIdentifier("showcase-shape-adaptive-gradient")
        }
        .padding(8)
        Text("Custom Shape.path(in:) is rendered as retained SVG geometry; fills, strokes, trims, clips and masks stay SwiftUI-shaped.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      ShowcaseCard("State-driven motion") {
        RoundedRectangle(cornerRadius: 16)
          .fill(Color.blue)
          .frame(width: motionExpanded ? 180 : 72, height: 64)
          .opacity(motionExpanded ? 1 : 0.5)
          .animation(.easeInOut(duration: 0.6), value: motionExpanded)
          .accessibilityIdentifier("showcase-motion-target")
        HStack {
          Button("Animate state") { motionExpanded.toggle() }
          Button("Unrelated counter") { counter += 1 }
          Text("Count: \(counter)")
        }
        Text("Retarget mid-animation. Updating another value must not replace this element or restart its animation.")
          .font(.caption).foregroundStyle(.secondary)
      }
      ShowcaseCard("Phase and keyframe animation") {
        PhaseAnimator([false, true]) { phase in
          Text("Pulse")
            .padding(10)
            .background(phase ? Color.purple.opacity(0.22) : Color.blue.opacity(0.14))
            .cornerRadius(8)
        }
        Text("A browser-native repeating phase animation")
          .font(.caption)
          .foregroundStyle(.secondary)
        HStack {
          Button("Run keyframes") { animationTrigger += 1 }
            .buttonStyle(ShowcasePrimaryButtonStyle())
          Text("Runs: \(animationTrigger)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Text("SwiftUIWeb")
          .keyframeAnimator(initialValue: ShowcaseMotionValue(), trigger: animationTrigger) { content, value in
            content
              .scaleEffect(value.scale)
              .offset(x: value.offset)
              .padding(10)
              .background(Color.accent.opacity(0.16))
              .cornerRadius(8)
          } keyframes: { _ in
            KeyframeTrack(\.scale) {
              LinearKeyframe(1.18, duration: 0.18)
              SpringKeyframe(1.0, duration: 0.42)
            }
            KeyframeTrack(\.offset) {
              MoveKeyframe(20)
            }
          }
        Text("The browser interpolates the timeline without per-frame Swift/WASM callbacks; changing or removing the view cancels it safely.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      ShowcaseCard("Accessibility and loading") {
        Text("Accessible status")
          .accessibilityLabel("Framework status")
          .accessibilityValue("Ready")
          .accessibilityHint("This status updates as the showcase changes")
        Text("Loading placeholder").redacted(reason: .placeholder)
        Button("Refresh") { showToast = true }.refreshable { await MainActor.run { showToast = true } }
          .safeAreaInset(edge: .bottom) { Text("Safe area content").font(.caption) }
      }
      ShowcaseCard("File import and export") {
        HStack {
          Button("Choose text file") { showFileImporter = true }
            .buttonStyle(ShowcaseSecondaryButtonStyle())
          Button("Export report") { showFileExporter = true }
            .buttonStyle(ShowcasePrimaryButtonStyle())
          Button("Move export") { showFileMover = true }
            .buttonStyle(ShowcaseSecondaryButtonStyle())
            .disabled(exportedFile == nil)
            .accessibilityIdentifier("showcase-file-move")
        }
        Text(fileMessage)
          .accessibilityIdentifier("showcase-file-message")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      .fileImporter(
        isPresented: $showFileImporter,
        allowedContentTypes: [.plainText, .json],
        onCompletion: { result in
          switch result {
          case .success(let url):
            fileMessage = "Selected \(url.absoluteString); load with SwiftUIWebFileRuntime.load(_:)"
          case .failure(let error):
            fileMessage = "Import failed: \(error)"
          }
        }
      )
      .fileExporter(
        isPresented: $showFileExporter,
        document: ShowcaseTextDocument(text: "SwiftUIWeb export generated at runtime.\n"),
        contentType: .plainText,
        defaultFilename: "swiftuiweb-report.txt",
        onCompletion: { result in
          switch result {
          case .success(let url):
            exportedFile = url
            fileMessage = "Exported \(url.absoluteString)"
          case .failure: fileMessage = "Export failed"
          }
        }
      )
      .fileMover(
        isPresented: $showFileMover,
        file: exportedFile,
        onCompletion: { result in
          switch result {
          case .success(let url):
            exportedFile = url
            fileMessage = "Moved to \(url.absoluteString)"
          case .failure: fileMessage = "Move failed"
          }
        },
        onCancellation: { fileMessage = "Move cancelled" }
      )
      ShowcaseCard("PasteButton") {
        PasteButton(payloadType: String.self) { values in
          pastedText = values.joined(separator: "\n")
        }
        .buttonStyle(ShowcaseSecondaryButtonStyle())
        Text(pastedText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(3)
        Text("Uses the browser clipboard only after an explicit click; unsupported or denied permissions leave the control safe and inert.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func icon(for item: ShowcaseSection) -> String {
    switch item {
    case .gettingStarted: return "sparkles"
    case .components: return "square.grid.2x2"
    case .layout: return "rectangle.split.3x1"
    case .navigation: return "arrow.right"
    case .presentation: return "rectangle.on.rectangle"
    case .forms: return "pencil.line"
    case .collections: return "list.bullet"
    case .state: return "dot.scope"
    case .themes: return "circle.lefthalf.filled"
    case .responsive: return "rectangle.resize"
    case .advanced: return "wrench.and.screwdriver"
    case .readingOrder: return "list.number"
    case .buttonShape: return "circle.square"
    case .renderBenchSmall: return "list.number"
    case .renderBenchList: return "list.bullet"
    case .stackDepth: return "square.stack.3d.up"
    case .tablePerformance: return "tablecells"
    }
  }

  private func resetDemo() {
    path.removeAll()
    showToast = false
    counter = 0
    isExpanded = true
    isEnabled = true
    choice = "Swift"
    selectedTab = "Home"
    optionalTab = nil
    motionExpanded = false
    customLayoutVertical = false
    quantity = 2
    progress = 0.65
    rows = [
      ShowcaseRow(id: 1, title: "Stable identity", status: "Ready"),
      ShowcaseRow(id: 2, title: "Fiber reconciliation", status: "Ready"),
      ShowcaseRow(id: 3, title: "WASM browser runtime", status: "Ready")
    ]
  }
}

private struct ShowcaseSheet: View {
  @Environment(\.dismiss) private var dismiss
  let title: String
  let onDismiss: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Text(title).font(.title)
      Text("Presentation uses the same SwiftUI modifier API on every host.")
      Button("Dismiss") {
        onDismiss()
        dismiss()
      }
      .buttonStyle(ShowcasePrimaryButtonStyle())
    }
    .padding(32)
  }
}

/// A small, fixed application header inspired by component documentation
/// sites. It is built from ordinary SwiftUI views so the browser renderer can
/// adapt it to its available width without a web-specific API.
private struct ShowcaseHeader: View {
  let topicsVisible: Bool
  let onTopics: @MainActor () -> Void
  let onExamples: @MainActor () -> Void
  let onDocumentation: @MainActor () -> Void
  let onToggleTheme: @MainActor () -> Void

  var body: some View {
    HStack(spacing: 16) {
      Button(topicsVisible ? "Close" : "Menu", action: onTopics)
        .buttonStyle(.plain).docs("menu-toggle", tag: "button")
        .modifier(AttributeModifier(attributes: ["aria-controls": "showcase-topics", "aria-expanded": topicsVisible ? "true" : "false"]))
        .accessibilityIdentifier("showcase-mobile-menu")
      Button("SwiftUIWeb", action: onDocumentation)
        .buttonStyle(.plain).docs("brand", tag: "button").docsRoute("/")
        .accessibilityIdentifier("showcase-brand")
      Spacer()
      Button("Overview", action: onDocumentation)
        .buttonStyle(.plain).docs("header-link", tag: "button").docsRoute("/")
      Button("Components", action: onExamples)
        .buttonStyle(.plain).docs("header-link", tag: "button").docsRoute("/components")
      Button("Appearance", action: onToggleTheme)
        .buttonStyle(.plain).docs("theme-toggle", tag: "button")
        .accessibilityLabel("Toggle light and dark appearance")
        .accessibilityIdentifier("showcase-theme-toggle")
    }
    .docs("header", tag: "header")
    .accessibilityIdentifier("showcase-header")
  }
}

@main
struct ShowcaseApp: BrowserApp {
  var body: some View { WindowGroup { ShowcaseAppView() } }
}

private struct DocsLayoutRoot: ViewModifier {
  func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-layout-root"] = "true"
  }
}
