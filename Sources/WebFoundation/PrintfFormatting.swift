import SwiftUIWebCore
// printf-style formatting for `String(format:)` on the browser build: the conversions Foundation takes (`%d %i %u %x %X
// %o %c %s %@ %f %e %g`, their flags `- + space 0 #`, a width and a precision, `%n$` positions and `*` widths). A double
// is printed from its exact binary value, rounded half-to-even as the C library rounds, so `%.2f` of 0.125 is "0.12".

/// One argument of `String(format:)`, as the formatter reads it.
public enum _PrintfValue: Sendable {
  case signed(Int64)
  case unsigned(UInt64)
  case floating(Double)
  case text(String)
}

/// The argument types `String(format:)` takes on the browser build. Embedded Swift has no `CVarArg`, so the values
/// name themselves through this protocol.
public protocol _PrintfArgument {
  var _printfValue: _PrintfValue { get }
}

extension Int: _PrintfArgument { public var _printfValue: _PrintfValue { .signed(Int64(self)) } }
extension Int8: _PrintfArgument { public var _printfValue: _PrintfValue { .signed(Int64(self)) } }
extension Int16: _PrintfArgument { public var _printfValue: _PrintfValue { .signed(Int64(self)) } }
extension Int32: _PrintfArgument { public var _printfValue: _PrintfValue { .signed(Int64(self)) } }
extension Int64: _PrintfArgument { public var _printfValue: _PrintfValue { .signed(self) } }
extension UInt: _PrintfArgument { public var _printfValue: _PrintfValue { .unsigned(UInt64(self)) } }
extension UInt8: _PrintfArgument { public var _printfValue: _PrintfValue { .unsigned(UInt64(self)) } }
extension UInt16: _PrintfArgument { public var _printfValue: _PrintfValue { .unsigned(UInt64(self)) } }
extension UInt32: _PrintfArgument { public var _printfValue: _PrintfValue { .unsigned(UInt64(self)) } }
extension UInt64: _PrintfArgument { public var _printfValue: _PrintfValue { .unsigned(self) } }
extension Double: _PrintfArgument { public var _printfValue: _PrintfValue { .floating(self) } }
extension Float: _PrintfArgument { public var _printfValue: _PrintfValue { .floating(Double(self)) } }
extension String: _PrintfArgument { public var _printfValue: _PrintfValue { .text(self) } }

/// The flags, width and precision of one conversion.
private struct _PrintfSpec {
  var leftAlign = false
  var plus = false
  var space = false
  var zero = false
  var alternate = false
  var width = 0
  var precision: Int?
  /// The width in bits of an integer conversion's argument: a plain `%x` takes 32, `h` 16, `hh` 8 and `l`, `ll`, `q`, `j`,
  /// `z` and `t` 64. It decides how many bits a negative value prints as in `%u %x %X %o`, as in C.
  var integerBits = 32
}

