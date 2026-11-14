import SwiftUI

/// The fixture page: the image tiles, then the keyframe tiles, in the reference's order.
struct FixturesPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GallerySection(title: Strings.Gallery.imagesHeader, entries: GalleryCatalog.images)
            GallerySection(title: Strings.Gallery.keyframesHeader, entries: GalleryCatalog.keyframes)
        }
    }
}
