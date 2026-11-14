import Testing
@testable import SwiftUIWeb
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
@testable import SwiftUIWebFiber
@testable import SwiftUIWebHTML
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebTransferable

private enum GapStorageUnit: String, CaseIterable, Hashable, Sendable { case celsius = "C", fahrenheit = "F" }
private enum GapStorageLevel: Int, Hashable, Sendable { case low = 1, high = 2 }

/// The declarations the example apps use, compiled as they are written: each property wrapper initializer is picked by
/// the compiler from the property's declared type.
@MainActor private struct GapStorageDeclarations: View {
  @AppStorage("gap.airplane") var airplane = false
  @AppStorage("gap.textScale") var textScale = 1.0
  @AppStorage("gap.appearance") var appearance = "dark"
  @AppStorage("gap.unit") var unit: GapStorageUnit = .fahrenheit
  @AppStorage("gap.level") var level: GapStorageLevel = .low
  @AppStorage("gap.link") var link: URL = URL(string: "https://example.com")!
  @AppStorage("gap.blob") var blob: Data = Data()
  @AppStorage("gap.optionalUnit") var optionalUnit: GapStorageUnit?
  @AppStorage("gap.optionalLevel") var optionalLevel: GapStorageLevel?
  @AppStorage("gap.optionalLink") var optionalLink: URL?
  var body: some View { Text("storage") }
}

@Suite(.serialized, .processGlobalState)
@MainActor
final class ViewAPIGapTests {
  private var values: [String: String] = [:]

  deinit {
    StorageRuntime.install(nil)
  }

  private func installStorage() {
    StorageRuntime.install(StorageAdapter(
      read: { [unowned self] in values[$0] },
      write: { [unowned self] in values[$0] = $1 },
      remove: { [unowned self] in values[$0] = nil }
    ))
  }

  /// Every render node of `node`'s tree, outermost first.
  private func allNodes(_ node: _RenderNode) -> [_RenderNode] {
    var result: [_RenderNode] = []
    var pending = [node]
    while let next = pending.popLast() {
      result.append(next)
      pending.append(contentsOf: next.children.reversed())
    }
    return result
  }

  private func html<V: View>(_ view: V) -> String { StaticHTMLFiberRenderer().render(view) }

  // MARK: Button(_:systemImage:action:)

  @Test func buttonWithTitleAndSystemImageRendersBothLabelParts() {
    let button = Button("Restart", systemImage: "arrow.counterclockwise") {}
    let rendered = html(button)
    #expect(rendered.contains("Restart"))
    #expect(rendered.contains("arrow.counterclockwise"), "the symbol is the label's icon")
    let tree = FiberTree(button).renderNode
    let node = try? #require(allNodes(tree).first { $0.attributes["data-control-kind"] == "button" })
    #expect(node?.events["click"] != nil, "the action is wired to the button element")
  }

  @Test func buttonWithSystemImageAcceptsARoleAndAStringTitle() {
    let title: String = "Delete"
    let destructive = Button(title, systemImage: "trash", role: .destructive) {}
    let rendered = html(destructive)
    #expect(rendered.contains("Delete") && rendered.contains("trash"))
    #expect(FiberTree(destructive).renderNode.attributes["data-role"] == "destructive")
  }

  // MARK: ContentUnavailableView.search

  @Test func searchStateUsesAppleWordingAndSearchSymbol() {
    let plain = html(ContentUnavailableView.search)
    #expect(plain.contains("No Results"))
    #expect(plain.contains("Check the spelling or try a new search."))
    #expect(plain.contains("magnifyingglass"))

    let withQuery = html(ContentUnavailableView.search(text: "kiwi"))
    #expect(withQuery.contains("No Results for “kiwi”"))
    #expect(withQuery.contains("Check the spelling or try a new search."))
  }

  // MARK: gridCellColumns and the other grid cell modifiers

  @Test func gridCellModifiersWriteTheAttributesTheGridPlacesBy() {
    let spanning = FiberTree(Rectangle().gridCellColumns(2)).renderNode
    #expect(allNodes(spanning).contains { $0.attributes["data-grid-cell-columns"] == "2" })

    let anchored = FiberTree(Rectangle().gridCellAnchor(.bottomTrailing)).renderNode
    #expect(allNodes(anchored).contains { $0.attributes["data-grid-cell-anchor"] == "1.0,1.0" })

    let unsized = FiberTree(Rectangle().gridCellUnsizedAxes(.horizontal)).renderNode
    #expect(allNodes(unsized).contains { $0.attributes["data-grid-unsized-axes"] == "1" })

    let aligned = FiberTree(Rectangle().gridColumnAlignment(.trailing)).renderNode
    #expect(allNodes(aligned).contains { $0.attributes["data-grid-column-alignment"] == "flex-end" })
  }

