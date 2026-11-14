/// The sample prose and the words the studies break it into.
enum SampleProse {
    static let ballText = """
    The apprentice learned the trade by weight before she learned it by eye. A line of type had a heft in the hand, and the hand knew when the measure was full long before anyone counted the letters. Later the shop bought its first machine, and the old compositor kept a case of loose type in the back room for the jobs that mattered. A machine could cast a line, he liked to say, but it could not feel one. Measure the page first and draw it second, and the work comes out right.
    """

    static let dragonText = """
    Of the dragon the old books say much and agree on little. One account has it sleeping for a century beneath a hill of its own making, the hill warm to the touch in winter, so that shepherds bring their flocks there when the snow lies deep. Another has it never sleeping at all, the warmth of the hill being only the memory of an older fire. Both are copied here without correction, since the copyist is not the judge.

    Of its shape there is more agreement. The neck is long and carried low, the wings are folded like a cloak when it walks, and the tail ends in a blade of horn. The crest along the back rises when the creature is angry and lies flat when it is content, and by that sign alone a traveller may know whether to go on or turn back.

    It is fond of gold, though not for the gold itself. A dragon cannot see its own hoard, being always upon it; what it loves is the sound the coins make when a thief disturbs them, for that sound is the only company it keeps. Feed it nothing. Speak to it plainly. Do not try to move it, for it will not go where it is pushed.
    """

    static let articleParagraphs: [String] = [
        "There is a moment in every layout when the page stops being a sketch and becomes a measurement. Before that moment it is a promise: a headline here, a column there, a photograph roughly this size. The sketch is honest about what it does not know. It cannot say how long the text will be, so it draws a grey block and hopes. It cannot say where the lines will break, so it draws straight rules and calls them columns.",
        "The usual answer is to let the page find its own shape. Pour the words in, let them flow, and see what happens. That works while there is one column and nothing in the way. It stops working the moment the design asks a question the flow cannot answer alone. How tall will this card be? Which column holds the quotation? Does the article still end on this page once the photograph is placed? Each question needs a number, and the number is the height of some text at some width.",
        "For most of the history of printing that number was found by setting the type. A compositor filled a measure, counted the lines, and knew. The knowledge was expensive, because the whole job had to be set to get it, but it was exact. Software reversed the order without meaning to: draw the page, ask the machine what it did, then draw it again. Anyone who has watched a web page settle into place, jumping twice as its images arrive, has watched that reversal happen in public.",
        "The idea behind a measured layout is simple. Measure every word once, in the face and size it will be set in, and keep the numbers. After that, deciding how tall a paragraph will be at any width is addition. Add advances until the line is full, start a new line, and count. There is no page to draw and throw away, and no waiting for a machine to report back. The cost is paid at the beginning, when the words are known and the layout is not, which is exactly when a design can still change its mind.",
        "Once heights are cheap, a whole class of layouts becomes ordinary. A wall of cards can be balanced across columns before a single card is drawn. A column can be cut at a line boundary rather than at a character count. A pull quotation can be placed where the eye wants it, and the article can make room for it, because the room it needs is a number too. None of these ideas is new. They belonged to every good magazine of the last century, and they are cheap enough now to do again on every resize.",
        "The interesting part is not the arithmetic. Adding widths takes a few dozen lines in any language. The interesting part is agreement. The numbers are useful only if the thing that finally draws the text breaks the lines where the arithmetic said it would. A measurement that is off by a hair will push one word onto a new line, and then the card is a line taller than the wall expected. Agreement depends on using the same letters, the same rules and the same rounding at both ends.",
        "Drag the width of this page and watch the columns re-cut. Nothing is measured again. The widths were known before the slider moved; only the sums change. That is the whole trick, and it is enough.",
    ]

    static let pullQuote = "“Measure the page first and draw it second; the pages that look wrong are the ones where somebody guessed.”"

    static let dropCapLetter = "T"

    /// Words in reading order, split on whitespace.
    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    static func make() -> ProseVO {
        let articleWords = articleParagraphs.flatMap { words($0) }
        let articleBreaks = articleParagraphs.flatMap { paragraph -> [Bool] in
            let count = words(paragraph).count
            return (0..<count).map { $0 == count - 1 }
        }
        var spreadWords = articleWords
        spreadWords[0] = String(spreadWords[0].dropFirst())
        return ProseVO(
            ballWords: words(ballText),
            dragonWords: words(dragonText),
            dropCapLetter: dropCapLetter,
            pullQuote: pullQuote,
            articleWords: articleWords,
            articleBreaks: articleBreaks,
            articleSpreadWords: spreadWords)
    }
}
