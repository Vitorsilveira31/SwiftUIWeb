import SwiftUI

/// The photo as the editor shows it: filtered, turned, zoomed and panned inside the stage, and clipped to it.
struct EditorPhoto: View {
    let source: PhotoSource
    let edit: Edit
    let stage: CGSize

    var body: some View {
        Group {
            switch source {
            case .sample:
                SamplePicture()
            case .picked(let image):
                image.resizable().scaledToFit()
            }
        }
        .frame(width: stage.width, height: stage.height)
        .brightness(edit.brightness)
        .contrast(edit.contrast)
        .saturation(edit.saturation)
        .hueRotation(.degrees(edit.hue))
        .blur(radius: edit.blur)
        .grayscale(edit.grayscale)
        .scaleEffect(edit.scale)
        .rotationEffect(.radians(edit.rotation))
        .offset(x: edit.panX * stage.width, y: edit.panY * stage.height)
        .frame(width: stage.width, height: stage.height)
        .clipped()
    }
}
