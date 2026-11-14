import Testing
@testable import SwiftUIWeb
import Foundation

/// The runtime `Regex` of the browser build (WebFoundation's backtracking matcher). A repeated single character is matched
/// in a loop, so a long run of text does not exhaust the browser's stack; the browser side is checked by
/// `make hostile-values-browser-test` (regex-long-run).
@Suite
struct RegexMatcherTests {
  private func first(_ pattern: String, _ text: String) throws -> String? {
    let regex = try Foundation.Regex<AnyRegexOutput>(pattern)
    return text.firstMatch(of: regex).map { String(text[$0.range]) }
  }

  @Test
  func repeatsKeepTheirMeaning() throws {
    #expect(try first("a+", "xaaay") == "aaa")
    #expect(try first("a+?", "xaaay") == "a")
    #expect(try first("a*b", "aaab") == "aaab")
    #expect(try first("[0-9]{2,3}", "x12345") == "123")
    #expect(try first("[0-9]{2,3}?", "x12345") == "12")
    #expect(try first("\\w+@\\w+", "mail me: ana@example now") == "ana@example")
    #expect(try first(".*z", "abc\nxyz") == "xyz")
    #expect(try first("(ab)+", "xababx") == "abab")
    #expect(try first("a{3}", "aa") == nil)
    #expect(try first("^a+$", "aaaa") == "aaaa")
  }

  @Test
  func caseInsensitiveRangesAcceptLongCaseMappings() throws {
    // "ß" uppercases to "SS", two characters; it used to trap building a Character from that string.
    #expect(try first("(?i)[a-z]+", "straße") == "stra")
  }

  @Test
  func longRunsDoNotRecursePerCharacter() throws {
    let text = String(repeating: "a", count: 200_000)
    #expect(try first("^a+b", text) == nil)
    #expect(try first("a+", text)?.count == 200_000)
    // A repeated group still backtracks frame by frame; within the depth limit it matches. Past it, it fails instead of
    // trapping: that runs in the browser build (hostile-values regex-deep-group); a debug test thread has a 512 KB stack.
    #expect(try first("(ab)+c", String(repeating: "ab", count: 20) + "c")?.count == 41)
  }

  /// As Swift's Regex: ^ and $ are the start and end of the input unless (?m) asks for lines, and . stops at a line
  /// break unless (?s). An allowlist pattern used with contains(_:) cannot be passed by a second line.
  @Test
  func anchorsAndDotFollowSwiftsDefaults() throws {
    let regex = try Foundation.Regex<AnyRegexOutput>("^[a-z]+$")
    #expect(!"ok\n<script>".contains(regex))
    #expect("ok".contains(regex))
    #expect(try first("(?m)^[a-z]+$", "1\nok\n2") == "ok")
    #expect(try first("a.b", "a\nb") == nil)
    #expect(try first("(?s)a.b", "a\nb") == "a\nb")
    #expect(try first("(?im)^OK$", "x\nok") == "ok")
  }

  /// Exponential backtracking stops at a step budget (no match) instead of freezing the page.
  @Test
  func catastrophicPatternsStopAtTheStepBudget() throws {
    // 2^22 ways to split the run: past the budget. Longer runs are checked in the browser build (hostile-values
    // regex-catastrophic); a debug test thread has a 512 KB stack.
    let started = Date()
    #expect(try first("(a+)+$", String(repeating: "a", count: 22) + "!") == nil)
    #expect(Date().timeIntervalSince(started) < 30)
  }

  /// Parsing is bounded too: groups nest at most a hundred deep, and many "{" do not make it quadratic.
  @Test
  func hostilePatternsAreRefusedOrParsedQuickly() throws {
    #expect(throws: RegexSyntaxError.self) { try Foundation.Regex<AnyRegexOutput>(String(repeating: "(", count: 5_000) + String(repeating: ")", count: 5_000)) }
    #expect((try? Foundation.Regex<AnyRegexOutput>(String(repeating: "(", count: 50) + "a" + String(repeating: ")", count: 50))) != nil)
    _ = try? Foundation.Regex<AnyRegexOutput>(String(repeating: "{", count: 200_000))
  }
}
