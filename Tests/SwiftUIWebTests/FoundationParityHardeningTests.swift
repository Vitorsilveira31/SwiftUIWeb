import Testing
import Foundation
@testable import SwiftUIWeb

/// Foundation behaviours that matter for data from outside: strict parsing, filters that apply, and string operations that
/// see "\r\n" and stay linear.
@Suite
struct FoundationParityHardeningTests {
  @Test
  func uuidsParseOnlyTheirOwnForm() {
    #expect(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F") != nil)
    #expect(UUID(uuidString: "----" + String(repeating: "0", count: 32)) == nil)
    #expect(UUID(uuidString: "E621E1F8C36C-495A-93FC-0C247A3E6E5F-") == nil)
    #expect(UUID(uuidString: "Ｅ621E1F8-C36C-495A-93FC-0C247A3E6E5F") == nil)
  }

  @Test
  func percentDecodingRefusesInvalidUTF8() {
    #expect("%FF".removingPercentEncoding == nil)
    #expect("%C0%AF".removingPercentEncoding == nil)
    #expect("a%20b%C3%A9".removingPercentEncoding == "a bé")
  }

  @Test
  func notificationObserversFilterBySenderAndTakeAnyName() {
    final class Sender {}
    final class Counter: @unchecked Sendable { var value = 0 }
    let center = NotificationCenter()
    let trusted = Sender(), other = Sender()
    let name = Notification.Name("hardening.test")
    let filtered = Counter(), everything = Counter()
    _ = center.addObserver(forName: name, object: trusted, queue: nil) { _ in filtered.value += 1 }
    _ = center.addObserver(forName: nil, object: nil, queue: nil) { _ in everything.value += 1 }
    center.post(name: name, object: other)
    center.post(name: name, object: trusted)
    center.post(name: Notification.Name("hardening.other"), object: nil)
    #expect(filtered.value == 1)
    #expect(everything.value == 3)
  }

  @Test
  func mutableDictionaryKeepsKeysApart() {
    let dictionary = NSMutableDictionary()
    dictionary["a"] = 1
    dictionary[1] = "one"
    #expect(dictionary["a"] as? Int == 1)
    #expect(dictionary[1] as? String == "one")
    #expect(dictionary["b"] == nil)
  }

  @Test
  func whitespaceAndLineBreaksFollowUnicode() {
    #expect("  \r\n".trimmingCharacters(in: .whitespacesAndNewlines) == "")
    #expect("\u{A0}x\u{2028}".trimmingCharacters(in: .whitespacesAndNewlines) == "x")
    #expect("a\r\nb".components(separatedBy: "\n") == ["a\r", "b"])
    #expect("a\r\nb".components(separatedBy: "\r\n") == ["a", "b"])
    #expect("a,b,,c".components(separatedBy: ",") == ["a", "b", "", "c"])
  }

  @Test
  func replacingAndMatchingStayLinear() throws {
    let text = String(repeating: "\r", count: 100_000)
    let started = Date()
    #expect(text.replacingOccurrences(of: "\r\n", with: "\n").count == 100_000)
    #expect(String(repeating: "ab", count: 50_000).replacingOccurrences(of: "a", with: "") == String(repeating: "b", count: 50_000))
    #expect("xaxbxa".replacingOccurrences(of: "xa", with: "!") == "!xb!")
    #expect("a\r\nb".replacingOccurrences(of: "\n", with: "X") == "a\rXb")
    // Canonically equivalent text is found, as Foundation finds it: a decomposed é is an é.
    #expect("cafe\u{301}".replacingOccurrences(of: "é", with: "X") == "cafX")
    #expect("cafe\u{301}".components(separatedBy: "é") == ["caf", ""])
    #expect("a\r\nb\r\nc".components(separatedBy: "\r\n") == ["a", "b", "c"])
    let regex = try Foundation.Regex<AnyRegexOutput>("a")
    #expect(String(repeating: "a", count: 20_000).matches(of: regex).count == 20_000)
    #expect(Date().timeIntervalSince(started) < 20)
  }

  @Test
  func longLiteralPatternsAndLongTextsMatch() throws {
    // 700 literals in a row: past the depth limit if each took a level.
    let pattern = String(repeating: "a", count: 700)
    #expect(try (String(repeating: "a", count: 700)).firstMatch(of: Foundation.Regex<AnyRegexOutput>(pattern)) != nil)
    // A needle at the end of a long text: the step budget grows with the text.
    let haystack = String(repeating: "x", count: 1_000_000) + "needle"
    #expect(try haystack.firstMatch(of: Foundation.Regex<AnyRegexOutput>("needle")) != nil)
  }

  @Test
  func lazyRepetitionsMatchEveryPositionInLinearTime() throws {
    let started = Date()
    let lazy = try Foundation.Regex<AnyRegexOutput>("a*?")
    // One empty match per position and one at the end: a lazy run must not read the rest of the run first.
    #expect(String(repeating: "a", count: 20_000).matches(of: lazy).count == 20_001)
    let minimum = try Foundation.Regex<AnyRegexOutput>("a+?b")
    #expect((String(repeating: "a", count: 2_000) + "b").matches(of: minimum).count == 1)
    #expect(Date().timeIntervalSince(started) < 10)
  }

  @Test
  func base64IsReadAsFoundationReadsIt() {
    #expect(Data(base64Encoded: "QUJD").map { Array($0) } == [65, 66, 67])
    #expect(Data(base64Encoded: "QQ==").map { Array($0) } == [65])
    #expect(Data(base64Encoded: "QQ==QQ==") == nil)
    #expect(Data(base64Encoded: " QQ==") == nil)
    #expect(Data(base64Encoded: "QQ") == nil)
    #expect(Data(base64Encoded: Data([1, 2, 3, 250]).base64EncodedString()).map { Array($0) } == [1, 2, 3, 250])
  }
}
