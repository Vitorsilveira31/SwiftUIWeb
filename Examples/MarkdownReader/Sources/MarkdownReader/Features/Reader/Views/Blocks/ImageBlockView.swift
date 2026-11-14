import SwiftUI

/// An image the reader does not load: a box with the alt text and the source path.
struct ImageBlockView: View {
    let alt: String
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(alt.isEmpty ? Strings.ImageBlock.untitled : alt)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 130)
            .padding()
            .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            Text(source)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
