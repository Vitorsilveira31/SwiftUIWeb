import SwiftUI

struct ListItemBlockView: View {
    let depth: Int
    let marker: ListMarker
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ListMarkerView(marker: marker, depth: depth)
                .frame(minWidth: 26, alignment: .trailing)
            Text(MarkdownInlineStyler.styled(text))
                .foregroundStyle(isCheckedTask ? .secondary : .primary)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A nested list indents by its depth, so the markers line up under their parents.
        .padding(.leading, CGFloat(depth) * 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isCheckedTask: Bool {
        if case .task(checked: true) = marker { return true }
        return false
    }
}
