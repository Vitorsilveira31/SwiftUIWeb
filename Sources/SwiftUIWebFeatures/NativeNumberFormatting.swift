// Foundation's number formatting computed in Swift for builds that have no browser to ask (a native build: tests,
// tools). The browser product formats with `Intl.NumberFormat` behind BrowserIO (`Tools/BrowserIO/text-format.mjs`);
// this file is compiled only where no browser can exist, so none of it, its locale tables included, reaches
// `app.wasm` (see `_TextHost` in TextHost.swift for the condition). It reads the same `name=value;...` requests as the
// browser's formatter and answers with the text Apple's Foundation prints on macOS 27, checked against it for every
// style, sign strategy, precision and grouping over the locales below.
#if !arch(wasm32)

/// Formats `text` (a number as Swift prints it: `28300.4`, `1e+21`, `-0.0`, `inf`, `nan`) with the `name=value;...`
/// options of `_NumberFormatOptions`, as Foundation does on Apple platforms; nil when the number or an option is
/// malformed (the same answers as `Tools/BrowserIO/text-format.mjs`).
func _swiftNumberFormat(_ text: String, options: String) -> String? {
  guard let request = _NativeNumberRequest(options) else { return nil }
  guard let number = _NativeDecimal(text) else { return nil }
  return request.format(number)
}

/// A decimal number as digits: the value is `0.d1d2...dn x 10^point`, with no leading or trailing zero digit (zero
/// has no digits). Swift's shortest round-trip text of a value is exact here, so rounding works on those digits.
struct _NativeDecimal {
  var negative = false
  var digits: [UInt8] = []
  var point = 0
  var special: Special?
  enum Special { case infinity, nan }

  init?(_ text: String) {
    var bytes = Array(text.utf8)
    guard !bytes.isEmpty else { return nil }
    var start = 0
    if bytes[0] == 43 || bytes[0] == 45 { negative = bytes[0] == 45; start = 1 }
    let word = String(decoding: bytes[start...].map { $0 >= 65 && $0 <= 90 ? $0 + 32 : $0 }, as: UTF8.self)
    if word == "inf" || word == "infinity" { special = .infinity; return }
    if word == "nan" { special = .nan; negative = false; return }
    bytes = Array(bytes[start...])
    var mantissa: [UInt8] = []
    var integerCount = 0
    var seenPoint = false
    var index = 0
    var sawDigit = false
    while index < bytes.count {
      let byte = bytes[index]
      if byte >= 48 && byte <= 57 {
        mantissa.append(byte - 48)
        if !seenPoint { integerCount += 1 }
        sawDigit = true
      } else if byte == 46 && !seenPoint {
        seenPoint = true
      } else {
        break
      }
      index += 1
    }
    // `1.` is a number, `.5` is one, `.` and `-` are not (the browser's pattern).
    guard sawDigit else { return nil }
    var exponent = 0
    if index < bytes.count {
      guard bytes[index] == 101 || bytes[index] == 69 else { return nil }
      index += 1
      var exponentNegative = false
      if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 { exponentNegative = bytes[index] == 45; index += 1 }
      let digitsStart = index
      while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 { exponent = exponent * 10 + Int(bytes[index] - 48); index += 1 }
      let count = index - digitsStart
      guard count >= 1, count <= 6, index == bytes.count else { return nil }
      if exponentNegative { exponent = -exponent }
    }
    var leading = 0
    while leading < mantissa.count, mantissa[leading] == 0 { leading += 1 }
    var trailing = mantissa.count
    while trailing > leading, mantissa[trailing - 1] == 0 { trailing -= 1 }
    digits = Array(mantissa[leading..<trailing])
    point = digits.isEmpty ? 0 : integerCount - leading + exponent
  }

  var isZero: Bool { special == nil && digits.isEmpty }