/// Substitutes `arguments` into `format`: sequentially, or at the `%n$` position when one is given.
package func _formatPrintf(_ format: String, _ arguments: [_PrintfValue]) -> String {
  let chars = Array(format)
  var out = ""
  var next = 0
  var index = 0
  while index < chars.count {
    guard chars[index] == "%" else {
      out.append(chars[index])
      index += 1
      continue
    }
    if index + 1 < chars.count, chars[index + 1] == "%" {
      out.append("%")
      index += 2
      continue
    }
    var cursor = index + 1
    var position: Int?
    var scan = cursor
    var number = 0
    while scan < chars.count, let digit = _asciiDigit(chars[scan]) {
      number = min(number * 10 + digit, _printfFieldLimit)
      scan += 1
    }
    if scan > cursor, scan < chars.count, chars[scan] == "$" {
      position = number - 1
      cursor = scan + 1
    }
    var spec = _PrintfSpec()
    flags: while cursor < chars.count {
      switch chars[cursor] {
      case "-": spec.leftAlign = true
      case "+": spec.plus = true
      case " ": spec.space = true
      case "0": spec.zero = true
      case "#": spec.alternate = true
      default: break flags
      }
      cursor += 1
    }
    if cursor < chars.count, chars[cursor] == "*" {
      spec.width = _starArgument(arguments, &next)
      if spec.width < 0 {
        spec.leftAlign = true
        spec.width = -spec.width
      }
      cursor += 1
    } else {
      while cursor < chars.count, let digit = _asciiDigit(chars[cursor]) {
        spec.width = min(spec.width * 10 + digit, _printfFieldLimit)
        cursor += 1
      }
    }
    if cursor < chars.count, chars[cursor] == "." {
      cursor += 1
      var precision = 0
      if cursor < chars.count, chars[cursor] == "*" {
        precision = _starArgument(arguments, &next)
        cursor += 1
      } else {
        while cursor < chars.count, let digit = _asciiDigit(chars[cursor]) {
          precision = min(precision * 10 + digit, _printfFieldLimit)
          cursor += 1
        }
      }
      spec.precision = precision >= 0 ? precision : nil
    }
    // Length modifiers (`l`, `ll`, `h`, `z`, ...) do not change the value's printed form here.
    while cursor < chars.count, "hlLqjzt".contains(chars[cursor]) {
      switch chars[cursor] {
      case "h": spec.integerBits = spec.integerBits == 16 ? 8 : 16
      case "l", "q", "j", "z", "t": spec.integerBits = 64
      default: break
      }
      cursor += 1
    }
    guard cursor < chars.count else {
      out += String(chars[index ..< chars.count])
      break
    }
    let conversion = chars[cursor]
    cursor += 1
    guard "diuxXocsf@FeEgG".contains(conversion) else {
      out += String(chars[index ..< cursor])
      index = cursor
      continue
    }
    let argument: _PrintfValue?
    if let position {
      argument = position >= 0 && position < arguments.count ? arguments[position] : nil
    } else {
      argument = next < arguments.count ? arguments[next] : nil
      next += 1
    }
    // Many fields of the largest width would still add up to gigabytes: past the output limit, widths and precisions
    // shrink to what is left.
    let remaining = Swift.max(0, _printfOutputLimit - out.utf8.count)
    spec.width = Swift.min(spec.width, remaining)
    if let precision = spec.precision { spec.precision = Swift.min(precision, remaining) }
    if let argument { out += _renderPrintf(argument, conversion, spec) }
    index = cursor
  }
  return out
}

/// The largest width, precision or argument position a format may ask for. The format can come from data (a translation,
/// a server string): ten digits would overflow a 32-bit Int, and a width of a billion would ask for a gigabyte of padding.
let _printfFieldLimit = 100_000
/// The most padding one format adds in all: 16 MB of text, far past any message, short of exhausting the page.
let _printfOutputLimit = 16_000_000

/// The value of a `*` width or precision: the next sequential argument, as an integer.
private func _starArgument(_ arguments: [_PrintfValue], _ next: inout Int) -> Int {
  defer { next += 1 }
  guard next < arguments.count else { return 0 }
  // Bounded: Int is 32 bits in the browser build, and a width from data should not ask for gigabytes of padding.
  return Int(min(max(_integerValue(arguments[next]), Int64(-_printfFieldLimit)), Int64(_printfFieldLimit)))
}

private func _asciiDigit(_ character: Character) -> Int? { character._asciiDigitValue }

private func _integerValue(_ value: _PrintfValue) -> Int64 {
  switch value {
  case .signed(let number): return number
  case .unsigned(let number): return Int64(truncatingIfNeeded: number)
  case .floating(let number):
    if number.isNaN { return 0 }
    if number >= 9.2e18 { return Int64.max }
    if number <= -9.2e18 { return Int64.min }
    return Int64(number)
  case .text(let text): return Int64(text) ?? 0
  }
}

private func _unsignedValue(_ value: _PrintfValue) -> UInt64 {
  switch value {
  case .unsigned(let number): return number
  case .signed(let number): return UInt64(bitPattern: number)
  case .floating, .text: return UInt64(bitPattern: _integerValue(value))
  }
}

