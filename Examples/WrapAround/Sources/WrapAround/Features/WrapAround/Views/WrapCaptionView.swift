import SwiftUI

/// A drop cap or an inset quotation, placed in its exclusion rectangle.
struct WrapCaptionView: View {
    let caption: WrapCaption
    let rect: CGRect

    var body: some View {
        switch caption {
        case .dropCap(let letter, let size):
            // Top-aligned in its box, so the letter's cap line meets the first line of text.
            Text(letter)
                .font(.system(size: size))
                .fontDesign(.serif)
                .foregroundStyle(WrapTint.terracotta.color)
                .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                .position(x: rect.midX, y: rect.midY)
        case .quote(let text, let size):
            Text(text)
                .italic()
                .font(.system(size: size))
                .fontDesign(.serif)
                .multilineTextAlignment(.center)
                .padding(12)
                .frame(width: rect.width, height: rect.height)
                .background(Color.teal.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                .position(x: rect.midX, y: rect.midY)
        }
    }
}
