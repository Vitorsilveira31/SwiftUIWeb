import Testing
@testable import SwiftUIWebInternationalization
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

/// Without a browser (a native build, these tests) the number format styles and `folding(options:locale:)` are
/// answered in Swift, with the output of Apple's Foundation on macOS: no `Intl` or `String.normalize` to ask.
/// Every expected value here was printed by Foundation.
@Suite(.serialized)
@MainActor
struct NativeTextFormattingTests {
  private let brazil = Locale(identifier: "pt_BR")
  private let unitedStates = Locale(identifier: "en_US")

  @Test
  func brazilianNumbersCurrencyAndPercentMatchFoundation() {
    #expect(_TextHost.formatNumber != nil, "a native build starts with the Swift formatter")
    #expect(28_300.formatted(.number.locale(brazil)) == "28.300")
    #expect(28_300.4.formatted(.number.locale(brazil)) == "28.300,4")
    #expect(28_300.4.formatted(.number.precision(.fractionLength(0)).locale(brazil)) == "28.300")
    // Foundation separates the symbol with a no-break space (U+00A0) in pt-BR.
    #expect(1027.formatted(.currency(code: "BRL").locale(brazil)) == "R$\u{A0}1.027,00")
    #expect(1027.0.formatted(.currency(code: "BRL").locale(brazil)) == "R$\u{A0}1.027,00")
    #expect(1027.5.formatted(.currency(code: "BRL").locale(brazil)) == "R$\u{A0}1.027,50")
    #expect(1027.0.formatted(.currency(code: "BRL").precision(.fractionLength(0)).locale(brazil)) == "R$\u{A0}1.027")
    #expect((-22.0).formatted(.currency(code: "BRL").precision(.fractionLength(0)).locale(brazil)) == "-R$\u{A0}22")
    #expect((-22.0).formatted(.currency(code: "BRL").locale(brazil)) == "-R$\u{A0}22,00")
    #expect(12.0.formatted(.currency(code: "USD").precision(.fractionLength(0)).locale(brazil)) == "US$\u{A0}12")
    #expect(0.736.formatted(.percent.precision(.fractionLength(0)).locale(brazil)) == "74%")
    #expect(0.736.formatted(.percent.locale(brazil)) == "73,6%")
    #expect(0.7456.formatted(.percent.locale(brazil)) == "74,56%")
    #expect(Int.max.formatted(.number.locale(brazil)) == "9.223.372.036.854.775.807")
  }

  @Test
  func americanNumbersCurrencyAndPercentMatchFoundation() {
    #expect(1_234_567.891.formatted(.number.locale(unitedStates)) == "1,234,567.891")
    #expect(1027.5.formatted(.currency(code: "USD").locale(unitedStates)) == "$1,027.50")
    #expect(1027.5.formatted(.currency(code: "BRL").locale(unitedStates)) == "R$1,027.50")
    #expect(1.5.formatted(.currency(code: "CHF").locale(unitedStates)) == "CHF\u{A0}1.50")
    #expect((-22.0).formatted(.currency(code: "USD").sign(strategy: .accounting).locale(unitedStates)) == "($22.00)")
    #expect(0.0.formatted(.currency(code: "USD").sign(strategy: .always()).locale(unitedStates)) == "+$0.00")
    #expect(0.736.formatted(.percent.locale(unitedStates)) == "73.6%")
    #expect(7.formatted(.percent.locale(unitedStates)) == "7%")
    #expect(1234.5678.formatted(.number.precision(.significantDigits(3)).locale(unitedStates)) == "1,230")
    #expect(12.formatted(.number.precision(.integerLength(4)).locale(unitedStates)) == "0,012")
    #expect(28_300.formatted(.number.precision(.integerLength(0...2)).locale(unitedStates)) == "0")
    #expect(Double.nan.formatted(.currency(code: "USD").locale(unitedStates)) == "$NaN")
    #expect((-0.0).formatted(.number.locale(unitedStates)) == "-0")
  }

  /// `Locale.current` has no visitor outside a browser: the native build formats it as en_US.
  @Test
  func theCurrentLocaleFormatsAsAmericanEnglish() {
    #expect(0.736.formatted(.percent) == "73.6%")
    #expect(1234.5.formatted() == "1,234.5")
    #expect(1027.formatted(.currency(code: "BRL")) == "R$1,027.00")
  }

