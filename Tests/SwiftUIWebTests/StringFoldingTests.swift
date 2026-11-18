import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

/// `String.folding(options:locale:)`: ASCII is folded in Swift and everything
/// else by the browser (see `Tools/test-text-format.mjs` for the folding
/// itself) or, natively, by Swift as Foundation does, so search code written
/// against Foundation behaves the same in every build.
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
    let swiftFold = _TextHost.fold
    var asked: [String] = []
    _TextHost.fold = { value, diacritics, foldsCase in
      guard value == "Maré" else { return swiftFold?(value, diacritics, foldsCase) }
      asked.append("\(value) \(diacritics) \(foldsCase)")
      return "folded"
    }
    defer { _TextHost.fold = swiftFold }
    #expect(_swiftUIWebFoldText("Maré", diacritics: true, case: true) == "folded")
    #expect(_swiftUIWebFoldText("Mare", diacritics: true, case: true) == "mare")
    #expect(_swiftUIWebFoldText("Maré", diacritics: false, case: false) == "Maré")
    #expect(asked == ["Maré true true"])
  }

  /// Without a browser, Swift folds the text as Foundation does (`NativeTextFormattingTests` has the cases).
  @Test
  func foldsNonASCIITextWhenNoBrowserIsInstalled() {
    #expect(_swiftUIWebFoldText("Maré", diacritics: true, case: true) == "mare")
    #expect(_swiftUIWebFoldText("Telenovela · Suspense", diacritics: true, case: true) == "telenovela · suspense")
  }
}
