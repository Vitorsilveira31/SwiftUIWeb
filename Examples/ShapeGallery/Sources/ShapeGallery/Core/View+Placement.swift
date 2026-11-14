import SwiftUI

extension View {
    // SVG coordinates are points of the 120 x 80 picture, so an element is placed at its
    // absolute x and y by giving it a frame and an offset.
    func placed(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> some View {
        frame(width: width, height: height, alignment: .topLeading).offset(x: x, y: y)
    }

    // Stacks a full-picture layer in its own coordinate space, so a transform applied to it
    // is taken about the picture's origin, as an SVG transform is.
    func pictureLayer() -> some View {
        frame(width: 120, height: 80, alignment: .topLeading)
    }
}
