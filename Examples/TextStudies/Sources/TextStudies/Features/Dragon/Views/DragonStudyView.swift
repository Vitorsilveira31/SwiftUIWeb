import SwiftUI

/// A bestiary page with a dragon the reader can move. The silhouette is one polygon: it is
/// drawn and it is the exclusion the words close around.
struct DragonStudyView: View {
    let words: [String]
    let dropCap: String
    @State private var offset = CGSize.zero
    @State private var base = CGSize.zero
    @State private var grabbed: Bool? = nil
    @State private var widths = WidthCache(font: TextFonts.article)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: Strings.Dragon.eyebrow)
            Text(Strings.Dragon.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
            GeometryReader { geometry in
                Canvas { context, size in
                    DragonScene.draw(
                        into: &context,
                        size: size,
                        offset: offset,
                        widths: widths,
                        words: words,
                        dropCap: dropCap)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // Decide once per touch whether it started on the dragon.
                            if grabbed == nil {
                                grabbed = DragonScene
                                    .frame(in: geometry.size, offset: base)
                                    .contains(value.startLocation)
                            }
                            if grabbed == true {
                                offset = CGSize(
                                    width: base.width + value.translation.width,
                                    height: base.height + value.translation.height)
                            }
                        }
                        .onEnded { _ in
                            if grabbed == true { base = offset }
                            grabbed = nil
                        })
            }
            .frame(height: 900)
            .accessibilityIdentifier("dragon-page")
        }
        .padding()
    }
}
