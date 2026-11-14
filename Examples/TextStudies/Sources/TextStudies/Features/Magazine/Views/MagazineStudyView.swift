import SwiftUI

/// The measured essay in a page whose width the reader sets; the columns re-cut at line boundaries.
struct MagazineStudyView: View {
    let words: [String]
    let breaks: [Bool]
    @State private var pageWidth = 720.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: Strings.Magazine.eyebrow)
                Text(Strings.Magazine.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Slider(value: $pageWidth, in: 260...760) {
                    Text(Strings.Common.pageWidth)
                }
                .accessibilityIdentifier("width-slider")
                Text(Strings.Common.pageWidthValue(Int(pageWidth)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("page-width")

                VStack(alignment: .leading, spacing: 14) {
                    Text(Strings.Common.pageHeading)
                        .font(.system(size: 36, weight: .bold))
                    Text(Strings.Magazine.subtitle)
                        .font(.system(size: 15).italic())
                        .foregroundStyle(.secondary)
                    FlowLayout(
                        decorated: false,
                        breaks: breaks,
                        lineHeight: 24,
                        fontSize: 16
                    ) {
                        ForEach(words.indices, id: \.self) { index in
                            Text(words[index])
                                .font(TextFonts.article)
                        }
                    }
                    .accessibilityIdentifier("magazine")
                }
                .padding(24)
                .frame(maxWidth: CGFloat(pageWidth), alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3)))
            }
            .padding()
        }
    }
}
