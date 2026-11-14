import SwiftUIWeb

/// The `TextEditor` itself, with its own text state seeded from the initial text and a fixed height.
struct TextEditorCatalogContent: View {
  let height: Double
  @State private var text: String

  init(initialText: String, height: Double) {
    self.height = height
    _text = State(initialValue: initialText)
  }

  var body: some View {
    TextEditor(text: $text).frame(height: height)
  }
}