  /// Keeps the first `count` digits, rounding half to even on the digits dropped.
  mutating func round(keeping count: Int) {
    guard special == nil, count < digits.count else { return }
    if count < 0 { digits = []; point = 0; return }
    let next = digits[count]
    let rest = digits[(count + 1)...].contains { $0 != 0 }
    let lastOdd = count > 0 && digits[count - 1] % 2 == 1
    digits.removeSubrange(count...)
    if next > 5 || (next == 5 && (rest || lastOdd)) {
      var index = digits.count - 1
      while index >= 0 && digits[index] == 9 { digits[index] = 0; index -= 1 }
      if index >= 0 { digits[index] += 1 } else { digits.insert(1, at: 0); point += 1 }
    }
    while let last = digits.last, last == 0 { digits.removeLast() }
    if digits.isEmpty { point = 0 }
  }
}

/// The parsed options of one formatting request.
struct _NativeNumberRequest {
  enum Style { case decimal, percent, currency }
  var style = Style.decimal
  var scale = 2
  var grouping = true
  var sign = "auto"
  var currency = ""
  var locale = ""
  var minInt = 1
  var maxInt: Int?
  var minFrac: Int?
  var maxFrac: Int?
  var minSig: Int?
  var maxSig: Int?
  /// The infinity of the locale asked for, when another locale's layout writes the amount.
  var infinity: String?

  init?(_ text: String) {
    for pair in text.split(separator: ";", omittingEmptySubsequences: true) {
      guard let equals = pair.firstIndex(of: "=") else { return nil }
      let name = String(pair[..<equals])
      let value = String(pair[pair.index(after: equals)...])
      switch name {
      case "style":
        switch value {
        case "decimal": style = .decimal
        case "percent": style = .percent
        case "currency": style = .currency
        default: return nil
        }
      case "currency":
        guard value.utf8.count == 3, value.utf8.allSatisfy({ $0 >= 65 && $0 <= 90 }) else { return nil }
        currency = value
      case "locale": locale = value
      case "grouping":
        guard value == "auto" || value == "never" else { return nil }
        grouping = value == "auto"
      case "sign":
        guard ["auto", "always", "alwaysExceptZero", "never", "accounting", "accountingAlways", "accountingExceptZero"].contains(value) else { return nil }
        sign = value
      case "minFrac", "maxFrac", "minInt", "maxInt", "minSig", "maxSig", "scale":
        guard let count = Self.count(value) else { return nil }
        switch name {
        case "minFrac": minFrac = count
        case "maxFrac": maxFrac = count
        case "minInt": minInt = count
        case "maxInt": maxInt = count
        case "minSig": minSig = count
        case "maxSig": maxSig = count
        default: scale = count
        }
      default: return nil
      }
    }
  }

  /// A count of one to three ASCII digits, at most 255.
  private static func count(_ value: String) -> Int? {
    let bytes = Array(value.utf8)
    guard (1...3).contains(bytes.count), bytes.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
    let count = bytes.reduce(0) { $0 * 10 + Int($1 - 48) }
    return count <= 255 ? count : nil
  }

  func format(_ value: _NativeDecimal) -> String {
    let conventions = _NativeNumberConventions.named(locale)
    var number = value
    if style == .percent, number.special == nil, !number.isZero { number.point += scale }
    let body: String
    if let special = number.special {
      body = special == .nan ? "NaN" : infinity ?? conventions.infinity
    } else {
      body = digitsText(&number, conventions, grouping: grouping && !conventions.group.isEmpty)
    }
    // A sign follows the rounded value: -0.001 to no fraction is a negative zero.
    let isZero = number.isZero
    let accounting = sign.hasPrefix("accounting")
    var prefix = ""
    var parentheses = false
    do {
      // NaN takes a sign only when every value does (`+NaN`), as Foundation writes it.
      let showsSign: Bool
      switch sign {
      case "never": showsSign = false
      case "always", "accountingAlways": showsSign = true
      case "alwaysExceptZero", "accountingExceptZero": showsSign = !isZero && number.special != .nan
      default: showsSign = number.negative
      }
      if showsSign {
        if number.negative {
          if accounting && style == .currency && conventions.accountingParentheses { parentheses = true } else { prefix = "-" }
        } else {
          prefix = "+"
        }
      }
    }
    switch style {
    case .decimal:
      return prefix + body
    case .percent:
      return prefix + body + conventions.percentSuffix
    case .currency:
      // A locale whose accounting form is another locale's (en_US_POSIX writes `(€1,234.50)`) formats it as that one.
      if accounting, let layout = conventions.accountingLayout {
        var other = self
        other.locale = layout
        other.infinity = conventions.infinity
        return other.format(value)
      }
      let symbol = conventions.symbol(currency)
      let amount: String
      if conventions.currencyBefore {
        var gap = conventions.currencyGap
        // CLDR currency spacing: a symbol ending in a letter is kept apart from the digits (`CHF 1.50`, `$1.50`).
        if gap.isEmpty, let last = symbol.unicodeScalars.last, !_isSymbolScalar(last),
           let first = body.unicodeScalars.first, first.value >= 48 && first.value <= 57 {
          gap = "\u{A0}"
        }
        amount = symbol + gap + body
      } else {
        amount = body + "\u{A0}" + symbol
      }
      return parentheses ? "(" + amount + ")" : prefix + amount
    }
  }

