import SwiftUI

/// One clip in the side list: title, detail, and a check mark on the clip being played.
struct PlayerClipRow: View {
    let clip: Clip
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.title)
                        .font(.body.weight(.semibold))
                    Text(clip.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isCurrent ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("clip-\(clip.id)")
    }
}
