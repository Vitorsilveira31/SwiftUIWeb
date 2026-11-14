import SwiftUI

// Page 3: gradients, spread methods, opacity groups, icon symbols and paint order.
struct Page03View: View {
    var body: some View {
        FixtureGrid {
            FxGradients()
            FxSpread()
            FxArea()
            FxOpacityRestore()
            FxUse()
            FxOrder()
            FxBadge(tint: 0xF43F5E, name: "fx-badge-#f43f5e")
            FxBadge(tint: 0x14B8A6, name: "fx-badge-#14b8a6")
            FxSprite()
        }
    }
}
