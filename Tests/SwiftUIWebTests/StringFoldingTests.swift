import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

/// `String.folding(options:locale:)` for the browser: ASCII is folded in
/// Swift and everything else by the browser (see `Tools/test-text-format.mjs`
/// for the folding itself), so search code written against Foundation behaves
/// the same in Embedded builds.
@Suite(.serialized)
@MainActor
struct StringFoldingTests {
  @Test
  func foldsASCIIWithoutTheBrowser() {
    #expect(_swiftUIWebFoldText("Mare de SANGUE", diacritics: true, case: true) == "mare de sangue")
    #expect(_swiftUIWebFoldText("Mare de SANGUE", diacritics: false, case: true) == "mare de sangue")
    #expect(_swiftUIWebFoldText("Mare de SANGUE", diacritics: true, case: false) == "Mare de SANGUE")
    #expect(_swiftUIWebFoldText("Mare", diacritics: false, case: false) == "Mare")
    #expect(_swiftUIWebFoldText("", diacritics: true, case: true) == "")
  }

  @Test
  func asksTheBrowserForEverythingElse() {
    var asked: [String] = []
    _TextHost.fold = { value, diacritics, foldsCase in
      asked.append("\(value) \(diacritics) \(foldsCase)")
      return "folded"
    }
    defer { _TextHost.fold = nil }
    #expect(_swiftUIWebFoldText("Maré", diacritics: true, case: true) == "folded")
    #expect(_swiftUIWebFoldText("Mare", diacritics: true, case: true) == "mare")
    #expect(_swiftUIWebFoldText("Maré", diacritics: false, case: false) == "Maré")
    #expect(asked == ["Maré true true"])
  }

  @Test
  func leavesNonASCIITextAloneWhenNoBrowserAnswers() {
    #expect(_swiftUIWebFoldText("Maré", diacritics: true, case: true) == "Maré")
  }
}
