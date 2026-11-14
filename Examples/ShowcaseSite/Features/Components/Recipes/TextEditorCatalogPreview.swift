import SwiftUIWeb

/// The live `TextEditor` of the catalog. Its text starts from the initial-text knob; changing that knob starts it again.
struct TextEditorCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    TextEditorCatalogContent(initialText: values.text("initial"), height: values.number("height"))
      .id(values.text("initial"))
      .frame(maxWidth: 360)
  }
}
