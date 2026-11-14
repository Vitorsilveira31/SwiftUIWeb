import SwiftUI

struct HeadingBlockView: View {
    let level: Int
    let text: String

    var body: some View {
        Text(MarkdownInlineStyler.styled(text, font: font))
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, level <= 2 ? 10 : 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var font: Font {
        switch level {
        case 1: return .system(.largeTitle, weight: .bold)
        case 2: return .system(.title, weight: .bold)
        case 3: return .system(.title2, weight: .bold)
        case 4: return .system(.title3, weight: .semibold)
        case 5: return .system(.headline)
        default: return .system(.subheadline, weight: .bold)
        }
    }
}