  @Test func spanningCellIsPlacedAcrossItsColumns() {
    // Column widths: the 100pt spanning cell widens two 40pt columns (with the 8pt gap) to 46pt each.
    let rendered = StaticHTMLFiberRenderer().render(
      GridLayout(horizontalSpacing: 8, verticalSpacing: 8) {
        GridRow {
          Rectangle().frame(width: 100, height: 20).gridCellColumns(2)
        }
        GridRow {
          Rectangle().frame(width: 40, height: 20)
          Rectangle().frame(width: 40, height: 20)
        }
      }
    )
    #expect(rendered.contains("left: 0px;"), "the spanning cell starts at the first column")
    #expect(rendered.contains("width: 100px;"), "the spanning cell keeps its 100pt width")
    #expect(rendered.contains("left: 3px;"), "the 40pt cell is centred in its 46pt column")
    #expect(rendered.contains("left: 57px;"), "the second column starts after the 46pt first column and the gap, centred")
  }

  @Test func columnWidthsDoNotDependOnTheOrderOfTheRows() {
    // The 80pt and 10pt cells size their columns first; the 100pt spanning cell then widens both by 5pt: [85, 15].
    let spanningFirst = StaticHTMLFiberRenderer().render(
      GridLayout(horizontalSpacing: 0, verticalSpacing: 0) {
        GridRow { Rectangle().frame(width: 100, height: 20).gridCellColumns(2) }
        GridRow {
          Rectangle().frame(width: 80, height: 20)
          Rectangle().frame(width: 10, height: 20)
        }
      }
    )
    let spanningLast = StaticHTMLFiberRenderer().render(
      GridLayout(horizontalSpacing: 0, verticalSpacing: 0) {
        GridRow {
          Rectangle().frame(width: 80, height: 20)
          Rectangle().frame(width: 10, height: 20)
        }
        GridRow { Rectangle().frame(width: 100, height: 20).gridCellColumns(2) }
      }
    )
    for rendered in [spanningFirst, spanningLast] {
      #expect(rendered.contains("left: 87.5px;"), "the 10pt cell is centred in the 15pt column that starts at 85pt")
      #expect(rendered.contains("left: 2.5px;"), "the 80pt cell is centred in the 85pt column")
    }
  }

  @Test func horizontallyUnsizedCellFillsItsSlotFromItsStart() {
    // The first row makes the column 100pt wide; the unsized cell takes the whole slot, so it starts at the column.
    let rendered = StaticHTMLFiberRenderer().render(
      GridLayout(horizontalSpacing: 0, verticalSpacing: 0) {
        GridRow { Rectangle().frame(width: 100, height: 20) }
        GridRow { Color.orange.frame(height: 6).gridCellUnsizedAxes(.horizontal) }
      }
    )
    let lefts = rendered.components(separatedBy: "left: ").dropFirst().map { $0.prefix(while: { $0 != ";" }) }
    #expect(!lefts.isEmpty)
    #expect(lefts.allSatisfy { $0 == "0px" }, "every cell starts at the column, got \(lefts)")
  }

  // MARK: ToolbarItemPlacement.bottomBar and ShapeStyle.bar

  @Test func bottomBarItemsLeaveTheTopBarAndSitAAtTheFootOfTheScreen() {
    let screen = NavigationStack {
      Text("Body")
        .toolbar {
          ToolbarItem(placement: .navigationBarTrailing) { Text("Edit") }
          ToolbarItemGroup(placement: .bottomBar) { Text("Share") }
        }
    }
    let rendered = html(screen)
    let bottomStart = rendered.range(of: "navigation-bottom-bar")
    #expect(bottomStart != nil, "a bottom bar holds the bottom item")
    guard let bottomStart else { return }
    let bodyPosition = rendered.range(of: "Body")?.lowerBound
    let sharePosition = rendered.range(of: "Share")?.lowerBound
    #expect(sharePosition.map { $0 > bottomStart.lowerBound } == true, "Share is inside the bottom bar")
    #expect(bodyPosition.map { $0 < bottomStart.lowerBound } == true, "the bottom bar follows the screen content")
    #expect(rendered.contains("Edit"), "the top item stays in the top bar")
    #expect(ToolbarItemPlacement.bottomBar.rawValue == "bottom-bar")
  }

