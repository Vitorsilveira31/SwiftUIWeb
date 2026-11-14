import SwiftUI

/// Fonts shared by the studies. Measuring and drawing use the same font, so the
/// widths the breaker sums are the widths the text is drawn with.
enum TextFonts {
    static let body = Font.system(size: 17)
    static let article = Font.system(size: 16)
    static let glyph = Font.system(size: 13)
    static let mono = Font.system(size: 13, design: .monospaced)
}
