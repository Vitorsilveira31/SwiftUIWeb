import SwiftUI

// One notification: its symbol, title, time and the first lines of its body.
struct NoticeCard: View {
    let notice: Notice
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: notice.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(notice.title)
                            .font(Voice.title(17))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(notice.time)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Text(notice.body)
                        .font(Voice.text(15))
                        .foregroundStyle(.primary.opacity(0.88))
                        .lineLimit(3)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("notice-\(notice.id)")
    }
}