/// The low `bits` of `number`, read as an unsigned integer of that width.
private func _truncatedUnsigned(_ number: UInt64, bits: Int) -> UInt64 {
  switch bits {
  case 8: return UInt64(UInt8(truncatingIfNeeded: number))
  case 16: return UInt64(UInt16(truncatingIfNeeded: number))
  case 32: return UInt64(UInt32(truncatingIfNeeded: number))
  default: return number
  }
}

private func _doubleValue(_ value: _PrintfValue) -> Double {
  switch value {
  case .floating(let number): return number
  case .signed(let number): return Double(number)
  case .unsigned(let number): return Double(number)
  case .text(let text): return Double(text) ?? 0
  }
}

private func _renderPrintf(_ value: _PrintfValue, _ conversion: Character, _ spec: _PrintfSpec) -> String {
  switch conversion {
  case "s", "@":
    var text: String
    switch value {
    case .text(let string): text = string
    case .signed(let number): text = String(number)
    case .unsigned(let number): text = String(number)
    case .floating(let number): text = "\(number)"
    }
    if conversion == "s", let precision = spec.precision, text.count > precision { text = String(text.prefix(precision)) }
    return _padText(text, spec)
  case "c":
    let scalar = Unicode.Scalar(UInt32(truncatingIfNeeded: _integerValue(value))) ?? "?"
    return _padText(String(Character(scalar)), spec)
  case "d", "i":
    let number = _integerValue(value)
    let sign = number < 0 ? "-" : (spec.plus ? "+" : (spec.space ? " " : ""))
    let body = _integerBody(String(number.magnitude), spec.precision, number == 0)
    return _padNumber(sign: sign, body: body, spec, allowZero: spec.precision == nil)
  case "u", "x", "X", "o":
    // A negative value read as unsigned is its bit pattern at the argument's width (`%x` of -1 is ffffffff, `%lx` ffffffffffffffff).
    var number = _unsignedValue(value)
    if case .signed(let signed) = value, signed < 0 { number = _truncatedUnsigned(number, bits: spec.integerBits) }
    let radix = conversion == "o" ? 8 : (conversion == "u" ? 10 : 16)
    var body = _integerBody(String(number, radix: radix, uppercase: conversion == "X"), spec.precision, number == 0)
    var prefix = ""
    if spec.alternate {
      if conversion == "o", !body.hasPrefix("0") { body = "0" + body }
      if radix == 16, number != 0 { prefix = conversion == "X" ? "0X" : "0x" }
    }
    return _padNumber(sign: prefix, body: body, spec, allowZero: spec.precision == nil)
  default:
    return _renderFloating(_doubleValue(value), conversion, spec)
  }
}

/// The digits of an integer, with at least `precision` of them (a zero precision prints nothing for a zero value).
private func _integerBody(_ digits: String, _ precision: Int?, _ isZero: Bool) -> String {
  guard let precision else { return digits }
  if precision == 0 && isZero { return "" }
  return digits.count >= precision ? digits : String(repeating: "0", count: precision - digits.count) + digits
}

private func _renderFloating(_ value: Double, _ conversion: Character, _ spec: _PrintfSpec) -> String {
  let upper = conversion == "F" || conversion == "E" || conversion == "G"
  let negative = value.sign == .minus
  let sign = negative ? "-" : (spec.plus ? "+" : (spec.space ? " " : ""))
  guard value.isFinite else {
    let body = value.isNaN ? "nan" : "inf"
    return _padNumber(sign: sign, body: upper ? body.uppercased() : body, spec, allowZero: false)
  }
  let magnitude = abs(value)
  let precision = spec.precision ?? 6
  var body: String
  switch conversion {
  case "e", "E": body = _exponentialBody(magnitude, precision, spec.alternate)
  case "g", "G": body = _generalBody(magnitude, precision == 0 ? 1 : precision, spec.alternate)
  default: body = _fixedBody(magnitude, precision, spec.alternate)
  }
  if upper { body = body.uppercased() }
  return _padNumber(sign: sign, body: body, spec, allowZero: true)
}

