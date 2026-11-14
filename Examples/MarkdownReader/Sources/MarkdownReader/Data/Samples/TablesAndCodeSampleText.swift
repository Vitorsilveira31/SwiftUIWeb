/// A stress document: wide tables, long code lines and uneven rows.
enum TablesAndCodeSampleText {
    static let source = #"""
# Tables and code

A stress document. Wide tables and long code lines scroll sideways, and
each table's alignment is read from its separator row.

## Narrow table

| Name | Role |
| --- | --- |
| Ada | Engineer |
| Grace | Admiral |
| Linus | |

## Aligned table

| Left | Centre | Right |
| :--- | :---: | ---: |
| a | b | c |
| 1 | 2 | 3 |

## Wide table

| Identifier | Description of the first column | Second column with a long heading | Third | Fourth | Fifth | Sixth | Seventh |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `alpha-0001` | A row whose cells are long enough that the table must scroll | value one | 1 | 2 | 3 | 4 | 5 |
| `beta-0002` | Another row, with **bold** and *italic* in its cells | value two | 6 | 7 | 8 | 9 | 10 |
| `gamma-0003` | Links are [inline](https://example.com) too | value three | 11 | 12 | 13 | 14 | 15 |

## Uneven rows

| One | Two | Three |
| --- | --- | --- |
| only one cell |
| a | b | c | extra |

## Code

```json
{ "name": "markdown", "features": ["tables", "code", "lists"], "version": 3 }
```

```swift
enum Shape {
    case circle(radius: Double)
    case rectangle(width: Double, height: Double)
}
```

```
A long unbroken line for horizontal scrolling: 0123456789 0123456789 0123456789 0123456789 0123456789 0123456789 END
```

## Thematic breaks

Above this line.

---

Below this line.
"""#
}
