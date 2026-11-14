/// Every user-visible sentence of the reader. Sample documents and format
/// strings live elsewhere, as fixture data and code.
enum Strings {
    enum App {
        static let title = "Markdown"
    }

    enum Reader {
        static let contents = "Contents"
        static let source = "Source"
        static let textSize = "Text size"
        static let samples = "Samples"
        static let sample = "Sample"
    }

    enum TextSizeOption {
        static let small = "Small"
        static let standard = "Standard"
        static let large = "Large"
        static let larger = "Larger"
        static let largest = "Largest"
    }

    enum SampleOption {
        static let welcome = "Welcome tour"
        static let longDocument = "300 sections"
        static let tablesAndCode = "Tables and code"
    }

    enum Contents {
        static let title = "Contents"
        static let empty = "This document has no headings."
        static let done = "Done"
    }

    enum CodeBlock {
        static let copy = "Copy"
        static let untitledLanguage = "code"
    }

    enum ImageBlock {
        static let untitled = "Image"
    }
}
