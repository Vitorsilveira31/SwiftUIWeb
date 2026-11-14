import SwiftUI

/// Study 05: a drop cap, an inset quotation and two discs, in the coordinates of the whole spread.
struct EditorialScene: WrapSceneGeometry {
    func parts(_ context: WrapSceneContext) -> [WrapExclusion] {
        let narrow = context.narrow
        let scale = context.scale
        let quote = narrow
            ? CGRect(x: 165, y: 188, width: 100, height: 112)
            : CGRect(x: 234, y: 190, width: 188, height: 115)
        let beadOne = 68 * scale
        let beadTwo = 60 * scale
        return [
            WrapExclusion(
                id: "drop-cap",
                outline: .rect(CGRect(x: 0, y: 0, width: 48, height: 61)),
                margin: 7,
                caption: .dropCap("T", 65)
            ),
            WrapExclusion(
                id: "pull-quote",
                outline: .rect(quote),
                margin: 10,
                caption: .quote(WrapCopy.pullQuote, narrow ? 16 : 21)
            ),
            WrapExclusion.disc(
                "bead-1",
                center: CGPoint(x: (narrow ? 192 : 510) + beadOne / 2, y: 24 + beadOne / 2),
                radius: beadOne / 2,
                margin: 10,
                tint: .terracotta
            ),
            WrapExclusion.disc(
                "bead-2",
                center: CGPoint(x: (narrow ? 26 : 92) + beadTwo / 2, y: (narrow ? 650 : 356) + beadTwo / 2),
                radius: beadTwo / 2,
                margin: 9,
                tint: .sage
            ),
        ]
    }
}
