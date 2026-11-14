import SwiftUI

/// The edit's crop of the stage, at the stage's own scale: what Export renders.
struct CroppedPhoto: View {
    let source: PhotoSource
    let edit: Edit
    let stage: CGSize

    var body: some View {
        let crop = edit.crop
        EditorPhoto(source: source, edit: edit, stage: stage)
            .offset(x: -crop.x * stage.width, y: -crop.y * stage.height)
            .frame(width: crop.width * stage.width, height: crop.height * stage.height, alignment: .topLeading)
            .clipped()
    }
}
