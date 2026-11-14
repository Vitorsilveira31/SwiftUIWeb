# MarkdownReader

A Markdown reader: a bundled document rendered block by block, with a contents sheet, a text size menu, and a Source
view that edits the text and re-renders it live. It presses on `ScrollViewReader` with `scrollTo` for in-document
`#anchor` links, `OpenURLAction`, `AttributedString(markdown:)` for inline styling, `Grid` in a horizontal `ScrollView`
for tables, `ShareLink` for the code block copy button, `TextEditor` bound to an `@Observable` view model, and
`.dynamicTypeSize` for the text size choice.

```
Sources/MarkdownReader/
  App/                      MarkdownReaderRootView (NavigationStack and title)
  Core/                     Strings
  Data/Models/              Block, BlockKind, ListMarker, ColumnAlignment, TableData, Heading, Document
  Data/Parsing/            MarkdownParser, block scanner, line recognizer, list and table parsers, inline styler
  Data/Samples/            Sample, SampleRepository, the bundled sample texts (one file each)
  Features/Reader/         ReaderViewModel, TextSize, ScrollRequest
  Features/Reader/Views/   ReaderScreen, toolbar, Source editor, document, contents sheet
  Features/Reader/Views/Blocks/  one View per block kind
```

Run on iOS: open `Darwin/MarkdownReader.xcodeproj` and run the scheme "MarkdownReader App".

Run in the browser: `make example-web EXAMPLE=MarkdownReader` from the repository root.
