/// Every user-visible literal in the app. Sample prose and card text are data, not copy, and live in Data/.
enum Strings {
    enum Root {
        static let title = "Text Studies"
        static let studyPicker = "Study"
        static let play = "Play"
        static let pause = "Pause"

        enum Study {
            static let balls = "01 Balls"
            static let dragon = "02 Dragon"
            static let masonry = "03 Masonry"
            static let magazine = "04 Dynamic layout"
            static let ascii = "05 ASCII art"
            static let wall = "06 Occlusion"
            static let spread = "07 Spread"
        }
    }

    enum Common {
        static let pageWidth = "Page width"
        static let pageHeading = "The Measured Page"

        static func pageWidthValue(_ points: Int) -> String {
            "\(points) pt"
        }
    }

    enum Balls {
        static let eyebrow = "01 / BALLS"
        static let summary = "Three spheres cross a paragraph, and the words part around them on both sides. Their positions are arithmetic on the clock, so every frame re-flows the text."
    }

    enum Dragon {
        static let eyebrow = "02 / THE ILLUSTRATED MANUSCRIPT"
        static let summary = "Drag the dragon anywhere on the page. Its outline is both the ink and the exclusion, so the text closes around it wherever it lands."
    }

    enum Masonry {
        static let eyebrow = "03 / MASONRY"
        static let summary = "36 cards, each set in the bold and regular faces and placed in the shortest column. Each footer counts the words it was built from."
        static let shuffle = "Shuffle"
    }

    enum Magazine {
        static let eyebrow = "04 / DYNAMIC LAYOUT"
        static let summary = "Move the width and the columns re-cut at line boundaries. The lines are measured once; the width only changes how many fall in each column."
        static let subtitle = "An essay in as many columns as fit"
    }

    enum Ascii {
        static let eyebrow = "05 / ASCII ART"
        static let facePicker = "Face"
        static let monoTitle = "Mono"
        static let measuredTitle = "Measured"
        static let gridTitle = "Grid"
        static let monoExplanation = "A monospaced face: every glyph has one advance, so a uniform grid is the true layout."
        static let measuredExplanation = "A proportional face. Each row advances by the real width of the glyph it just chose, so the sphere keeps its shape."
        static let gridExplanation = "A proportional face on a uniform grid. The glyphs are not uniform, so the rows stretch and the sphere bends."
    }

    enum Wall {
        static let eyebrow = "06 / OCCLUSION"
        static let summary = "1,200 cards in the shortest-column layout. Every height is known before the scroll extent is set, so the scroll bar never re-estimates as you move."
    }

    enum Spread {
        static let eyebrow = "07 / EDITORIAL SPREAD"
        static let summary = "The drop cap, the quotation and the picture are obstacles. The words break around them, and the columns balance themselves to the fewest lines that hold the whole essay."
        static let subtitle = "Why a magazine measures first and draws second"
    }

    enum Card {
        static func footer(number: Int, words: Int) -> String {
            "No. \(number) · \(words) words"
        }
    }
}
