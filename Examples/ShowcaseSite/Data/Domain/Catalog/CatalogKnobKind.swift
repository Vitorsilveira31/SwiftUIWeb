/// What a knob changes and the values it accepts.
enum CatalogKnobKind {
  case toggle(defaultValue: Bool)
  /// One of a fixed list of tokens, as they are written in code (`title`, `bordered`).
  case choice(options: [String], defaultIndex: Int)
  case number(range: ClosedRange<Double>, step: Double, defaultValue: Double)
  case text(defaultValue: String)
}
