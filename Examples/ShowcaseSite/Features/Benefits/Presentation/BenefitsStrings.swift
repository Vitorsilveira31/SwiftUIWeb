/// The words of the benefits page.
enum BenefitsStrings {
  static func title(_ language: SiteLanguage) -> String {
    language.pick(pt: "Benefícios", en: "Benefits")
  }

  static func lead(_ language: SiteLanguage) -> String {
    language.pick(
      pt: "O que muda no dia a dia de quem escreve SwiftUI e publica para a web.",
      en: "What changes day to day for someone who writes SwiftUI and ships to the web."
    )
  }

  static func all(_ language: SiteLanguage) -> [BenefitVO] {
    [
      BenefitVO(
        id: "one-language",
        symbol: "chevron.left.forwardslash.chevron.right",
        title: language.pick(pt: "Uma linguagem, um modelo", en: "One language, one model"),
        detail: language.pick(
          pt: "Modelos, validações e regras de negócio são os mesmos no iOS, no iPadOS e na web.",
          en: "Models, validation and business rules are the same on iOS, iPadOS and the web."
        )
      ),
      BenefitVO(
        id: "swiftui",
        symbol: "square.grid.2x2",
        title: language.pick(pt: "O SwiftUI que você já conhece", en: "The SwiftUI you already know"),
        detail: language.pick(
          pt: "View, State, NavigationStack, List: os mesmos nomes e formatos. A API da Apple é o contrato.",
          en: "View, State, NavigationStack, List: the same names and shapes. Apple's API is the contract."
        )
      ),
      BenefitVO(
        id: "browser",
        symbol: "globe",
        title: language.pick(pt: "O navegador faz o que faz melhor", en: "The browser does what it does best"),
        detail: language.pick(
          pt: "Texto, fontes, rolagem, entrada e acessibilidade são recursos nativos do navegador, não reimplementações.",
          en: "Text, fonts, scrolling, input and accessibility are native browser features, not re-implementations."
        )
      ),
      BenefitVO(
        id: "responsive",
        symbol: "gauge.with.dots.needle.67percent",
        title: language.pick(pt: "Responsivo por padrão", en: "Responsive by default"),
        detail: language.pick(
          pt: "O Swift roda em um Web Worker, então trabalho pesado não trava a digitação nem a rolagem.",
          en: "Swift runs in a Web Worker, so heavy work does not block typing or scrolling."
        )
      ),
      BenefitVO(
        id: "incremental",
        symbol: "arrow.triangle.2.circlepath",
        title: language.pick(pt: "Atualizações pequenas", en: "Small updates"),
        detail: language.pick(
          pt: "Uma mudança envia um patch binário compacto, só com as views que mudaram.",
          en: "A change sends a compact binary patch with only the views that changed."
        )
      ),
      BenefitVO(
        id: "testable",
        symbol: "checkmark.shield",
        title: language.pick(pt: "Testável sem navegador", en: "Testable without a browser"),
        detail: language.pick(
          pt: "Modelos, view models e casos de uso rodam no swift test comum. Os testes de navegador cobrem o resto.",
          en: "Models, view models and use cases run in plain swift test. Browser tests cover the rest."
        )
      ),
    ]
  }
}
