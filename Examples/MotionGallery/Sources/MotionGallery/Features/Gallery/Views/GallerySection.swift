import SwiftUI

/// A headed block of tiles laid out in adaptive columns.
struct GallerySection: View {
    let title: String
    let entries: [GalleryEntry]
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(entries) { entry in
                    GalleryCell(entry: entry)
                }
            }
        }
    }
}
