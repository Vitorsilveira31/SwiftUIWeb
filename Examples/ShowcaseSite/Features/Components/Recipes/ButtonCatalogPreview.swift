import SwiftUIWeb

/// The live `Button` of the catalog, in the style the knob picks; each tap is counted so the action is seen running.
struct ButtonCatalogPreview: View {
  let values: CatalogKnobValues
  @State private var taps = 0

  var body: some View {
    VStack(spacing: 8) {
      switch values.choice("style", in: ButtonCatalogRecipe.styles) {
      case "bordered":
        content.buttonStyle(.bordered)
      case "borderedProminent":
        content.buttonStyle(.borderedProminent)
      case "borderless":
        content.buttonStyle(.borderless)
      case "plain":
        content.buttonStyle(.plain)
      default:
        content.buttonStyle(.automatic)
      }
      Text("\(taps)").font(.caption).foregroundStyle(.secondary)
    }
  }

  private var content: ButtonCatalogContent {
    ButtonCatalogContent(
      title: values.text("title"),
      isDestructive: values.choice("role", in: ButtonCatalogRecipe.roles) == "destructive",
      isDisabled: values.bool("disabled"),
      taps: $taps
    )
  }
}