/// Pads a number to the width: zeros go between the sign (or `0x`) and the digits, spaces outside or on the left when
/// the value is left-aligned.
private func _padNumber(sign: String, body: String, _ spec: _PrintfSpec, allowZero: Bool) -> String {
  let length = sign.count + body.count
  guard length < spec.width else { return sign + body }
  let fill = spec.width - length
  if spec.leftAlign { return sign + body + String(repeating: " ", count: fill) }
  if spec.zero && allowZero { return sign + String(repeating: "0", count: fill) + body }
  return String(repeating: " ", count: fill) + sign + body
}

private func _padText(_ text: String, _ spec: _PrintfSpec) -> String {
  let fill = spec.width - text.count
  guard fill > 0 else { return text }
  return spec.leftAlign ? text + String(repeating: " ", count: fill) : String(repeating: " ", count: fill) + text
}

/// `%e`: one digit, then `precision` digits, then the exponent with at least two digits.
private func _exponentialBody(_ magnitude: Double, _ precision: Int, _ alternate: Bool) -> String {
  var scientific = 0
  var rounded: [UInt8] = []
  if magnitude != 0 {
    let exact = _exactDecimal(magnitude)
    let result = _roundDigits(exact.digits, keep: precision + 1)
    rounded = result.digits
    scientific = exact.exponent - 1 + (result.carry ? 1 : 0)
  }
  var text = String(_digit(rounded, 0))
  if precision > 0 || alternate { text += "." }
  for offset in 0 ..< precision { text.append(_digit(rounded, offset + 1)) }
  let magnitudeOfExponent = scientific.magnitude
  text += "e" + (scientific < 0 ? "-" : "+") + (magnitudeOfExponent < 10 ? "0" : "") + String(magnitudeOfExponent)
  return text
}

/// `%g`: `%e` or `%f` with `precision` significant digits, whichever is shorter for the exponent, without trailing zeros
/// unless `#` is given.
private func _generalBody(_ magnitude: Double, _ precision: Int, _ alternate: Bool) -> String {
  var scientific = 0
  if magnitude != 0 {
    let exact = _exactDecimal(magnitude)
    let result = _roundDigits(exact.digits, keep: precision)
    scientific = exact.exponent - 1 + (result.carry ? 1 : 0)
  }
  var body = scientific < precision && scientific >= -4
    ? _fixedBody(magnitude, precision - 1 - scientific, alternate)
    : _exponentialBody(magnitude, precision - 1, alternate)
  if !alternate { body = _stripTrailingZeros(body) }
  return body
}

private func _stripTrailingZeros(_ body: String) -> String {
  guard body.contains(".") else { return body }
  var mantissa = Substring(body)
  var exponent = ""
  if let marker = body.firstIndex(of: "e") {
    mantissa = Substring(body[..<marker])
    exponent = String(body[marker...])
  }
  while mantissa.hasSuffix("0") { mantissa = mantissa.dropLast() }
  if mantissa.hasSuffix(".") { mantissa = mantissa.dropLast() }
  return String(mantissa) + exponent
}

// `String(format:)` on every host goes through `_formatPrintf`, so a flag or conversion means the same in every arity.
#if !hasFeature(Embedded)
public extension String {
  init(format: String, _ arguments: any CVarArg...) {
    self = _formatPrintf(format, arguments.map(_printfValue(of:)))
  }

  init(format: String, arguments: [any CVarArg]) {
    self = _formatPrintf(format, arguments.map(_printfValue(of:)))
  }

  /// The locale does not change the printf conversions, which are the C library's; it is accepted for Foundation's shape.
  init(format: String, locale: Locale?, _ arguments: any CVarArg...) {
    self = _formatPrintf(format, arguments.map(_printfValue(of:)))
  }

  init(format: String, locale: Locale?, arguments: [any CVarArg]) {
    self = _formatPrintf(format, arguments.map(_printfValue(of:)))
  }
}

