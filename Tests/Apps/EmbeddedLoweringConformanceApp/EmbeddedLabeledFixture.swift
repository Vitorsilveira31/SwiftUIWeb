import SwiftUIWeb

/// LabeledContent rows: the label takes what the value leaves, the value is as wide as it wants within the row and no
/// narrower than its longest word. CSS layout must lay it out (`Tools/test-css-layout-fixtures-browser.mjs`).
struct EmbeddedLabeledFixture: View {
  let onDone: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button("Return to conformance app") { onDone() }
      LabeledContent("Name", value: "Food Truck")
      LabeledContent("A label long enough to give way to its value", value: "Value")
      LabeledContent("Status") { Text("A value long enough to wrap inside the row it is given") }
      LabeledContent("Count") { Text("12").bold() }
      HStack {
        LabeledContent("In a stack", value: "beside")
        Text("sibling")
      }
    }
    .frame(width: 360)
    .padding(16)
  }
}
