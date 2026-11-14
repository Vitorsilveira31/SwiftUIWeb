/// A piece of the catalog's own copy, written in both languages side by side.
struct CatalogText {
  let pt: String
  let en: String

  func resolved(_ language: SiteLanguage) -> String { language.pick(pt: pt, en: en) }
}