  /// The digits of `number` with its precision, grouping and separators; `number` is left rounded.
  private func digitsText(_ number: inout _NativeDecimal, _ conventions: _NativeNumberConventions, grouping: Bool) -> String {
    var fractionMinimum = 0
    var significantMinimum = 0
    if minSig != nil || maxSig != nil {
      // Significant digits take over from fraction digits, as they do in Foundation.
      let minimum = Swift.max(1, Swift.min(minSig ?? 1, 21))
      let maximum = Swift.max(minimum, Swift.max(1, Swift.min(maxSig ?? 21, 21)))
      number.round(keeping: maximum)
      significantMinimum = minimum
    } else {
      var minimum = minFrac
      var maximum = maxFrac
      if minimum == nil && maximum != nil { minimum = 0 }
      if style == .currency {
        let digits = _currencyDigits(currency)
        if minimum == nil { minimum = digits }
        if maximum == nil { maximum = Swift.max(minimum ?? digits, digits) }
      } else {
        if maximum == nil { maximum = Swift.max(minimum ?? 0, 6) }
        if minimum == nil { minimum = 0 }
      }
      let lower = Swift.min(minimum ?? 0, 100)
      let upper = Swift.min(Swift.max(maximum ?? 0, lower), 100)
      number.round(keeping: number.point + upper)
      fractionMinimum = lower
    }
    var integer: [UInt8] = []
    var fraction: [UInt8] = []
    if number.point > 0 {
      for index in 0..<number.point { integer.append(index < number.digits.count ? number.digits[index] : 0) }
      if number.point < number.digits.count { fraction = Array(number.digits[number.point...]) }
    } else {
      fraction = Array(repeating: 0, count: -number.point) + number.digits
    }
    if significantMinimum > 0 {
      let shown = integer.isEmpty ? (number.isZero ? 1 + fraction.count : fraction.count + number.point) : integer.count + fraction.count
      if shown < significantMinimum { fraction += Array(repeating: 0, count: significantMinimum - shown) }
    } else if fraction.count < fractionMinimum {
      fraction += Array(repeating: 0, count: fractionMinimum - fraction.count)
    }
    // Foundation keeps the last `maxInt` digits, drops the zeros before them down to `minInt` (21 at most) or pads up
    // to it, and writes a lone zero rather than nothing (`.5` has no integer digit, `0` keeps its one).
    if let maxInt, integer.count > maxInt { integer = Array(integer.suffix(maxInt)) }
    let minimumInteger = Swift.min(minInt, 21)
    while integer.count > minimumInteger, integer.first == 0 { integer.removeFirst() }
    if integer.count < minimumInteger { integer = Array(repeating: 0, count: minimumInteger - integer.count) + integer }
    if integer.isEmpty && fraction.isEmpty { integer = [0] }
    let digitText = { (slice: ArraySlice<UInt8>) in String(decoding: slice.map { $0 + 48 }, as: UTF8.self) }
    var integerText = digitText(integer[...])
    if grouping && integer.count >= 3 + conventions.minimumGrouping {
      var groups: [String] = []
      var end = integer.count
      while end > 0 {
        let start = Swift.max(0, end - 3)
        groups.insert(digitText(integer[start..<end]), at: 0)
        end = start
      }
      integerText = groups.joined(separator: conventions.group)
    }
    if fraction.isEmpty { return integerText }
    return integerText + conventions.decimal + digitText(fraction[...])
  }
}

