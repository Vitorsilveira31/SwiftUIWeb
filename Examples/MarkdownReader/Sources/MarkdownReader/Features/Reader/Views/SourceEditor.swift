import SwiftUI

/// The Source view: the document's Markdown as editable monospaced text.
/// Every edit re-parses the document.
struct SourceEditor: View {
    let text: Binding<String>

    var body: some View {
        TextEditor(text: text)
            .font(.system(.callout, design: .monospaced))
            .frame(height: 220)
            .padding(8)
            .accessibilityIdentifier("markdown-source")
    }
}
