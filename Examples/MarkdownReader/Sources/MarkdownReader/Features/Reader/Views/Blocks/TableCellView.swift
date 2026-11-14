import SwiftUI

/// One cell of a table: its text, its column's alignment, and the header band.
struct TableCellView: View {
    let text: String
    let alignment: ColumnAlignment
    let isHeader: Bool

    var body: some View {
        Text(MarkdownInlineStyler.styled(text, font: isHeader ? .callout.bold() : .callout))
            .multilineTextAlignment(textAlignment)
            .frame(minWidth: 96, alignment: frameAlignment)
            .padding(8)
            .background(isHeader ? Color.gray.opacity(0.14) : Color.clear)
            .overlay(Rectangle().stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
    }

    private var textAlignment: TextAlignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}
