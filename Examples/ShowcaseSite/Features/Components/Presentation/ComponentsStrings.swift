/// The words of the components page.
enum ComponentsStrings {
  static func title(_ language: SiteLanguage) -> String {
    language.pick(pt: "Componentes", en: "Components")
  }

  static func lead(_ language: SiteLanguage) -> String {
    language.pick(
      pt: "Cada componente, ao vivo: mude os ajustes e a prévia e o código acompanham.",
      en: "Every component, live: change its settings and the preview and the code follow."
    )
  }

  static func searchPrompt(_ language: SiteLanguage) -> String {
    language.pick(pt: "Buscar componente", en: "Search components")
  }

  static func category(_ category: CatalogCategory, _ language: SiteLanguage) -> String {
    switch category {
    case .content: return language.pick(pt: "Conteúdo", en: "Content")
    case .controls: return language.pick(pt: "Controles", en: "Controls")
    case .layout: return language.pick(pt: "Layout", en: "Layout")
    case .collections: return language.pick(pt: "Coleções", en: "Collections")
    }
  }

  static func previewHeading(_ language: SiteLanguage) -> String {
    language.pick(pt: "Ao vivo", en: "Live")
  }

  static func knobsHeading(_ language: SiteLanguage) -> String {
    language.pick(pt: "Ajustes", en: "Adjust")
  }

  static func codeHeading(_ language: SiteLanguage) -> String {
    language.pick(pt: "Código", en: "Code")
  }

  static func reset(_ language: SiteLanguage) -> String {
    language.pick(pt: "Restaurar padrões", en: "Reset to defaults")
  }

  static func noResults(_ language: SiteLanguage) -> String {
    language.pick(pt: "Nenhum componente encontrado.", en: "No component found.")
  }

  static func pickPrompt(_ language: SiteLanguage) -> String {
    language.pick(pt: "Escolha um componente na lista.", en: "Pick a component from the list.")
  }
}
