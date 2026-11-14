import Testing

@testable import LoweringCore

@Suite struct StateMemberIDTests {
  private func identities(_ source: String) -> LoweringResult { lower(source, rules: ["state-member-ids"]) }

  @Test func theIdentityIsTheFNVHashOfTheName() {
    #expect(stableStateMemberID("hovered") == 2_901_697_652)
    #expect(stableStateMemberID("") == 2_166_136_261)
  }

  @Test func everyStateWithAValueGetsAStableIdentityIdempotently() {
    let source = """
      struct SettingsView {
        @State
        private var selectedTab = 0
        @State(wrappedValue: false) var airplaneMode: Bool
        @State private(set) var adjustable = 0
        @State(memberID: 9) var explicit = 0
        @State private var initializedInInit: Model
        @StateObject private var model: Model
        let example = "@State private var ignored = 1"
        // @State private var alsoIgnored = 2
      }

      """
    let first = identities(source)
    #expect(first.counts == ["state-member-identities": 3])
    #expect(first.text.contains("@State(memberID: \(stableStateMemberID("selectedTab")))\n  private var selectedTab = 0"))
    #expect(first.text.contains("@State(wrappedValue: false, memberID: \(stableStateMemberID("airplaneMode"))) var airplaneMode: Bool"))
    #expect(first.text.contains("@State(memberID: \(stableStateMemberID("adjustable"))) private(set) var adjustable = 0"))
    #expect(first.text.contains("@State(memberID: 9) var explicit = 0"))
    #expect(first.text.contains("@State private var initializedInInit: Model"))
    #expect(first.text.contains("@StateObject private var model: Model"))
    #expect(first.text.contains("let example = \"@State private var ignored = 1\""))
    #expect(first.text.contains("// @State private var alsoIgnored = 2"))
    let second = identities(first.text)
    #expect(second.text == first.text)
    #expect(second.counts.isEmpty)
  }

  @Test func attributesNestedArgumentsAndEscapedNamesAreRead() {
    let source = """
      struct V {
        @State @MainActor @available(*, deprecated, message: "legacy")
        public var items: [Int] = [1]
        @State(wrappedValue: make((1))) var nested: Int
        @State private var `default` = 0
        @State private var value: Model
        @State private let invalid = 1
        @State var (a, b) = (1, 2)
        @State required var required = 1
        @State static var shared = 1
        @State var many = 1, other = 2
      }

      """
    let result = identities(source)
    #expect(result.text.contains("@State(memberID: \(stableStateMemberID("items"))) @MainActor @available(*, deprecated, message: \"legacy\")\n  public var items: [Int] = [1]"))
    #expect(result.text.contains("@State(wrappedValue: make((1)), memberID: \(stableStateMemberID("nested"))) var nested: Int"))
    #expect(result.text.contains("@State(memberID: \(stableStateMemberID("default"))) private var `default` = 0"))
    #expect(result.text.contains("@State private var value: Model"))
    #expect(result.text.contains("@State private let invalid = 1"))
    #expect(result.text.contains("@State var (a, b) = (1, 2)"))
    #expect(result.text.contains("@State required var required = 1"))
    #expect(result.text.contains("@State(memberID: \(stableStateMemberID("shared"))) static var shared = 1"))
    #expect(result.text.contains("@State(memberID: \(stableStateMemberID("many"))) var many = 1, other = 2"))
    #expect(result.counts["state-member-identities"] == 5)
  }

  @Test func aPropertyWithoutAValueGetsNoIdentityAndAnAccessorIsNotAValue() {
    let result = identities(
      """
      struct V {
        @State var callback: (Int) -> [Int] = { value in [value] }
        @State var typed: (Int) -> [Int] = make()
        @State var model: Model { storage = make() }
        @State var later: Model
      }

      """)
    #expect(result.text.contains("@State(memberID: \(stableStateMemberID("callback"))) var callback"))
    #expect(result.text.contains("@State(memberID: \(stableStateMemberID("typed"))) var typed"))
    #expect(result.text.contains("@State var model: Model { storage = make() }"))
    #expect(result.text.contains("@State var later: Model"))
    #expect(result.counts["state-member-identities"] == 2)
  }

  @Test func anExistingIdentityKeepsAnAttributeWithOnlyThatArgument() {
    let result = identities("struct V {\n  @State(initialValue: 1) var a: Int\n  @State() var b = 2\n  @State(memberID: 1, wrappedValue: 2) var c: Int\n}\n")
    #expect(result.text.contains("@State(initialValue: 1) var a: Int"))
    #expect(result.text.contains("@State(memberID: \(stableStateMemberID("b"))) var b = 2"))
    #expect(result.text.contains("@State(memberID: 1, wrappedValue: 2) var c: Int"))
  }

  @Test func theFrameworkSourcesGetIdentitiesToo() {
    var pipeline = LoweringPipeline.standard
    pipeline = pipeline.selecting(["state-member-ids"])!
    let result = lower(pipeline, "struct V {\n  @State var hovered = false\n}\n", options: LoweringOptions(lowerCodable: false))
    #expect(result.text == "struct V {\n  @State(memberID: 2901697652) var hovered = false\n}\n")
  }
}
