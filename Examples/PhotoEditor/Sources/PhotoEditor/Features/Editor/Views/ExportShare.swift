import SwiftUI

/// Shares the last export through the system share sheet.
struct ExportShare: View {
    let image: Image

    var body: some View {
        ShareLink(item: image, preview: SharePreview(Strings.Editor.sharePreview, image: image))
            .accessibilityIdentifier("share")
    }
}
