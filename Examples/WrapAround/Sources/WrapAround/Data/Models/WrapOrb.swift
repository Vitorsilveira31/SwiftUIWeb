import SwiftUI

/// A disc the reader can drag. Positions are in the 656-point logical page, scaled to the column.
struct WrapOrb: Sendable {
    var x: CGFloat
    var y: CGFloat
    let diameter: CGFloat
    let tint: WrapTint

    static let initial: [WrapOrb] = [
        WrapOrb(x: 140, y: 52, diameter: 104, tint: .terracotta),
        WrapOrb(x: 414, y: 161, diameter: 78, tint: .sage),
        WrapOrb(x: 245, y: 302, diameter: 56, tint: .ochre),
    ]
}
