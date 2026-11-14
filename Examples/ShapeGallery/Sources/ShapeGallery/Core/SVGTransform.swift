import Foundation
import SwiftUI

// SVG transform functions, each returning the matrix that the SVG function denotes.
enum SVGTransform {
    static func rotate(_ degrees: CGFloat, about cx: CGFloat = 0, _ cy: CGFloat = 0) -> CGAffineTransform {
        let r = degrees * .pi / 180
        let c = cos(r)
        let s = sin(r)
        return CGAffineTransform(
            a: c, b: s, c: -s, d: c,
            tx: cx - cx * c + cy * s,
            ty: cy - cx * s - cy * c
        )
    }

    static func translate(_ x: CGFloat, _ y: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: x, y: y)
    }

    static func skewX(_ degrees: CGFloat) -> CGAffineTransform {
        CGAffineTransform(a: 1, b: 0, c: tan(degrees * .pi / 180), d: 1, tx: 0, ty: 0)
    }

    static func scale(_ x: CGFloat, _ y: CGFloat) -> CGAffineTransform {
        CGAffineTransform(scaleX: x, y: y)
    }
}
