import SwiftUI

// A person's initials, or the assistant's mark, as a filled disc.
struct Avatar: View {
    let initials: String
    let isAssistant: Bool
    let size: CGFloat

    var body: some View {
        Text(initials)
            .font(isAssistant ? Voice.display(size * 0.4) : Voice.title(size * 0.36))
            .foregroundStyle(isAssistant ? AnyShapeStyle(BackgroundStyle()) : AnyShapeStyle(Color.primary))
            .frame(width: size, height: size)
            .background(Circle().fill(isAssistant ? Color.primary : Color.gray.opacity(0.35)))
    }
}
