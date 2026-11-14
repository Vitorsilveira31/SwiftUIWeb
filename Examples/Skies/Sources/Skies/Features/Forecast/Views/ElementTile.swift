import SwiftUI

// One reading in the details grid: a labelled symbol over its value.
struct ElementTile: View {
    let title: String
    let symbol: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .serif))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.10)))
    }
}
