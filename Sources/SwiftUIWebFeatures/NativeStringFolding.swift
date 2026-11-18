// Foundation's `String.folding(options:locale:)` computed in Swift for builds that have no browser to ask (a native
// build: tests, tools). The browser product folds non-ASCII text with `String.normalize` behind BrowserIO
// (`Tools/BrowserIO/text-format.mjs`); this file is compiled only where no browser can exist, so none of it reaches
// `app.wasm` (see `_TextHost` in TextHost.swift for the condition).
#if !arch(wasm32)
// The standard library's own normalization and case folding (the SPI swift-foundation folds with).
@_spi(_Unicode) import Swift

/// Foundation's `folding(options:locale:)` on Apple platforms, for the text the ASCII path does not fold. Foundation
/// folds a cluster at a time: a base and the combining marks (Grapheme_Extend) after it. Its diacritic folding knows
/// Latin, Greek and Cyrillic: those letters lose their marks (`é` -> `e`) and a base below U+0510 drops every mark
/// after it. Any other base (a CJK ideograph, a Hebrew letter, kana) keeps its marks, except a first one below U+0510
/// (U+0301 right after an ideograph), and the marks it keeps come out decomposed in canonical order. A base whose
/// case folding changes it to a letter outside those scripts keeps every mark. Measured against Foundation on macOS 27
/// for every scalar alone, after a base and before a mark, and for random runs of letters and marks.
func _swiftFoldText(_ value: String, diacritics: Bool, case foldsCase: Bool) -> String {
  let scalars = Array(value.unicodeScalars)
  var result = String.UnicodeScalarView()
  guard diacritics else {
    for scalar in scalars { result.append(contentsOf: _caseFolded(scalar, foldsCase)) }
    return String(result)
  }
  var index = 0
  while index < scalars.count {
    let base = scalars[index]
    index += 1
    // NUL takes no marks: what follows starts a cluster, as the start of the text does.
    if base.value == 0 { result.append(base); continue }
    var marks: [Unicode.Scalar] = []
    while index < scalars.count, _isFoldingMark(scalars[index]) { marks.append(scalars[index]); index += 1 }
    if _foldsDiacritics(base) {
      result.append(contentsOf: _caseFolded(_diacriticBase(base), foldsCase))
      continue
    }
    let folded = _caseFolded(base, foldsCase)
    if folded.count != 1 || folded[0] != base {
      if _dropsMarks(folded[0]) {
        result.append(_foldsDiacritics(folded[0]) ? _diacriticBase(folded[0]) : folded[0])
        for part in folded.dropFirst() where !_isFoldingMark(part) { result.append(part) }
      } else {
        result.append(contentsOf: folded)
        result.append(contentsOf: _canonicallyOrdered(marks))
      }
      continue
    }
    if _dropsMarks(base) { result.append(base); continue }
    // Only a first mark below U+0510 goes (U+0301 right after a CJK ideograph).
    let kept = marks.first.map { $0.value < 0x510 } == true ? Array(marks.dropFirst()) : marks
    if _isFoldingMark(base) {
      result.append(contentsOf: _canonicallyOrdered(kept, after: base))
    } else {
      result.append(base)
      result.append(contentsOf: _canonicallyOrdered(kept))
    }
  }
  return String(result)
}

/// Unicode's full case folding, as Foundation applies it: Cherokee is lowercased (Unicode folds it to its capitals)
/// and the Cyrillic letter variants U+1C80...U+1C88 stay as they are.
private func _caseFolded(_ scalar: Unicode.Scalar, _ foldsCase: Bool) -> [Unicode.Scalar] {
  guard foldsCase else { return [scalar] }
  let value = scalar.value
  if (0x13A0...0x13FD).contains(value) || (0xAB70...0xABBF).contains(value) {
    return Array(scalar.properties.lowercaseMapping.unicodeScalars)
  }
  if (0x1C80...0x1C88).contains(value) { return [scalar] }
  return Array(scalar.properties._caseFolded.unicodeScalars)
}

/// Marks decomposed and stably sorted by canonical combining class (a class 0 mark such as U+FE0F goes first).
private func _canonicallyOrdered(_ marks: [Unicode.Scalar], after leading: Unicode.Scalar? = nil) -> [Unicode.Scalar] {
  guard !marks.isEmpty else { return leading.map { [$0] } ?? [] }
  // A mark that starts the text is sorted with the marks after it but is not decomposed.
  var parts: [Unicode.Scalar] = leading.map { [$0] } ?? []
  for mark in marks { parts.append(contentsOf: String(mark)._nfd) }
  return parts.enumerated().sorted {
    let left = $0.element.properties.canonicalCombiningClass.rawValue
    let right = $1.element.properties.canonicalCombiningClass.rawValue
    return left != right ? left < right : $0.offset < $1.offset
  }.map(\.element)
}

