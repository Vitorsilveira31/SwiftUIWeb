import SwiftUIWebCore
import SwiftUIWebFeatures
import SwiftUIWebTransferable

// Differential probe for AttributedString(markdown:) built for the Embedded
// WASM profile. The host supplies the mode through imports (Embedded Swift has
// no CommandLine) and receives text through a log import. Every run is printed
// as text, link, strike, underline and a font-combination index, which covers
// every attribute the markdown parser can set.

@_extern(wasm, module: "probe", name: "log_bytes")
func logBytes(_ pointer: UnsafePointer<UInt8>, _ count: Int32)
@_extern(wasm, module: "probe", name: "mode")
func probeMode() -> Int32
@_extern(wasm, module: "probe", name: "now_ms")
func nowMilliseconds() -> Double
@_extern(wasm, module: "probe", name: "bench_kind")
func benchKind() -> Int32
@_extern(wasm, module: "probe", name: "bench_n")
func benchN() -> Int32

func emit(_ text: String) {
  let bytes = Array(text.utf8)
  bytes.withUnsafeBufferPointer { buffer in
    logBytes(buffer.baseAddress!, Int32(buffer.count))
  }
}

func hex8(_ value: UInt32) -> String {
  var result = ""
  var shift: UInt32 = 28
  while true {
    let nibble = UInt8((value >> shift) & 0xF)
    let digit: UInt8 = nibble < 10 ? 48 + nibble : 87 + nibble
    result.append(Character(Unicode.Scalar(digit)))
    if shift == 0 { break }
    shift -= 4
  }
  return result
}

func escaped(_ text: String) -> String {
  var result = "\""
  for scalar in text.unicodeScalars {
    let value = scalar.value
    if value >= 0x20 && value <= 0x7E && value != 0x22 && value != 0x5C {
      result.append(Character(scalar))
    } else {
      result += "\\u" + hex8(value)
    }
  }
  return result + "\""
}

func repeated(_ piece: String, _ count: Int) -> String {
  var result = ""
  var index = 0
  while index < count {
    result += piece
    index += 1
  }
  return result
}

// Font references come from the parser itself, so each combination's Font
// value is exactly what the parser produces for that style.
let fontTemplates: [String] = [
  "x", "**x**", "*x*", "***x***", "`x`", "**`x`**", "*`x`*", "***`x***",
]

func fontReferences() -> [Font?] {
  var references: [Font?] = []
  for template in fontTemplates {
    let parsed = try! AttributedString(markdown: template)
    references.append(parsed.runs.first?.font)
  }
  return references
}

let references = fontReferences()

func fontIndex(_ font: Font?) -> Int {
  var index = 0
  while index < references.count {
    if references[index] == font { return index }
    index += 1
  }
  return -1
}

func show(_ input: String) -> String {
  var out = "IN " + escaped(input) + "\n"
  do {
    let s = try AttributedString(markdown: input)
    out += "CHARS " + escaped(s.characters) + "\n"
    for run in s.runs {
      let text = s[run.range].characters
      var link = "-"
      if let url = run.link { link = escaped(url.absoluteString) }
      let strike = run.strikethroughStyle == nil ? "s" : "S"
      let underline = run.underlineStyle == nil ? "u" : "U"
      out += "RUN " + escaped(text) + " link=" + link + " strike=" + strike
        + " underline=" + underline + " font=" + String(fontIndex(run.font)) + "\n"
    }
  } catch {
    out += "ERR\n"
  }
  return out
}

let ordinary: [String] = [
  "plain text",
  "*em* and **strong** and _u_ and __b__",
  "`code` here",
  "~~strike~~",
  "[link](https://example.com)",
  "[**bold link**](/x)",
  "[a *b* c](/y) tail",
  "[nested [inner](/i) label](/outer)",
  "![img](x.png)",
  "\\[escaped](x)",
  "\\*not em\\*",
  "a [b] c",
  "a [b c",
  "[unclosed",
  "[a](b",
  "[a]",
  "[a] (b)",
  "[](empty)",
  "]stray",
  "[a](b)c](d)",
  "[x](y)[z](w)",
  "[a [b] c](d)",
  "[a](b) [c",
  "***triple***",
  "`[code](x)`",
  "\\",
  "a\\",
  "[a\\](b)",
  "[a](b\\)c)",
  "[](\\",
  "[*a](b)*",
  "~ ~~ ~",
  "[ab](c)(d)",
  "[a](b)]",
  "[[a](b)](c)",
  "[a](b) and ) stray",
  "[a](b c) d",
  "[a](https://x.test/a(b)c)",
  "the [ unmatched [ brackets ] (x)",
  "[\u{e9}](\u{fc}) \u{2713}",
  "[a\nb](c)",
  "[a [b](c) d](e)",
  "[[[a]](b)]](c)",
  "x [y [z] w",
  "[a](b)[c](d)[e",
  "_[under](x)_ and `a` ~~[s](t)~~",
  "[**a**](b) [`c`](d) [~~e~~](f)",
  "**[a](b)**",
]

func corpus() {
  for input in ordinary {
    emit(show(input))
  }
  var state: UInt64 = 20260415
  let alphabet: [String] = ["[", "]", "(", ")", "\\", "*", "_", "`", "~", "a", " "]
  var caseIndex = 0
  while caseIndex < 1500 {
    state = state &* 6364136223846793005 &+ 1442695040888963407
    let length = Int((state >> 33) % 13)
    var input = ""
    var position = 0
    while position < length {
      state = state &* 6364136223846793005 &+ 1442695040888963407
      input += alphabet[Int((state >> 33) % UInt64(alphabet.count))]
      position += 1
    }
    emit(show(input))
    caseIndex += 1
  }
}

func bench() {
  let kind = benchKind()
  let n = Int(benchN())
  let input: String
  if kind == 1 {
    input = repeated("[", n)
  } else if kind == 2 {
    input = repeated("[](", n)
  } else if kind == 3 {
    input = repeated("[](x)", n)
  } else if kind == 4 {
    input = repeated("[", n) + "a" + repeated("](x)", n)
  } else if kind == 6 {
    input = repeated("[", n) + repeated("](", n)
  } else if kind == 7 {
    input = repeated("[a](", n)
  } else {
    input = repeated("a [b] *c* ", n)
  }
  let start = nowMilliseconds()
  let result = try? AttributedString(markdown: input)
  let elapsed = nowMilliseconds() - start
  var runCount = -1
  if let result { runCount = result.runs.count }
  emit("BENCH kind=" + String(kind) + " n=" + String(n) + " inputLength=" + String(input.utf8.count)
    + " ms=" + String(Int(elapsed)) + " runs=" + String(runCount) + "\n")
}

if probeMode() == 1 {
  bench()
} else {
  corpus()
}
