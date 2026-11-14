import SwiftUIWeb

/// The live `DatePicker` of the catalog, in the style and with the fields the knobs pick.
struct DatePickerCatalogPreview: View {
  let values: CatalogKnobValues
  @State private var date = Date()

  var body: some View {
    VStack {
      switch values.choice("style", in: DatePickerCatalogRecipe.styles) {
      case "compact":
        content.datePickerStyle(.compact)
      case "graphical":
        content.datePickerStyle(.graphical)
      case "field":
        content.datePickerStyle(.field)
      case "stepperField":
        content.datePickerStyle(.stepperField)
      default:
        content.datePickerStyle(.automatic)
      }
    }
    .frame(maxWidth: 360)
  }

  private var content: DatePickerCatalogContent {
    DatePickerCatalogContent(
      components: DatePickerCatalogRecipe.displayed(values.choice("components", in: DatePickerCatalogRecipe.componentOptions)),
      date: $date
    )
  }
}
