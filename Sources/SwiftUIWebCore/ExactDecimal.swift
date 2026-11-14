// Exact decimal digits of a double, shared by `String(format:)` (WebFoundation) and `Text`'s number specifiers: a double is
// printed from its exact binary value, rounded half to even as the C library rounds.

/// The exact decimal expansion of a finite, positive double: `value = 0.d0 d1 d2 ... × 10^exponent`, with no leading zero.
package func _exactDecimal(_ value: Double) -> (digits: [UInt8], exponent: Int) {
  let bits = value.bitPattern
  let biased = Int((bits >> 52) & 0x7FF)
  var mantissa = bits & 0xF_FFFF_FFFF_FFFF
  let binaryExponent: Int
  if biased == 0 {
    binaryExponent = -1074
  } else {
    mantissa |= 1 << 52
    binaryExponent = biased - 1075
  }
  var number = _BigNatural(mantissa)
  if binaryExponent >= 0 {
    for _ in 0 ..< binaryExponent { number.multiply(by: 2) }
    let digits = number.decimalDigits()
    return (digits, digits.count)
  }
  // m / 2^k = m * 5^k / 10^k: the digits of m * 5^k, with the point moved k places left.
  for _ in 0 ..< -binaryExponent { number.multiply(by: 5) }
  let digits = number.decimalDigits()
  return (digits, digits.count + binaryExponent)
}

/// A non-negative integer as little-endian 32-bit limbs: just enough arithmetic to print a double exactly.
struct _BigNatural {
  private var limbs: [UInt32]

  init(_ value: UInt64) {
    limbs = [UInt32(truncatingIfNeeded: value), UInt32(truncatingIfNeeded: value >> 32)]
    trim()
  }

  mutating func multiply(by factor: UInt32) {
    var carry: UInt64 = 0
    for index in limbs.indices {
      let product = UInt64(limbs[index]) * UInt64(factor) + carry
      limbs[index] = UInt32(truncatingIfNeeded: product)
      carry = product >> 32
    }
    if carry > 0 { limbs.append(UInt32(carry)) }
  }

  /// Divides by `divisor` in place and returns the remainder.
  private mutating func divide(by divisor: UInt32) -> UInt32 {
    var remainder: UInt64 = 0
    for index in limbs.indices.reversed() {
      let current = (remainder << 32) | UInt64(limbs[index])
      limbs[index] = UInt32(current / UInt64(divisor))
      remainder = current % UInt64(divisor)
    }
    trim()
    return UInt32(remainder)
  }

  private mutating func trim() {
    while let last = limbs.last, last == 0, limbs.count > 1 { limbs.removeLast() }
    if limbs.isEmpty { limbs = [0] }
  }

  var isZero: Bool { limbs.count == 1 && limbs[0] == 0 }

  /// The decimal digits (values 0 to 9), most significant first.
  func decimalDigits() -> [UInt8] {
    var work = self
    var chunks: [UInt32] = []
    while !work.isZero { chunks.append(work.divide(by: 1_000_000_000)) }
    if chunks.isEmpty { return [0] }
    var digits: [UInt8] = []
    for (position, chunk) in chunks.reversed().enumerated() {
      let text = String(chunk)
      let padded = position == 0 ? text : String(repeating: "0", count: 9 - text.count) + text
      for byte in padded.utf8 { digits.append(byte - 48) }
    }
    return digits
  }
}

/// The digit at `index` of a digit sequence, zero outside it.
package func _digit(_ digits: [UInt8], _ index: Int) -> Character {
  guard index >= 0, index < digits.count else { return "0" }
  return Character(Unicode.Scalar(48 + digits[index]))
}

/// Rounds a digit sequence to its first `keep` digits, half to even on the exact value. A carry out of the leading digit
/// returns `[1]`, and the caller moves the exponent up by one.
package func _roundDigits(_ digits: [UInt8], keep: Int) -> (digits: [UInt8], carry: Bool) {
  if keep >= digits.count { return (digits, false) }
  if keep < 0 { return ([], false) }
  let next = digits[keep]
  let restNonZero = digits[(keep + 1)...].contains { $0 != 0 }
  let previousOdd = keep > 0 && digits[keep - 1] % 2 == 1
  var kept = Array(digits[0 ..< keep])
  guard next > 5 || (next == 5 && (restNonZero || previousOdd)) else { return (kept, false) }
  var position = keep - 1
  while position >= 0 {
    if kept[position] < 9 {
      kept[position] += 1
      return (kept, false)
    }
    kept[position] = 0
    position -= 1
  }
  return ([1], true)
}

/// `%f`: `precision` digits after the point.
package func _fixedBody(_ magnitude: Double, _ precision: Int, _ alternate: Bool) -> String {
  var text = ""
  var exponent = 1
  var rounded: [UInt8] = []
  if magnitude != 0 {
    let exact = _exactDecimal(magnitude)
    exponent = exact.exponent
    let result = _roundDigits(exact.digits, keep: exponent + precision)
    rounded = result.digits
    if result.carry { exponent += 1 }
  }
  if exponent <= 0 {
    text = "0"
  } else {
    for index in 0 ..< exponent { text.append(_digit(rounded, index)) }
  }
  if precision > 0 || alternate { text += "." }
  for offset in 0 ..< precision { text.append(_digit(rounded, exponent + offset)) }
  return text
}

