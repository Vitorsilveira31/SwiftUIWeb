import SwiftUI

/// Study 07: a drop cap and a quotation at the right edge. Paragraphs take the height their words need.
struct ArticleScene: WrapSceneGeometry {
    func parts(_ context: WrapSceneContext) -> [WrapExclusion] {
        let narrow = context.narrow
        let width = context.proseWidth
        let quote = CGRect(
            x: width - (narrow ? 128 : 196),
            y: narrow ? 300 : 170,
            width: narrow ? 128 : 196,
            height: narrow ? 104 : 96
        )
        return [
            WrapExclusion(
                id: "drop-cap",
                outline: .rect(CGRect(x: 0, y: 0, width: narrow ? 46 : 66, height: narrow ? 42 : 66)),
                margin: 6,
                caption: .dropCap("M", narrow ? 44 : 64)
            ),
            WrapExclusion(
                id: "article-quote",
                outline: .rect(quote),
                margin: 10,
                caption: .quote(WrapCopy.articleQuote, narrow ? 15 : 19)
            ),
        ]
    }
}
