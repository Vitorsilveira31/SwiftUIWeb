import SwiftUI

// SVG text is placed by its anchor (start, middle, end) and its baseline; this view
// positions a Text the same way inside the 120-point picture.
struct AnchoredLabel: View {
    enum Anchor {
        case start, middle, end
    }

    enum Vertical {
        case baseline, middle, hanging
    }

    let text: String
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let weight: Font.Weight
    let color: Color
    let anchor: Anchor
    let vertical: Vertical

    init(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        size: CGFloat,
        weight: Font.Weight = .regular,
        color: Color,
        anchor: Anchor = .start,
        vertical: Vertical = .baseline
    ) {
        self.text = text
        self.x = x
        self.y = y
        self.size = size
        self.weight = weight
        self.color = color
        self.anchor = anchor
        self.vertical = vertical
    }

    var body: some View {
        let width: CGFloat = 120
        let height = size * 1.3
        let left: CGFloat
        let alignment: Alignment
        switch anchor {
        case .start:
            left = x
            alignment = .leading
        case .middle:
            left = x - width / 2
            alignment = .center
        case .end:
            left = x - width
            alignment = .trailing
        }
        let top: CGFloat
        switch vertical {
        case .baseline: top = y - size * 0.8
        case .middle: top = y - height / 2
        case .hanging: top = y
        }
        return Text(text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            .frame(width: width, height: height, alignment: alignment)
            .offset(x: left, y: top)
    }
}
