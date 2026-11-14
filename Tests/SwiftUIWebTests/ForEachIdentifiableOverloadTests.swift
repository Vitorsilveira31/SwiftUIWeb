import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

/// SwiftUI identifies `Identifiable` elements by `id`, even when the element is
/// also `Hashable`; `ForEach(data)` must compile and use that identity.
@Suite
@MainActor
struct ForEachIdentifiableOverloadTests {
  private struct Option: Hashable, Identifiable {
    let id: String
    let title: String
  }

  @Test
  func hashableIdentifiableElementsUseTheirIdentifier() {
    let options = [Option(id: "story", title: "História"), Option(id: "comic", title: "Webtoon")]
    let node = ForEach(options) { option in Text(option.title) }._render(in: _RenderContext())

    let keys = node.children.compactMap { $0.key.map(fiberKeyDescription) }
    #expect(keys.count == 2)
    #expect(keys[0].contains("story"))
    #expect(!keys[0].contains("História"))
  }
}