  /// A locale missing from the native tables writes as its language's main region, then as Foundation's root.
  @Test
  func otherLocalesFollowTheirLanguageOrTheRoot() {
    #expect(1234.5.formatted(.number.locale(Locale(identifier: "pt"))) == "1.234,5")
    #expect(1234.5.formatted(.number.locale(Locale(identifier: "pt-BR"))) == "1.234,5")
    #expect(1234.5.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))) == "1234.5")
    #expect(Double.infinity.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))) == "INF")
    #expect(1234.5.formatted(.currency(code: "EUR").locale(Locale(identifier: "en_US_POSIX"))) == "\u{20AC}\u{A0}1234.50")
    #expect((-1234.5).formatted(.currency(code: "EUR").sign(strategy: .accounting).locale(Locale(identifier: "en_US_POSIX"))) == "(\u{20AC}1,234.50)")
  }

  /// The cases `Tools/test-text-format.mjs` checks the browser's formatter with: the same text and options give the
  /// same answer without the browser.
  @Test
  func theBrowserCasesFormatTheSameWithoutTheBrowser() {
    for (text, options, expected) in Self.foundationCases {
      #expect(_swiftUIWebFormatNumber(text, options: options) == expected, "\(text) \(options)")
    }
    let huge = _swiftUIWebFormatNumber("1e+300", options: "locale=en_US")
    #expect(huge.hasPrefix("1,000,000,000,000"))
    #expect(huge.count == 401)
  }

  @Test
  func malformedNumbersAndOptionsKeepThePlainText() {
    for (text, options) in [("abc", ""), ("1.5", "style=hex"), ("1.5", "maxFrac=x"), ("", "")] {
      #expect(_swiftUIWebFormatNumber(text, options: options) == text)
    }
    for options in ["maxFrac=1234", "maxFrac=", "maxFrac=300", "grouping=sometimes", "sign=bogus", "unknown=1", "noequals", "currency=usd"] {
      #expect(_swiftUIWebFormatNumber("1.5", options: options) == "1.5", "\(options)")
    }
    for text in ["1e", "1e+", "1e1234567", "1.2.3", "-", "1x", "0x10", " 1", "1 "] {
      #expect(_swiftUIWebFormatNumber(text, options: "") == text, "\(text)")
    }
  }

  @Test
  func foldingMatchesFoundation() {
    #expect(_TextHost.fold != nil, "a native build starts with the Swift folding")
    let both: String.CompareOptions = [.diacriticInsensitive, .caseInsensitive]
    #expect("Maré".folding(options: both, locale: nil) == "mare")
    #expect("Maré".folding(options: .diacriticInsensitive, locale: nil) == "Mare")
    #expect("Maré".folding(options: .caseInsensitive, locale: nil) == "maré")
    // A character outside ASCII (the middle dot) no longer leaves the whole text unfolded.
    #expect("Telenovela · Suspense".folding(options: both, locale: nil) == "telenovela · suspense")
    #expect("Ação à vontade, ÉPICO".folding(options: both, locale: nil) == "acao a vontade, epico")
    #expect("Čeština Ÿ Ёлка й".folding(options: both, locale: nil) == "cestina y елка и")
    // Case folding, not lowercasing: ß and ẞ are "ss", the ligature ﬁ is "fi", a final sigma is σ.
    #expect("Straße Ærø Þór 日本 🙂".folding(options: both, locale: nil) == "strasse ærø þor 日本 🙂")
    #expect("ẞ ﬁ ΟΔΟΣ".folding(options: .caseInsensitive, locale: nil) == "ss fi οδοσ")
    #expect("Łódź đ Ħ ı İ".folding(options: both, locale: nil) == "łodz đ ħ ı i")
    #expect("İ".folding(options: .caseInsensitive, locale: nil) == "i\u{307}")
    #expect("ế ά Ά".folding(options: .diacriticInsensitive, locale: nil) == "e α Α")
    // Decomposed marks fold like precomposed letters; a lone mark at the start stays.
    #expect("Mare\u{301}".folding(options: .diacriticInsensitive, locale: nil) == "Mare")
    #expect("Mare\u{301}".folding(options: .caseInsensitive, locale: nil) == "mare\u{301}")
    #expect("\u{301}".folding(options: both, locale: nil) == "\u{301}")
    // Other scripts keep their marks: kana voicing, Hangul, Hebrew points; emoji keep their presentation.
    #expect("が 한국어 שָׁלוֹם ❤️".folding(options: both, locale: nil) == "が 한국어 שָׁלוֹם ❤️")
    #expect("日\u{301}".folding(options: .diacriticInsensitive, locale: nil) == "日")
    #expect("\u{5D0}\u{596}\u{5B8}".folding(options: .diacriticInsensitive, locale: nil) == "\u{5D0}\u{5B8}\u{596}")
    #expect("Ꭰ".folding(options: .caseInsensitive, locale: nil) == "ꭰ")
    #expect("Å Ω K ≠".folding(options: both, locale: nil) == "a ω k =")
    #expect("".folding(options: both, locale: nil) == "")
  }

