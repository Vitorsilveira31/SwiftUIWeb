import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
import SwiftUIWeb
@_spi(Generated) import SwiftUIWeb

/// Entries registered as one sorted `StaticString`, the form `Tools/compile-strings.mjs` emits.
/// Part of `LocalizationTests` because the table is process-global and only one suite may touch it at a time.
extension LocalizationTests {
  /// Sorted by the UTF-8 bytes of the key: space, `%`, `O`, `a`, `ab`, `z`.
  private static let english: StaticString = """
     leading\u{3} spaced\u{4}\
    %lld obras\u{3}\u{1}one\u{2}%lld work\u{1}other\u{2}%lld works\u{4}\
    Olá\u{3}Hello\u{4}\
    a\u{3}A\u{4}\
    ab\u{3}AB\u{4}\
    z\u{3}Z
    """

  private func withSortedTable(_ body: () -> Void) {
    LocalizationTable.removeAll()
    LocalizationTable.developmentLanguage = "pt-BR"
    LocalizationTable.preferredLanguage = "en"
    LocalizationTable.register(language: "en", sorted: Self.english)
    body()
    LocalizationTable.removeAll()
    LocalizationTable.preferredLanguage = nil
    LocalizationTable.developmentLanguage = "en"
  }

  @Test
  func everyRecordIsFoundIncludingPrefixesAndTheLastRecord() {
    withSortedTable {
      #expect(LocalizedStringKey(" leading").resolved == " spaced")
      #expect(LocalizedStringKey("a").resolved == "A")
      #expect(LocalizedStringKey("ab").resolved == "AB")
      #expect(LocalizedStringKey("Olá").resolved == "Hello")
      #expect(LocalizedStringKey("z").resolved == "Z")
    }
  }

  @Test
  func keysAreComparedByBytesSoADecomposedAccentIsADifferentKey() {
    withSortedTable {
      #expect(LocalizedStringKey("Ol\u{E1}").resolved == "Hello")
      #expect(LocalizedStringKey("Ola\u{301}").resolved == "Ola\u{301}", "no canonical equivalence, as documented in MIGRATION.md")
      #expect(LocalizedStringKey("olá").resolved == "olá", "case is not folded either")
    }
  }

  @Test
  func aMissingKeyFallsBackToTheKeyAndAPrefixIsNotAMatch() {
    withSortedTable {
      #expect(LocalizedStringKey("abc").resolved == "abc")
      #expect(LocalizedStringKey("b").resolved == "b")
      #expect(LocalizedStringKey("").resolved == "")
    }
  }

  @Test
  func pluralFormsAreDecodedFromTheStoredValue() {
    withSortedTable {
      #expect(LocalizedStringKey("\(1) obras").resolved == "1 work")
      #expect(LocalizedStringKey("\(3) obras").resolved == "3 works")
    }
  }

  @Test
  func dictionaryEntriesTakePrecedenceOverTheSortedBlob() {
    withSortedTable {
      LocalizationTable.register(language: "en", entries: ["a": .text("override")])
      #expect(LocalizedStringKey("a").resolved == "override")
      #expect(LocalizedStringKey("ab").resolved == "AB")
    }
  }
}
