import Foundation
import SwiftUI

/// Inline Markdown (emphasis, code spans, strikethrough, links) as a styled
/// `AttributedString` that `Text` draws. Links keep their `.link` attribute,
/// so `Text` makes them tappable and sends them to `OpenURLAction`.
enum MarkdownInlineStyler {
    /// Parses only inline syntax and keeps the whitespace the author typed,
    /// which is what a paragraph needs: no block structure is re-read here.
    static func styled(_ source: String, font: Font = .body) -> AttributedString {
        var text = (try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(source)

        // The parser records emphasis as intents. Turning them into fonts here
        // keeps every run's weight and face under the reader's control, rather
        // than trusting each host to honour the intent.
        for run in text.runs {
            let intent = run.inlinePresentationIntent ?? []
            var runFont = intent.contains(.code) ? Font.system(.callout, design: .monospaced) : font
            if intent.contains(.stronglyEmphasized) {
                runFont = runFont.bold()
            }
            if intent.contains(.emphasized) {
                runFont = runFont.italic()
            }
            text[run.range].font = runFont
            if intent.contains(.strikethrough) {
                text[run.range].strikethroughStyle = .single
            }
            if intent.contains(.code) {
                text[run.range].foregroundColor = .orange
            }
        }
        return text
    }

    /// The words of `source` with its markup removed, for the contents list.
    static func plainText(_ source: String) -> String {
        String(styled(source).characters)
    }
}
