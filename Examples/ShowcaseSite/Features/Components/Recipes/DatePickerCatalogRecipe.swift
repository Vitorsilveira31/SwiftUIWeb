import SwiftUIWeb

enum DatePickerCatalogRecipe {
  static let styles = ["automatic", "compact", "graphical", "field", "stepperField"]
  static let componentOptions = ["date", "hourAndMinute", "both"]

  /// The fields a `displayedComponents` option shows, as the view takes them.
  static func displayed(_ token: String) -> DatePickerComponents {
    switch token {
    case "hourAndMinute": return [.hourAndMinute]
    case "both": return [.date, .hourAndMinute]
    default: return [.date]
    }
  }

  /// The same fields, written as the code writes them.
  static func displayedCode(_ token: String) -> String {
    switch token {
    case "hourAndMinute": return "[.hourAndMinute]"
    case "both": return "[.date, .hourAndMinute]"
    default: return "[.date]"
    }
  }

  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "datepicker",
      name: "DatePicker",
      summary: CatalogText(
        pt: "Escolhe uma data, uma hora ou as duas.",
        en: "Picks a date, a time, or both."
      ),
      category: .controls,
      covers: ["DatePicker"],
      knobs: [
        CatalogKnob(id: "style", label: CatalogText(pt: "Estilo", en: "Style"), kind: .choice(options: styles, defaultIndex: 1)),
        CatalogKnob(id: "components", label: CatalogText(pt: "Campos", en: "Fields"), kind: .choice(options: componentOptions, defaultIndex: 0)),
      ],
      preview: { AnyView(DatePickerCatalogPreview(values: $0)) },
      code: { values in
        let components = displayedCode(values.choice("components", in: componentOptions))
        var code = CatalogCodeBuilder("DatePicker(\"Date\", selection: $date, displayedComponents: \(components))")
        code.modifier("datePickerStyle(.\(values.choice("style", in: styles)))")
        return code.text
      }
    )
  }
}
