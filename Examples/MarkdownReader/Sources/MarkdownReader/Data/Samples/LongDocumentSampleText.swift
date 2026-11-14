/// A long document generated in a loop, so the laziness of the column is
/// what a reader scrolling it feels.
enum LongDocumentSampleText {
    static func source(sections: Int) -> String {
        var text = "# Long document\n\nThis document has \(sections) sections, generated in a loop to test laziness. Every section adds prose, and every few sections a list, a quote, a code block, a table or a task list.\n\n"
        for number in 1...max(sections, 1) {
            text += "## Section \(number)\n\n"
            text += "Section \(number) opens with **bold**, *italic* and `code`. [Back to the top](#long-document) jumps to the first heading.\n\n"
            if number % 3 == 0 {
                text += "- First point of section \(number)\n- Second point\n  - A nested point\n\n"
            }
            if number % 5 == 0 {
                text += "> Section \(number) is quoted here.\n>> And nested once.\n\n"
            }
            if number % 7 == 0 {
                text += "```swift\nlet section = \(number)\nprint(section)\n```\n\n"
            }
            if number % 11 == 0 {
                text += "| Key | Value |\n| --- | ---: |\n| section | \(number) |\n| squared | \(number * number) |\n\n"
            }
            if number % 13 == 0 {
                text += "- [x] Done in section \(number)\n- [ ] Still open in section \(number)\n\n"
            }
            if number % 17 == 0 {
                text += "![Figure for section \(number)](figure-\(number).png)\n\n"
            }
        }
        return text
    }
}
