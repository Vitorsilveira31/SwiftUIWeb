import SwiftUI

/// One labelled tile: the 64x64 picture in its grey tile box, with its caption below.
struct GalleryCell: View {
    let entry: GalleryEntry

    var body: some View {
        VStack(spacing: 6) {
            GalleryTile(kind: entry.tile)
                .frame(width: 64, height: 64)
                .background(Color.gray.opacity(0.12))
                .clipped()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(entry.label)
                .accessibilityIdentifier(entry.testId)
            Text(entry.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 96, height: 30, alignment: .top)
        }
        .frame(width: 96)
    }
}
