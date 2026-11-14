import SwiftUI

/// Images at four sizes, and one faded copy. The reference's tile image is an SF Symbol here, since the
/// gallery ships no assets. Crops and smoothing are not expressible on an SF Symbol draw, so each image
/// is drawn at its destination size.
@MainActor
enum ImagePainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        let photo = context.resolve(Image(systemName: "photo"))
        context.draw(photo, in: CGRect(x: 4, y: 4, width: 40, height: 30))
        context.draw(photo, in: CGRect(x: 50, y: 4, width: 60, height: 45))
        context.draw(photo, in: CGRect(x: 114, y: 4, width: 32, height: 24))
        context.draw(photo, in: CGRect(x: 4, y: 52, width: 80, height: 45))
        var faded = context
        faded.opacity = 0.5
        faded.draw(photo, in: CGRect(x: 90, y: 55, width: 56, height: 42))
    }
}