/// A combining mark as Foundation counts one: Grapheme_Extend and the emoji skin tones.
private func _isFoldingMark(_ scalar: Unicode.Scalar) -> Bool {
  scalar.properties.isGraphemeExtend || (0x1F3FB...0x1F3FF).contains(scalar.value)
}

/// A base after which Foundation drops every mark.
private func _dropsMarks(_ scalar: Unicode.Scalar) -> Bool {
  (scalar.value != 0 && scalar.value < 0x510) || _foldsDiacritics(scalar)
}

/// The letter of a precomposed character without its marks (`ế` -> `e`, `Å` -> `A`, `≠` -> `=`).
private func _diacriticBase(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
  String(scalar)._nfd.first { _ in true } ?? scalar
}
/// The characters Foundation decomposes when it folds diacritics (measured against Foundation on macOS 27).
private func _foldsDiacritics(_ scalar: Unicode.Scalar) -> Bool {
  let value = scalar.value
  guard value >= 0xC0, value <= 0x226F else { return false }
  // The combining forms that canonically decompose to another mark (U+0340 -> U+0300).
  if value == 0x340 || value == 0x341 || value == 0x343 || value == 0x344 { return true }
  var low = 0
  var high = _diacriticFoldingRanges.count / 2 - 1
  while low <= high {
    let middle = (low + high) / 2
    if value < _diacriticFoldingRanges[middle * 2] { high = middle - 1 }
    else if value > _diacriticFoldingRanges[middle * 2 + 1] { low = middle + 1 }
    else { return true }
  }
  return false
}

/// Inclusive ranges, as start, end pairs.
private let _diacriticFoldingRanges: [UInt32] = [
  0xC0, 0xC5, 0xC7, 0xCF, 0xD1, 0xD6, 0xD9, 0xDD, 0xE0, 0xE5, 0xE7, 0xEF, 0xF1, 0xF6, 0xF9, 0xFD, 0xFF, 0x10F,
  0x112, 0x125, 0x128, 0x130, 0x134, 0x137, 0x139, 0x13E, 0x143, 0x148, 0x14C, 0x151, 0x154, 0x165, 0x168, 0x17E,
  0x1A0, 0x1A1, 0x1AF, 0x1B0, 0x1CD, 0x1DC, 0x1DE, 0x1E3, 0x1E6, 0x1F0, 0x1F4, 0x1F5, 0x1F8, 0x21B, 0x21E, 0x21F,
  0x226, 0x233, 0x374, 0x374, 0x37E, 0x37E, 0x385, 0x38A, 0x38C, 0x38C, 0x38E, 0x390, 0x3AA, 0x3B0, 0x3CA, 0x3CE,
  0x3D3, 0x3D4, 0x400, 0x401, 0x403, 0x403, 0x407, 0x407, 0x40C, 0x40E, 0x419, 0x419, 0x439, 0x439, 0x450, 0x451,
  0x453, 0x453, 0x457, 0x457, 0x45C, 0x45E, 0x476, 0x477, 0x4C1, 0x4C2, 0x4D0, 0x4D3, 0x4D6, 0x4D7, 0x4DA, 0x4DF,
  0x4E2, 0x4E7, 0x4EA, 0x4F5, 0x4F8, 0x4F9, 0x1E00, 0x1E99, 0x1E9B, 0x1E9B, 0x1EA0, 0x1EF9, 0x1F00, 0x1F15,
  0x1F18, 0x1F1D, 0x1F20, 0x1F45, 0x1F48, 0x1F4D, 0x1F50, 0x1F57, 0x1F59, 0x1F59, 0x1F5B, 0x1F5B, 0x1F5D, 0x1F5D,
  0x1F5F, 0x1F7D, 0x1F80, 0x1FB4, 0x1FB6, 0x1FBC, 0x1FBE, 0x1FBE, 0x1FC1, 0x1FC4, 0x1FC6, 0x1FCC, 0x1FD0, 0x1FD3,
  0x1FD6, 0x1FDB, 0x1FE0, 0x1FEF, 0x1FF2, 0x1FF4, 0x1FF6, 0x1FFD, 0x2126, 0x2126, 0x212A, 0x212B, 0x2260, 0x2260,
  0x226E, 0x226F,
]
#endif
