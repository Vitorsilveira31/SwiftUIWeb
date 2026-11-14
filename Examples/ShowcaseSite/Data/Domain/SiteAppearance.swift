/// How the site picks its colors: the system's, or one of the two fixed.
enum SiteAppearance: String, CaseIterable, Hashable {
  case system
  case light
  case dark
}
