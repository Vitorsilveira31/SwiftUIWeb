/// The current value of every knob of one component.
struct CatalogKnobValues {
  private var bools: [String: Bool] = [:]
  private var numbers: [String: Double] = [:]
  private var texts: [String: String] = [:]
  private var choices: [String: Int] = [:]

  /// Every knob at its default.
  init(defaults knobs: [CatalogKnob]) {
    for knob in knobs {
      switch knob.kind {
      case .toggle(let value): bools[knob.id] = value
      case .choice(_, let index): choices[knob.id] = index
      case .number(_, _, let value): numbers[knob.id] = value
      case .text(let value): texts[knob.id] = value
      }
    }
  }

  func bool(_ id: String) -> Bool { bools[id] ?? false }
  func number(_ id: String) -> Double { numbers[id] ?? 0 }
  func text(_ id: String) -> String { texts[id] ?? "" }
  func choiceIndex(_ id: String) -> Int { choices[id] ?? 0 }

  /// The token a choice knob is on, out of the options the recipe declared.
  func choice(_ id: String, in options: [String]) -> String {
    let index = choiceIndex(id)
    return options.indices.contains(index) ? options[index] : (options.first ?? "")
  }

  mutating func set(_ id: String, bool value: Bool) { bools[id] = value }
  mutating func set(_ id: String, number value: Double) { numbers[id] = value }
  mutating func set(_ id: String, text value: String) { texts[id] = value }
  mutating func set(_ id: String, choiceIndex value: Int) { choices[id] = value }
}
