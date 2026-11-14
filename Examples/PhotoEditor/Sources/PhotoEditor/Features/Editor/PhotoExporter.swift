import SwiftUI

/// Renders the cropped, edited photo at the export size: the same picture the stage shows, with its crop applied.
enum PhotoExporter {
    @MainActor
    static func render(_ source: PhotoSource, edit: Edit) -> Image? {
        let renderer = ImageRenderer(
            content: CroppedPhoto(source: source, edit: edit, stage: StageGeometry.exportSize)
        )
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { return nil }
        return Image(decorative: cgImage, scale: 1)
    }
}
