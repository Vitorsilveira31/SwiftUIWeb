import SwiftUI

/// Layout numbers that depend on the window width and the large-type switch.
struct WrapMetrics {
    let width: CGFloat
    let largeType: Bool

    var narrow: Bool { width < 700 }
    var pageWidth: CGFloat { min(736, max(280, width - (narrow ? 24 : 80))) }
    var inset: CGFloat { narrow ? 20 : 40 }
    var proseWidth: CGFloat { pageWidth - inset * 2 }
    var scale: CGFloat { proseWidth / WrapSpace.logicalWidth }
    var bodySize: CGFloat { largeType ? 18.975 : 16.5 }
    var lineHeight: CGFloat { bodySize * 1.5 }
    var bodyHeight: CGFloat { narrow ? 450 : 480 }
    var logicalHeight: CGFloat { bodyHeight / scale }
    var titleSize: CGFloat { narrow ? 33 : 44 }

    func region(width: CGFloat? = nil, x: CGFloat = 0, y: CGFloat = 0) -> CGRect {
        CGRect(x: x, y: y, width: width ?? proseWidth, height: 0)
    }
}
