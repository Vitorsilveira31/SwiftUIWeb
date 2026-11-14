/// The words of the purpose page.
enum PurposeStrings {
  static func title(_ language: SiteLanguage) -> String {
    language.pick(pt: "Para que serve", en: "What it is for")
  }

  static func eyebrow(_ language: SiteLanguage) -> String {
    language.pick(pt: "Prévia · Swift compilado para WebAssembly", en: "Preview · Swift compiled to WebAssembly")
  }

  static func headline(_ language: SiteLanguage) -> String {
    language.pick(pt: "SwiftUI,", en: "SwiftUI,")
  }

  static func headlineAccent(_ language: SiteLanguage) -> String {
    language.pick(pt: "agora na web.", en: "on the web.")
  }

  static func ctaStart(_ language: SiteLanguage) -> String {
    language.pick(pt: "Começar", en: "Get started")
  }

  static func ctaComponents(_ language: SiteLanguage) -> String {
    language.pick(pt: "Ver componentes", en: "Browse components")
  }

  static func demoCode(_ language: SiteLanguage) -> String {
    language.pick(pt: "O código", en: "The code")
  }

  static func demoLive(_ language: SiteLanguage) -> String {
    language.pick(pt: "Rodando agora, na sua tela", en: "Running right now, on your screen")
  }

  static func lead(_ language: SiteLanguage) -> String {
    language.pick(
      pt: "O SwiftUIWeb é para quem conhece SwiftUI e precisa de um app web de verdade.",
      en: "SwiftUIWeb is for people who know SwiftUI and need a real web app."
    )
  }

  static func fitsHeading(_ language: SiteLanguage) -> String {
    language.pick(pt: "Onde encaixa bem", en: "Where it fits")
  }

  static func limitsHeading(_ language: SiteLanguage) -> String {
    language.pick(pt: "Onde ainda não encaixa", en: "Where it does not fit yet")
  }

  static func fits(_ language: SiteLanguage) -> [PurposeItemVO] {
    [
      PurposeItemVO(
        id: "tools",
        title: language.pick(pt: "Ferramentas internas e painéis", en: "Internal tools and dashboards"),
        detail: language.pick(
          pt: "Telas cheias de formulários, tabelas e listas, que mudam o tempo todo e precisam de muita lógica de domínio.",
          en: "Screens full of forms, tables and lists that change all the time and carry a lot of domain logic."
        )
      ),
      PurposeItemVO(
        id: "ios-web",
        title: language.pick(pt: "Apps que já existem no iOS e no iPadOS", en: "Apps that already exist on iOS and iPadOS"),
        detail: language.pick(
          pt: "A mesma tela, a mesma navegação e o mesmo estado em Xcode e no navegador, com o ponto de entrada de cada plataforma separado.",
          en: "The same screen, navigation and state in Xcode and in the browser, with each platform's entry point kept apart."
        )
      ),
      PurposeItemVO(
        id: "swift-team",
        title: language.pick(pt: "Equipes em que Swift é a língua comum", en: "Teams where Swift is the common language"),
        detail: language.pick(
          pt: "Modelos, validações e regras ficam em um lugar só e rodam nos testes nativos, sem navegador.",
          en: "Models, validation and rules live in one place and run in native tests, no browser needed."
        )
      ),
    ]
  }

  static func limits(_ language: SiteLanguage) -> [PurposeItemVO] {
    [
      PurposeItemVO(
        id: "seo",
        title: language.pick(pt: "Páginas que precisam ser indexadas", en: "Pages that must be indexed"),
        detail: language.pick(
          pt: "O app é desenhado no navegador. Ainda não há renderização no servidor.",
          en: "The app is drawn in the browser. There is no server-side rendering yet."
        )
      ),
      PurposeItemVO(
        id: "tiny",
        title: language.pick(pt: "Páginas muito pequenas", en: "Very small pages"),
        detail: language.pick(
          pt: "Se o conteúdo é menor que o WebAssembly que o carrega, HTML puro é a ferramenta certa.",
          en: "If the content is smaller than the WebAssembly that loads it, plain HTML is the right tool."
        )
      ),
      PurposeItemVO(
        id: "api",
        title: language.pick(pt: "APIs do SwiftUI ainda não implementadas", en: "SwiftUI APIs not implemented yet"),
        detail: language.pick(
          pt: "A API pública é acompanhada contra a da Apple, e o que falta fica registrado em vez de escondido.",
          en: "The public API is tracked against Apple's, and what is missing is recorded rather than hidden."
        )
      ),
    ]
  }
}
