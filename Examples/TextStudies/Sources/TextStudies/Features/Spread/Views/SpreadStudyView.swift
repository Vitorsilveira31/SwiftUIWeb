import SwiftUI

/// The editorial spread: a drop cap, a pull quote and a round picture the words flow around.
struct SpreadStudyView: View {
    let prose: ProseVO
    @State private var pageWidth = 940.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: Strings.Spread.eyebrow)
                Text(Strings.Spread.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Slider(value: $pageWidth, in: 320...1000) {
                    Text(Strings.Common.pageWidth)
                }
                .accessibilityIdentifier("width-slider")
                Text(Strings.Common.pageWidthValue(Int(pageWidth)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("page-width")

                VStack(alignment: .leading, spacing: 18) {
                    Text(Strings.Common.pageHeading)
                        .font(.system(size: 44, weight: .bold))
                    Text(Strings.Spread.subtitle)
                        .font(.system(size: 17).italic())
                        .foregroundStyle(.secondary)
                    FlowLayout(
                        decorated: true,
                        breaks: prose.articleBreaks,
                        lineHeight: 24,
                        fontSize: 16
                    ) {
                        DropCapView(letter: prose.dropCapLetter)
                        PullQuoteView(text: prose.pullQuote)
                        RoundPictureView()
                        ForEach(prose.articleSpreadWords.indices, id: \.self) { index in
                            Text(prose.articleSpreadWords[index])
                                .font(TextFonts.article)
                        }
                    }
                    .accessibilityIdentifier("spread")
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
