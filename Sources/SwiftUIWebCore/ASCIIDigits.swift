// The value of an ASCII digit, read from the character's bytes.
//
// `Character.wholeNumberValue` and `isNumber` answer for every numeric character in Unicode (`٣`, `½`, `Ⅻ`), so they link
// the standard library's numeric property tables into the browser build. The framework's own parsers (format
// specifiers, CSS colors, state keys) only accept ASCII digits, and read them here instead.
extension Character {
  package var _asciiDigitValue: Int? {
    let bytes = utf8
    guard bytes.count == 1, let byte = bytes.first, byte >= 0x30, byte <= 0x39 else { return nil }
    return Int(byte &- 0x30)
  }
}
