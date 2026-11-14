import SwiftUI

/// Measures words inside a Canvas: `GraphicsContext.resolve` gives the ink width of a word
/// in the study's font. Widths are kept, since the same vocabulary is measured every frame.
@MainActor
final class WidthCache {
    private let font: Font
    private var widths: [String: CGFloat] = [:]

    init(font: Font) {
        self.font = font
    }

    func width(_ text: String, in context: inout GraphicsContext) -> CGFloat {
        if let known = widths[text] { return known }
        let resolved = context.resolve(Text(text).font(font))
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let measured = resolved.measure(in: unbounded).width
        widths[text] = measured
        return measured
    }
}