  @Test func bottomBarItemsStayWhenTheNavigationBarIsHidden() {
    let screen = NavigationStack {
      Text("Body")
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
          ToolbarItem(placement: .navigationBarTrailing) { Text("Edit") }
          ToolbarItemGroup(placement: .bottomBar) { Text("Share") }
        }
    }
    let rendered = html(screen)
    #expect(rendered.contains("navigation-bottom-bar"), "the bottom bar outlives the hidden navigation bar")
    #expect(rendered.contains("Share"))
    #expect(!rendered.contains("Edit"), "the top items go with the hidden bar")
  }

  @Test func barMaterialIsAShapeStyleMaterial() {
    let material: Material = .bar
    #expect(material._swiftUIWebCSSValue == Material.regular._swiftUIWebCSSValue)
    #expect(material._swiftUIWebCSSValue.contains("Canvas 58%"))
    let styled = html(Text("Toolbar").background(.bar))
    #expect(styled.contains("Canvas 58%"))
  }

  // MARK: OpenURLAction.Result.systemAction

  @Test func systemActionOpensTheURLItWasGiven() {
    var opened: [String] = []
    defer { _OpenURLSystem.open = { _ in } }
    _OpenURLSystem.open = { opened.append($0.absoluteString) }
    let target = URL(string: "https://target.example/page")!
    let requested = URL(string: "https://requested.example/")!

    let redirected = OpenURLAction { _ in .systemAction(target) }
    redirected(requested)
    #expect(opened == ["https://target.example/page"])

    let defaulted = OpenURLAction { _ in .systemAction }
    defaulted(requested)
    #expect(opened == ["https://target.example/page", "https://requested.example/"])

    let handled = OpenURLAction { _ in .handled }
    handled(requested)
    let discarded = OpenURLAction { _ in .discarded }
    discarded(requested)
    #expect(opened.count == 2, "handled and discarded results do not open anything")
  }

  // MARK: @AppStorage initializers

  @Test func appStorageDeclarationsStoreAndReadBackEveryAppleInitializer() {
    installStorage()
    let view = GapStorageDeclarations()
    #expect(view.airplane == false && view.textScale == 1.0 && view.appearance == "dark")
    #expect(view.unit == .fahrenheit && view.level == .low)
    #expect(view.link.absoluteString == "https://example.com")
    #expect(view.blob.isEmpty)
    #expect(view.optionalUnit == nil && view.optionalLevel == nil && view.optionalLink == nil)

    let store = UserDefaults.standard
    let units = AppStorage(wrappedValue: GapStorageUnit.celsius, "gap.units.round", store: store)
    units.wrappedValue = .fahrenheit
    #expect(values["gap.units.round"] == "F", "a String raw value is stored as the raw value")
    #expect(AppStorage(wrappedValue: GapStorageUnit.celsius, "gap.units.round", store: store).wrappedValue == .fahrenheit)

    let levels = AppStorage(wrappedValue: GapStorageLevel.low, "gap.levels.round", store: store)
    levels.wrappedValue = .high
    #expect(values["gap.levels.round"] == "2", "an Int raw value is stored as the raw value")
    #expect(AppStorage(wrappedValue: GapStorageLevel.low, "gap.levels.round", store: store).wrappedValue == .high)

    let link = AppStorage(wrappedValue: URL(string: "https://a.example")!, "gap.links.round", store: store)
    link.wrappedValue = URL(string: "https://b.example/x")!
    #expect(values["gap.links.round"] == "https://b.example/x")
    #expect(AppStorage(wrappedValue: URL(string: "https://a.example")!, "gap.links.round", store: store).wrappedValue.absoluteString == "https://b.example/x")

    let blob = AppStorage(wrappedValue: Data(), "gap.blobs.round", store: store)
    blob.wrappedValue = Data([0x01, 0x02, 0x03])
    #expect(values["gap.blobs.round"] == "AQID", "Data is kept as base64 text")
    #expect(AppStorage(wrappedValue: Data(), "gap.blobs.round", store: store).wrappedValue == Data([0x01, 0x02, 0x03]))

    let optionalLevel = AppStorage<GapStorageLevel?>("gap.optional.level", store: store)
    optionalLevel.wrappedValue = .high
    #expect(values["gap.optional.level"] == "2")
    #expect(AppStorage<GapStorageLevel?>("gap.optional.level", store: store).wrappedValue == .high)
    optionalLevel.wrappedValue = nil
    #expect(values["gap.optional.level"] == nil, "assigning nil removes the key")

    let optionalLink = AppStorage<URL?>("gap.optional.link", store: store)
    optionalLink.wrappedValue = URL(string: "https://c.example")!
    #expect(values["gap.optional.link"] == "https://c.example")
    optionalLink.wrappedValue = nil
    #expect(values["gap.optional.link"] == nil)

    let optionalUnit = AppStorage<GapStorageUnit?>("gap.optional.unit", store: store)
    optionalUnit.wrappedValue = .celsius
    #expect(values["gap.optional.unit"] == "C")
  }

  // MARK: AttributedString inlinePresentationIntent

  @Test func markdownRunsCarryTheirInlinePresentationIntent() throws {
    let text = try AttributedString(markdown: "*a* **b** `c` ~~d~~ e")
    var intents: [(String, InlinePresentationIntent)] = []
    for run in text.runs {
      guard let intent = run.inlinePresentationIntent, !intent.isEmpty else { continue }
      let range = run.range
      intents.append((String(text[range].characters), intent))
    }
    #expect(intents.count == 4)
    #expect(intents.map { $0.0 } == ["a", "b", "c", "d"])
    #expect(intents[0].1 == [.emphasized])
    #expect(intents[1].1 == [.stronglyEmphasized])
    #expect(intents[2].1 == [.code])
    #expect(intents[3].1 == [.strikethrough])
    let plain = text.runs.last
    #expect((plain?.inlinePresentationIntent ?? []).isEmpty, "unmarked text has no intent")
  }

  @Test func nestedMarkdownEmphasisCombinesIntents() throws {
    let text = try AttributedString(markdown: "**bold *both***")
    let both = text.runs.compactMap { $0.inlinePresentationIntent }.first { $0.contains(.emphasized) }
    #expect(both == [.emphasized, .stronglyEmphasized])
  }

  // MARK: Image: Transferable

  @Test func pickedBytesImportAsAnImageShownFromADataURL() async throws {
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    let image: Image = try await Image.importing(data: png, contentType: .png)
    let rendered = html(image)
    #expect(rendered.contains("src=\"data:image/png;base64,iVBORw0KGgo=\""))
    #expect(Image.importedContentTypes().contains(.image))
  }

  // MARK: TextField(axis: .vertical) with a line-limit range

  @Test func multilineFieldGrowsBetweenTheLineLimitsOfARange() {
    var draft = ""
    let field = TextField("Message", text: Binding(get: { draft }, set: { draft = $0 }), axis: .vertical)
      .lineLimit(1...5)
    let node = allNodes(FiberTree(field).renderNode).first { $0.attributes["data-control-kind"] == "text-field-multiline" }
    #expect(node?.attributes["rows"] == "1")
    #expect(node?.styles["--lines-min"] == "1")
    #expect(node?.styles["--lines-max"] == "5")
    #expect(node?.attributes["data-lines-min"] == "1" && node?.attributes["data-lines-max"] == "5")
    #expect(node?.styles["field-sizing"] == "content")
  }

  @Test func multilineFieldWithAPartialRangeKeepsItsMinimumOnly() {
    var draft = ""
    let field = TextField("Message", text: Binding(get: { draft }, set: { draft = $0 }), axis: .vertical)
      .lineLimit(2...)
    let node = allNodes(FiberTree(field).renderNode).first { $0.attributes["data-control-kind"] == "text-field-multiline" }
    #expect(node?.attributes["rows"] == "2")
    #expect(node?.styles["--lines-max"] == nil && node?.attributes["data-lines-max"] == nil, "a partial range from below has no maximum")
    #expect(node?.styles["field-sizing"] == "content", "the field grows with its text instead of scrolling at its minimum")
    let capped = TextField("Message", text: Binding(get: { draft }, set: { draft = $0 }), axis: .vertical)
      .lineLimit(...3)
    let cappedNode = allNodes(FiberTree(capped).renderNode).first { $0.attributes["data-control-kind"] == "text-field-multiline" }
    #expect(cappedNode?.styles["--lines-max"] == "3")
    #expect(cappedNode?.styles["--lines-min"] == "1", "a maximum alone starts the field at one line, not at the stylesheet's base height")
  }
}