/// The printf value of one variadic argument. Values that are not numbers or text print their description, as `%@` does.
private func _printfValue(of value: any CVarArg) -> _PrintfValue {
  if let argument = value as? any _PrintfArgument { return argument._printfValue }
  return .text(String(describing: value))
}
#else
// Embedded Swift has no variadic `CVarArg`: one to ten arguments, each one of the types above.
extension String {
  public init(format: String, _ a: some _PrintfArgument) {
    self = _formatPrintf(format, [a._printfValue])
  }

  public init(format: String, _ a: some _PrintfArgument, _ b: some _PrintfArgument) {
    self = _formatPrintf(format, [a._printfValue, b._printfValue])
  }

  public init(format: String, _ a: some _PrintfArgument, _ b: some _PrintfArgument, _ c: some _PrintfArgument) {
    self = _formatPrintf(format, [a._printfValue, b._printfValue, c._printfValue])
  }

  public init(format: String, _ a: some _PrintfArgument, _ b: some _PrintfArgument, _ c: some _PrintfArgument,
              _ d: some _PrintfArgument) {
    self = _formatPrintf(format, [a._printfValue, b._printfValue, c._printfValue, d._printfValue])
  }

  public init(format: String, _ a: some _PrintfArgument, _ b: some _PrintfArgument, _ c: some _PrintfArgument,
              _ d: some _PrintfArgument, _ e: some _PrintfArgument) {
    self = _formatPrintf(format, [a._printfValue, b._printfValue, c._printfValue, d._printfValue, e._printfValue])
  }

  public init(format: String, _ a: some _PrintfArgument, _ b: some _PrintfArgument, _ c: some _PrintfArgument,
              _ d: some _PrintfArgument, _ e: some _PrintfArgument, _ f: some _PrintfArgument) {
    self = _formatPrintf(format, [a._printfValue, b._printfValue, c._printfValue, d._printfValue, e._printfValue,
                                  f._printfValue])
  }

  public init(format: String, _ a: some _PrintfArgument, _ b: some _PrintfArgument, _ c: some _PrintfArgument,
              _ d: some _PrintfArgument, _ e: some _PrintfArgument, _ f: some _PrintfArgument, _ g: some _PrintfArgument) {
    self = _formatPrintf(format, [a._printfValue, b._printfValue, c._printfValue, d._printfValue, e._printfValue,
                                  f._printfValue, g._printfValue])
  }

  public init(format: String, _ a: some _PrintfArgument, _ b: some _PrintfArgument, _ c: some _PrintfArgument,
              _ d: some _PrintfArgument, _ e: some _PrintfArgument, _ f: some _PrintfArgument, _ g: some _PrintfArgument,
              _ h: some _PrintfArgument) {
    self = _formatPrintf(format, [a._printfValue, b._printfValue, c._printfValue, d._printfValue, e._printfValue,
                                  f._printfValue, g._printfValue, h._printfValue])
  }

  public init(format: String, _ a: some _PrintfArgument, _ b: some _PrintfArgument, _ c: some _PrintfArgument,
              _ d: some _PrintfArgument, _ e: some _PrintfArgument, _ f: some _PrintfArgument, _ g: some _PrintfArgument,
              _ h: some _PrintfArgument, _ i: some _PrintfArgument) {
    self = _formatPrintf(format, [a._printfValue, b._printfValue, c._printfValue, d._printfValue, e._printfValue,
                                  f._printfValue, g._printfValue, h._printfValue, i._printfValue])
  }

  public init(format: String, _ a: some _PrintfArgument, _ b: some _PrintfArgument, _ c: some _PrintfArgument,
              _ d: some _PrintfArgument, _ e: some _PrintfArgument, _ f: some _PrintfArgument, _ g: some _PrintfArgument,
              _ h: some _PrintfArgument, _ i: some _PrintfArgument, _ j: some _PrintfArgument) {
    self = _formatPrintf(format, [a._printfValue, b._printfValue, c._printfValue, d._printfValue, e._printfValue,
                                  f._printfValue, g._printfValue, h._printfValue, i._printfValue, j._printfValue])
  }
}
#endif
