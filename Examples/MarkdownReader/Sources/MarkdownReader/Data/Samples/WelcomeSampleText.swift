/// The welcome document: every construct the reader draws, on one page.
enum WelcomeSampleText {
    static let source = #"""
# Markdown tour

This document exercises every construct the reader draws. The
[contents](#contents) below jump to each section, and the list button in
the toolbar opens the same contents as a sheet.

## Contents

- [Text](#text)
- [Lists](#lists)
- [Quotes](#quotes)
- [Code](#code)
- [Tables](#tables)
- [Images](#images)

## Text

Prose wraps at the reading width, with **bold**, *italic*, ~~struck out~~,
`inline code`, and a [link to the web](https://example.com) that opens in
the browser.

### Emphasis, nested

Mixing **bold with *italic* inside** reads naturally, and so does
***both at once***.

#### Deep heading

##### Deeper heading

###### Deepest heading

## Lists

- An unordered item
- Another item, long enough to wrap so that the hanging indent
  under the marker is visible rather than merely asserted
  - A nested item
    - and one more level down
  - Back up a level
1. An ordered item
2. And the next
3. A third

Tasks:

- [x] Parse the headings
- [x] Lay the blocks out in a lazy column
- [ ] Ship the reader
  - [ ] A nested task

## Quotes

> A block quote sits behind a bar on its leading edge.
>
> A second paragraph in the same quote.

> Nested quotes get one bar per level.
>> The inner quote, one level deeper.
>>> And one level deeper still.

## Code

```swift
struct Greeting: View {
    let name: String
    var body: some View {
        Text("Hello, \(name)")
    }
}
```

```sh
mdview README.md
```

```
A fence with no language label. Indentation is kept exactly as written.
    This line is indented, and this one is long enough that the block must scroll sideways to show its end.
```

## Tables

| Left | Centre | Right |
| :--- | :----: | ----: |
| `path` | where the file came from | 12 |
| **bold** | *italic* | 3 |
| ~~gone~~ | [a link](#markdown-tour) | 1,024 |

## Images

![A placeholder diagram of the reader pipeline](diagram.png)

---

Back to the [top](#markdown-tour).
"""#
}