/// A currency sign (Unicode category Sc, Sm, Sk, So): no space is put between it and the digits.
private func _isSymbolScalar(_ scalar: Unicode.Scalar) -> Bool {
  switch scalar.properties.generalCategory {
  case .currencySymbol, .mathSymbol, .modifierSymbol, .otherSymbol: return true
  default: return false
  }
}

/// The fraction digits of a currency (ISO 4217, as Foundation shows them).
private func _currencyDigits(_ code: String) -> Int {
  switch code {
  case "AFN", "ALL", "BIF", "CLP", "COP", "DJF", "GNF", "HUF", "IDR", "IQD", "IRR", "ISK", "JPY", "KMF", "KPW", "KRW",
       "LAK", "LBP", "MGA", "MMK", "PKR", "PYG", "RSD", "RWF", "SLL", "SOS", "SYP", "UGX", "VND", "VUV", "XAF", "XOF",
       "XPF", "YER":
    return 0
  case "BHD", "JOD", "KWD", "LYD", "OMR", "TND":
    return 3
  default:
    return 2
  }
}

/// How a locale writes numbers (CLDR data as Apple's Foundation ships it).
struct _NativeNumberConventions {
  var decimal = "."
  var group = ","
  /// Digits the integer part needs before it is grouped beyond the first group: 1 groups `1,234`, 2 only `12.345`.
  var minimumGrouping = 1
  var percentSuffix = "%"
  var currencyBefore = true
  /// Between a leading symbol and the digits; empty applies CLDR's currency spacing.
  var currencyGap = ""
  var accountingParentheses = false
  /// The locale whose layout writes an accounting amount in parentheses, when it is not this one.
  var accountingLayout: String?
  var infinity = "\u{221E}"
  var symbols = ""

  func symbol(_ code: String) -> String {
    for entry in symbols.split(separator: ";") {
      let parts = entry.split(separator: "=", maxSplits: 1)
      if parts.count == 2, parts[0] == code { return String(parts[1]) }
    }
    return code
  }

  private static let englishSymbols = "AUD=A$;BRL=R$;CAD=CA$;CNY=CN\u{A5};EUR=\u{20AC};GBP=\u{A3};HKD=HK$;ILS=\u{20AA};INR=\u{20B9};JPY=\u{A5};KRW=\u{20A9};MXN=MX$;NZD=NZ$;PHP=\u{20B1};SAR=\u{20C1};TWD=NT$;USD=$;VND=\u{20AB};XAF=FCFA;XCD=EC$;XCG=Cg.;XOF=F\u{202F}CFA;XPF=CFPF"
  private static let portugueseSymbols = "AUD=AU$;BRL=R$;CAD=CA$;CNY=CN\u{A5};EUR=\u{20AC};GBP=\u{A3};HKD=HK$;ILS=\u{20AA};INR=\u{20B9};JPY=JP\u{A5};KRW=\u{20A9};MXN=MX$;NZD=NZ$;SAR=\u{20C1};THB=\u{E3F};TWD=NT$;USD=US$;VND=\u{20AB};XAF=FCFA;XCD=EC$;XCG=Cg.;XOF=F\u{202F}CFA;XPF=CFPF"

