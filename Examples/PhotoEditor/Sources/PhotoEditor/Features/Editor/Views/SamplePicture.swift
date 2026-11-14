import SwiftUI

/// The bundled picture, drawn with Canvas so the editor works with no photo.
/// Drawn from fractions of its size, so it looks the same at any size, including the export's.
struct SamplePicture: View {
    var body: some View {
        Canvas { context, size in
            SampleArt.draw(&context, size: size)
        }
    }
}
