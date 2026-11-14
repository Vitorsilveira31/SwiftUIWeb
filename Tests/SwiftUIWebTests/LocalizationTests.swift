import Testing
@_spi(Renderer) @_spi(Generated) import SwiftUIWebCore
@_spi(Renderer) @_spi(Generated) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber
import SwiftUIWeb

/// The localization table is process-global, so the tests share one serialized suite.
@Suite(.serialized)
@MainActor
struct LocalizationTests {
  private func withTable(_ body: () -> Void) {
    LocalizationTable.removeAll()
    LocalizationTable.developmentLanguage = "pt-BR"
    LocalizationTable.preferredLanguage = nil
    LocalizationTable.register(language: "pt-BR", entries: [
      "Criar obra": .text("Criar obra"),
      "%lld obras": .plural(["one": "%lld obra", "other": "%lld obras"]),
      "Olá, %@! Você tem %lld itens": .text("Olá, %@! Você tem %lld itens"),
      "100%% pronto": .text("100%% pronto"),
      "%2$@ antes de %1$@": .text("%2$@ antes de %1$@")
    ])
    LocalizationTable.register(language: "en", entries: [
      "Criar obra": .text("Create work"),
      "%lld obras": .plural(["one": "%lld work", "other": "%lld works"]),
      "Olá, %@! Você tem %lld itens": .text("Hello, %@! You have %lld items")
    ])
    body()
    LocalizationTable.removeAll()
    LocalizationTable.preferredLanguage = nil
    LocalizationTable.developmentLanguage = "en"
  }

  private func text(_ view: some View) -> String {
    StaticHTMLFiberRenderer().render(view)
  }

  @Test
  func aLiteralKeyIsTranslatedForThePreferredLanguageAndFallsBack() {
    withTable {
      #expect(LocalizedStringKey("Criar obra").resolved == "Criar obra")
      LocalizationTable.preferredLanguage = "en_US"
      #expect(LocalizedStringKey("Criar obra").resolved == "Create work", "en_US falls back to en")
      #expect(LocalizedStringKey("Sem tradução").resolved == "Sem tradução", "a missing key shows itself")
      LocalizationTable.preferredLanguage = "es"
      #expect(LocalizedStringKey("Criar obra").resolved == "Criar obra", "an unknown language uses the development language")
    }
  }

  @Test
  func interpolationBuildsAFormatKeyAndSubstitutesArguments() {
    withTable {
      let name = "Vitor", count = 3
      let key: LocalizedStringKey = "Olá, \(name)! Você tem \(count) itens"
      #expect(key.key == "Olá, %@! Você tem %lld itens")
      #expect(key.resolved == "Olá, Vitor! Você tem 3 itens")
      LocalizationTable.preferredLanguage = "en"
      #expect(key.resolved == "Hello, Vitor! You have 3 items")
      let percent: LocalizedStringKey = "100% pronto \(1)"
      #expect(percent.key == "100%% pronto %lld")
      #expect(LocalizedStringKey("100%% pronto").resolved == "100%% pronto", "no arguments: the value is returned as stored")
    }
  }

  @Test
  func pluralFormsFollowTheFirstIntegerArgument() {
    withTable {
      func resolve(_ n: Int) -> String { LocalizedStringKey("\(n) obras").resolved }
      #expect(resolve(0) == "0 obra", "Portuguese treats zero as singular")
      #expect(resolve(1) == "1 obra")
      #expect(resolve(2) == "2 obras")
      LocalizationTable.preferredLanguage = "en"
      #expect(resolve(0) == "0 works")
      #expect(resolve(1) == "1 work")
    }
  }

  @Test
  func anExplicitLanguageOverridesThePreferredOneAndZeroCanHaveItsOwnForm() {
    withTable {
      LocalizationTable.register(language: "pt-BR", entries: ["%lld itens": .plural(["zero": "nenhum item", "one": "%lld item", "other": "%lld itens"])])
      let key = LocalizedStringKey("\(0) itens")
      #expect(LocalizationTable.resolve(key, language: "pt_BR") == "nenhum item")
      #expect(LocalizationTable.resolve(LocalizedStringKey("\(1) itens"), language: "pt-BR") == "1 item")
      LocalizationTable.preferredLanguage = "en"
      #expect(LocalizationTable.resolve(LocalizedStringKey("Criar obra"), language: "pt-BR") == "Criar obra", "the explicit language wins")
      #expect(LocalizationTable.resolve(LocalizedStringKey("Criar obra")) == "Create work")
    }
  }

  @Test
  func positionalSpecifiersReorderArguments() {
    withTable {
      let key = LocalizedStringKey(key: "%2$@ antes de %1$@", arguments: [.string("A"), .string("B")])
      #expect(key.resolved == "B antes de A")
    }
  }

  @Test
  func textLooksLiteralsUpButShowsStringVariablesVerbatim() {
    withTable {
      LocalizationTable.preferredLanguage = "en"
      #expect(text(Text("Criar obra")).contains("Create work"))
      let variable = "Criar obra"
      #expect(text(Text(variable)).contains("Criar obra"), "a String variable is not a key")
      #expect(text(Text(verbatim: "Criar obra")).contains("Criar obra"))
      let count = 2
      #expect(text(Text("\(count) obras")).contains("2 works"))
    }
  }

  @Test
  func controlsTakeLocalizedKeysForLiteralsAndStringsForVariables() {
    withTable {
      LocalizationTable.preferredLanguage = "en"
      #expect(text(Button("Criar obra") {}).contains("Create work"))
      let variable = "Criar obra"
      #expect(text(Button(variable) {}).contains("Criar obra"))
      #expect(text(Label("Criar obra", systemImage: "plus")).contains("Create work"))
    }
  }

  @Test
  func stringLocalizedUsesTheSameTable() {
    withTable {
      LocalizationTable.preferredLanguage = "en"
      #expect(String(localized: "Criar obra") == "Create work")
      let n = 5
      #expect(String(localized: "\(n) obras") == "5 works")
    }
  }
}