  private static let foundationCases: [(text: String, options: String, expected: String)] = [
    ("1027.5", "style=currency;currency=BRL;locale=pt_BR;minFrac=0;maxFrac=2", "R$\u{A0}1.027,5"),
    ("1027", "style=currency;currency=BRL;locale=pt_BR;minFrac=0;maxFrac=2", "R$\u{A0}1.027"),
    ("12", "style=currency;currency=USD;locale=pt_BR;minFrac=0;maxFrac=0", "US$\u{A0}12"),
    ("1.5", "style=currency;currency=XYZ;locale=pt_BR", "XYZ\u{A0}1,50"),
    ("1234.5", "style=currency;currency=JPY;locale=pt_BR", "JP\u{A5}\u{A0}1.234"),
    ("1027.5", "style=currency;currency=BRL;locale=pt_BR;sign=always", "+R$\u{A0}1.027,50"),
    ("-22", "style=currency;currency=BRL;locale=pt_BR;sign=never", "R$\u{A0}22,00"),
    ("-22", "style=currency;currency=EUR;locale=pt_BR;sign=accounting", "-\u{20AC}\u{A0}22,00"),
    ("1027.5", "style=currency;currency=USD;locale=en_US", "$1,027.50"),
    ("1027.5", "style=currency;currency=BRL;locale=en_US", "R$1,027.50"),
    ("-1.5", "style=currency;currency=USD;locale=en_US", "-$1.50"),
    ("-22", "style=currency;currency=USD;locale=en_US;sign=accounting", "($22.00)"),
    ("22", "style=currency;currency=USD;locale=en_US;sign=accounting", "$22.00"),
    ("1.5", "style=currency;currency=CHF;locale=en_US", "CHF\u{A0}1.50"),
    ("1234.5", "style=currency;currency=KRW;locale=en_US", "\u{20A9}1,234"),
    ("1234.5", "style=currency;currency=USD;locale=en_GB", "US$1,234.50"),
    ("1027.5", "style=currency;currency=EUR;locale=de_DE", "1.027,50\u{A0}\u{20AC}"),
    ("1234.5", "style=currency;currency=EUR;locale=fr_FR", "1\u{202F}234,50\u{A0}\u{20AC}"),
    ("-22", "style=currency;currency=EUR;locale=fr_FR;sign=accounting", "(22,00\u{A0}\u{20AC})"),
    ("1234.5", "style=currency;currency=EUR;locale=es_ES", "1234,50\u{A0}\u{20AC}"),
    ("12345.5", "style=currency;currency=USD;locale=it_IT", "12.345,50\u{A0}USD"),
    ("1234.5", "style=currency;currency=JPY;locale=ja_JP", "\u{A5}1,234"),
    ("nan", "style=currency;currency=USD;locale=en_US", "$NaN"),
    ("28300", "locale=pt_BR", "28.300"),
    ("28300.4", "locale=pt_BR", "28.300,4"),
    ("1234567.891", "locale=en_US", "1,234,567.891"),
    ("0.30000000000000004", "locale=en_US", "0.3"),
    ("123456789.12345679", "locale=en_US", "123,456,789.123457"),
    ("1e-07", "locale=en_US", "0"),
    ("1e+21", "locale=en_US", "1,000,000,000,000,000,000,000"),
    ("1234.5", "locale=fr_FR", "1\u{202F}234,5"),
    ("1234.5", "locale=es_ES", "1234,5"),
    ("12345.5", "locale=es_ES", "12.345,5"),
    ("12345.5", "locale=pt_PT", "12\u{A0}345,5"),
    ("1000000.5", "locale=en_US;grouping=never", "1000000.5"),
    ("-1234.5", "locale=en_US", "-1,234.5"),
    ("-0.0", "locale=en_US", "-0"),
    ("-0.001", "locale=en_US;maxFrac=0", "-0"),
    ("inf", "locale=en_US", "\u{221E}"),
    ("-inf", "locale=en_US", "-\u{221E}"),
    ("nan", "locale=en_US", "NaN"),
    ("0.74", "style=percent;locale=pt_BR", "74%"),
    ("0.7456", "style=percent;locale=pt_BR", "74,56%"),
    ("0.7456", "style=percent;locale=pt_BR;maxFrac=0", "75%"),
    ("0.736", "style=percent;locale=pt_BR;minFrac=0;maxFrac=0", "74%"),
    ("-0.74", "style=percent;locale=pt_BR", "-74%"),
    ("0.74", "style=percent;locale=de_DE", "74\u{A0}%"),
    ("7", "style=percent;locale=en_US;scale=0;maxFrac=0", "7%"),
    ("1e-07", "style=percent;locale=en_US", "0.00001%"),
    ("0.123456789", "style=percent;locale=en_US", "12.345679%"),
    ("inf", "style=percent;locale=en_US", "\u{221E}%"),
    ("2.5", "locale=en_US;maxFrac=0", "2"),
    ("3.5", "locale=en_US;maxFrac=0", "4"),
    ("0.5", "locale=en_US;maxFrac=0", "0"),
    ("1.005", "locale=en_US;minFrac=2;maxFrac=2", "1.00"),
    ("1.015", "locale=en_US;minFrac=2;maxFrac=2", "1.02"),
    ("0.745", "style=percent;locale=en_US;maxFrac=0", "74%"),
    ("0.735", "style=percent;locale=en_US;maxFrac=0", "74%"),
    ("9.999", "locale=en_US;maxFrac=2", "10"),
    ("999.5", "locale=en_US;maxFrac=0", "1,000"),
    ("0.0004", "locale=en_US;maxFrac=3", "0"),
    ("0.0006", "locale=en_US;maxFrac=3", "0.001"),
    ("1.5", "locale=en_US;minFrac=2;maxFrac=4", "1.50"),
    ("2", "locale=pt_BR;minFrac=1;maxFrac=3", "2,0"),
    ("12", "locale=en_US;minInt=4", "0,012"),
    ("5.25", "locale=en_US;minInt=2;minFrac=1;maxFrac=1", "05.2"),
    ("123", "locale=en_US;minInt=0;maxInt=2", "23"),
    ("1234.5678", "locale=en_US;minSig=3;maxSig=3", "1,230"),
    ("1234", "locale=en_US;minSig=2;maxSig=2", "1,200"),
    ("1.5", "locale=en_US;minSig=2;maxSig=4", "1.5"),
    ("1.23456", "locale=en_US;minSig=2;maxSig=4", "1.235"),
    ("0.00123456", "locale=en_US;minSig=3;maxSig=3", "0.00123"),
    ("9007199254740993", "locale=en_US;maxFrac=0", "9,007,199,254,740,993"),
    ("2147483647", "locale=en_US;maxFrac=0", "2,147,483,647"),
    ("-28300", "locale=pt_BR;maxFrac=0", "-28.300"),
    ("18446744073709551615", "locale=en_US;maxFrac=0", "18,446,744,073,709,551,615"),
    ("1.5", "style=currency;currency=GBP;locale=en_GB", "\u{A3}1.50"),
    ("1.5", "style=currency;currency=GBP;locale=fr_FR", "1,50\u{A0}\u{A3}GB"),
    ("1.5", "style=currency;currency=GBP;locale=es_ES", "1,50\u{A0}GBP"),
    ("1.5", "style=currency;currency=CAD;locale=en_US", "CA$1.50"),
    ("1.5", "style=currency;currency=AUD;locale=en_US", "A$1.50"),
    ("1.5", "style=currency;currency=MXN;locale=en_US", "MX$1.50"),
    ("1.5", "style=currency;currency=CNY;locale=en_US", "CN\u{A5}1.50"),
    ("1.5", "style=currency;currency=USD;locale=en_US;minFrac=1", "$1.5"),
    ("1.567", "style=currency;currency=USD;locale=en_US;minFrac=1", "$1.57"),
    ("+1.5", "locale=en_US", "1.5"),
    ("1e5", "locale=en_US", "100,000"),
    ("1E-2", "locale=en_US", "0.01"),
    ("1e-10", "locale=en_US;maxFrac=3", "0"),
    ("0.5", "locale=en_US;minInt=0;minFrac=1", ".5"),
    ("1234.5678", "locale=en_US;maxSig=3", "1,230"),
    ("1.5", "locale=en_US;maxSig=3", "1.5"),
    ("2", "locale=en_US;sign=alwaysExceptZero", "+2"),
    ("0", "locale=en_US;sign=alwaysExceptZero", "0"),
    ("-2", "locale=en_US;sign=alwaysExceptZero", "-2"),
    ("2", "locale=en_US;sign=auto;grouping=auto;style=decimal", "2"),
  ]
}