  static let english = _NativeNumberConventions(accountingParentheses: true, symbols: englishSymbols)
  static let britishEnglish = _NativeNumberConventions(accountingParentheses: true, symbols: "USD=US$;JPY=JP\u{A5};" + englishSymbols)
  static let posix = _NativeNumberConventions(group: "", currencyGap: "\u{A0}", accountingParentheses: true, accountingLayout: "en_US", infinity: "INF", symbols: englishSymbols)
  static let portuguese = _NativeNumberConventions(decimal: ",", group: ".", currencyGap: "\u{A0}", symbols: portugueseSymbols)
  static let europeanPortuguese = _NativeNumberConventions(decimal: ",", group: "\u{A0}", minimumGrouping: 2, currencyBefore: false, accountingParentheses: true, symbols: portugueseSymbols)
  static let german = _NativeNumberConventions(decimal: ",", group: ".", percentSuffix: "\u{A0}%", currencyBefore: false, symbols: "AUD=AU$;BRL=R$;CAD=CA$;CNY=CN\u{A5};EUR=\u{20AC};GBP=\u{A3};HKD=HK$;ILS=\u{20AA};INR=\u{20B9};JPY=\u{A5};KRW=\u{20A9};MXN=MX$;NZD=NZ$;SAR=\u{20C1};THB=\u{E3F};TWD=NT$;USD=$;VND=\u{20AB};XAF=FCFA;XCD=EC$;XCG=Cg.;XOF=F\u{202F}CFA;XPF=CFPF")
  static let french = _NativeNumberConventions(decimal: ",", group: "\u{202F}", percentSuffix: "\u{A0}%", currencyBefore: false, accountingParentheses: true, symbols: "ARS=$AR;AUD=$AU;BMD=$BM;BND=$BN;BRL=R$;BZD=$BZ;CAD=$CA;CLP=$CL;COP=$CO;EUR=\u{20AC};FJD=$FJ;FKP=\u{A3}FK;GBP=\u{A3}GB;GIP=\u{A3}GI;ILS=\u{20AA};INR=\u{20B9};KRW=\u{20A9};LBP=\u{A3}LB;MXN=$MX;NAD=$NA;NZD=$NZ;SAR=\u{20C1};SBD=$SB;SGD=$SG;SRD=$SR;TTD=$TT;USD=$US;UYU=$UY;VND=\u{20AB};WST=$WS;XAF=FCFA;XCG=Cg.;XOF=F\u{202F}CFA;XPF=FCFP")
  static let spanish = _NativeNumberConventions(decimal: ",", group: ".", minimumGrouping: 2, percentSuffix: "\u{A0}%", currencyBefore: false, symbols: "EUR=\u{20AC};SAR=\u{20C1};THB=\u{E3F};USD=US$;VND=\u{20AB};XCG=Cg.;XPF=CFPF")
  static let italian = _NativeNumberConventions(decimal: ",", group: ".", minimumGrouping: 2, currencyBefore: false, symbols: "AUD=A$;CAD=CA$;CNY=CN\u{A5};EUR=\u{20AC};GBP=\u{A3};ILS=\u{20AA};NZD=NZ$;PHP=\u{20B1};SAR=\u{20C1};THB=\u{E3F};XAF=FCFA;XCD=EC$;XCG=Cf;XOF=F\u{202F}CFA;XPF=CFPF")
  static let japanese = _NativeNumberConventions(accountingParentheses: true, symbols: "AUD=A$;BRL=R$;CAD=CA$;CNY=\u{5143};EUR=\u{20AC};GBP=\u{A3};HKD=HK$;ILS=\u{20AA};INR=\u{20B9};JPY=\u{A5};KRW=\u{20A9};MXN=MX$;NZD=NZ$;SAR=\u{20C1};TWD=NT$;USD=$;VND=\u{20AB};XAF=FCFA;XCD=EC$;XCG=Cg;XOF=F\u{202F}CFA;XPF=CFPF")

  /// The conventions of a locale identifier (`pt_BR`, `pt-BR`, `de_DE@currency=EUR`). A region this table does not
  /// list writes as its language's main one; a language it does not know, as Foundation's root locale. The empty
  /// identifier (`Locale.current`, which has no visitor outside a browser) is en_US.
  static func named(_ identifier: String) -> _NativeNumberConventions {
    let tag = identifier.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
    let parts = tag.split(whereSeparator: { $0 == "_" || $0 == "-" }).map { String($0) }
    guard let first = parts.first else { return english }
    let language = first.lowercased()
    let rest = parts.dropFirst().map { $0.uppercased() }
    let region = rest.first { $0.utf8.count == 2 || ($0.utf8.count == 3 && $0.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }) }
    switch language {
    case "en":
      if rest.contains("POSIX") { return posix }
      return region == "GB" ? britishEnglish : english
    case "pt": return region == "PT" ? europeanPortuguese : portuguese
    case "de": return german
    case "fr": return french
    case "es": return spanish
    case "it": return italian
    case "ja": return japanese
    default: return posix
    }
  }
}
#endif
