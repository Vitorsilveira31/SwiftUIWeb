import Testing

@testable import LoweringCore

/// Shapes of source at the edges of a rule: the spellings it has to read through and the ones it has to leave as they
/// are. The expected text of each is what the previous lowerer writes, unless a comment says the tree reads it better.
@Suite struct RewriteEdgeCaseTests {
  @Test func errorDescriptionsAreFoundThroughOptionalChainsAtAnyDepth() {
    let result = lower(
      """
      let a = vm?.loadError.localizedDescription
      let b = vm.loadError?.localizedDescription
      let c = a.b?.c.d.failure.localizedDescription
      let d = vm?.error?.errorDescription
      let e = vm.lastError!.localizedDescription
      let f = (error).localizedDescription

      """, rules: ["error-description"])
    #expect(result.text.contains("let a = _embeddedErrorDescription(vm?.loadError)\n"))
    #expect(result.text.contains("let b = _embeddedOptionalErrorDescription(vm.loadError)\n"))
    #expect(result.text.contains("let c = _embeddedErrorDescription(a.b?.c.d.failure)\n"))
    #expect(result.text.contains("let d = _embeddedOptionalErrorDescription(vm?.error)\n"))
    #expect(result.text.contains("let e = vm.lastError!.localizedDescription\n"))
    #expect(result.text.contains("let f = (error).localizedDescription\n"))
    #expect(result.counts["error-description"] == 4)
  }

  @Test func aClosureArgumentIsAReceiverWhoseMemberIsRead() {
    // The previous lowerer writes `$0._embeddedErrorDescription(error)` here, which is not a call that exists.
    let result = lower("let d = $0.error.localizedDescription\nlet d2 = $0.localizedDescription\n", rules: ["error-description"])
    #expect(result.text == "let d = _embeddedErrorDescription($0.error)\nlet d2 = $0.localizedDescription\n")
  }

  @Test func theModifiersBeforeAGenericMethodAndBeforeItsClassDecideWhetherTheClassBecomesFinal() {
    let result = lower(
      """
      open class A {
        func f<T>() {}
      }
      class B {
        final func g<T>(_ v: T) {}
      }
      class C {
        override func g<T>(_ v: T) {}
      }
      class D {
        private func g<T>(_ v: T) {}
      }
      class E {
        static func g<T>(_ v: T) {}
      }
      public indirect class F {
        func h<T>(_ v: T) {}
      }
      class H {
        nonisolated func h<T>(_ v: T) {}
        var x = 1
      }

      """, rules: ["final-class-generic-method"])
    for unchanged in ["open class A {", "\nclass B {", "public indirect class F {"] {
      #expect(result.text.contains(unchanged), "\(unchanged)")
    }
    for finalized in ["\nfinal class C {", "\nfinal class D {", "\nfinal class E {", "\nfinal class H {"] {
      #expect(result.text.contains(finalized), "\(finalized)")
    }
    #expect(result.counts["final-class-generic-method"] == 4)
  }

  @Test func aMethodOnTheLineOfItsClassCountsToo() {
    // The previous lowerer reads a method only at the start of a line and leaves this class alone; the tree does not care.
    #expect(lowered("class G { func h<T>(_ v: T) {} }\n", rules: ["final-class-generic-method"]) == "final class G { func h<T>(_ v: T) {} }\n")
  }

  @Test func onlyAPlainRootlessKeyPathBecomesAClosure() {
    let result = lower(
      """
      let c = KeyPathComparator(\\Order<Int>.status)
      let d = KeyPathComparator(\\Order.Inner.status)
      let e = KeyPathComparator(\\.name, order: .forward, extra: 1)
      let f = KeyPathComparator(\\.name, order: .forward,)
      ForEach(rows, id: \\Row.id) { _ in EmptyView() }
      List(rows, id: \\Row.id) { _ in EmptyView() }

      """, rules: ["table-sorting", "simple-rules"])
    #expect(result.text.contains("KeyPathComparator(\\Order<Int>.status)"))
    #expect(result.text.contains("KeyPathComparator(_embeddedMember: \"Inner.status\", { (row: Order) in row.Inner.status })"))
    #expect(result.text.contains("KeyPathComparator(\\.name, order: .forward, extra: 1)"))
    #expect(result.text.contains("KeyPathComparator(\\.name, order: .forward,)"))
    #expect(result.text.contains("ForEach(rows, id: \\Row.id)"))
    #expect(result.text.contains("List(rows, id: \\Row.id)"))
  }

  @Test func allCasesOfANamedTypeAreIdentifiedByThemselves() {
    let result = lower(
      """
      ForEach(Models.Mode.allCases) { _ in EmptyView() }
      ForEach(Mode.allCases) { _ in EmptyView() }
      ForEach(a.b().allCases) { _ in EmptyView() }
      ForEach(Array<Mode>.allCases) { _ in EmptyView() }

      """, rules: ["simple-rules"])
    #expect(result.text.contains("ForEach(Models.Mode.allCases, id: { $0 }) {"))
    #expect(result.text.contains("ForEach(Mode.allCases, id: { $0 }) {"))
    #expect(result.text.contains("ForEach(a.b().allCases) {"))
    #expect(result.text.contains("ForEach(Array<Mode>.allCases) {"))
    #expect(result.counts["foreach-allcases-rawvalue"] == 2)
  }

  @Test func anAttributeInAConditionalBlockStillBelongsToItsMember() {
    let output = lowered(
      """
      @Observable final class M {
        #if DEBUG
        @ObservationIgnored
        #endif
        var cache = 0
        #if DEBUG
        @ObservationIgnored var other = 0
        #endif
        final var label: String
        lazy var text: String
        weak var parent: M?
        var plain: Int
      }

      """, rules: ["observable", "weak"])
    #expect(output.contains("#if DEBUG\n  \n  #endif\n  @Published(memberID: 1) var cache = 0\n  #if DEBUG\n  var other = 0\n  #endif\n"))
    #expect(output.contains("@Published(memberID: 2) final var label: String\n"))
    #expect(output.contains("@Published(memberID: 3) lazy var text: String\n"))
    #expect(output.contains("@Published(memberID: 4) var parent: M? = nil\n"))
    #expect(output.contains("@Published(memberID: 5) var plain: Int\n"))
  }

  @Test func observableStateIsRecognizedByItsDeclaredOrConstructedType() {
    let output = lowered(
      """
      @Observable final class M { var a = 1 }
      struct V: View {
        @State var m: M?
        @State var n = M()
        @State var o = M ()
        @State private var p: M
        @State private var q = other
        @State static var shared = 0
        var body: some View { Text("") }
      }

      """)
    #expect(output.contains("  @State var m: M?\n"))
    #expect(output.contains("  @StateObject var n = M()\n"))
    #expect(output.contains("  @StateObject var o = M ()\n"))
    #expect(output.contains("  @StateObject private var p: M\n"))
    #expect(output.contains("  @State(memberID: \(stableStateMemberID("q"))) private var q = other\n"))
    #expect(output.contains("  @State(memberID: \(stableStateMemberID("shared"))) static var shared = 0\n"))
  }

  @Test func aGuardThatDoesNotUnwrapSelfKeepsItsMeaningInAWeakSelfClosure() {
    let output = lowered(
      """
      func f() {
        guard let self = other else { return }
        guard let self, ready else { return }
        guard var self else { return }
        run { [weak self] in
          guard let self = other else { return }
          self?.go()
        }
      }

      """, rules: ["weak"])
    #expect(output.contains("  guard let self = other else { return }\n  guard let self, ready else { return }\n  guard var self else { return }\n"))
    #expect(output.contains("run { [self] in\n    guard let self = other else { return }\n    self.go()\n"))
  }

  @Test func theBridgingImportAndTheCodableImportReadTheirAttributes() {
    // An import with two attributes is not the plain bridging import and gets none added to it.
    let bridging = lowered("import WebFoundation\n@_spi(Renderer) @_spi(Generated) import WebFoundation\nlet data = buffer.storage as Data\n", rules: ["as-data-bridge"])
    #expect(bridging == "@_spi(Renderer) import WebFoundation\n@_spi(Renderer) @_spi(Generated) import WebFoundation\nlet data = Data(_bridging: buffer.storage)\n")
    // Neither is it the framework import the Codable types need, so one is added in front.
    let codable = lowered("@preconcurrency import SwiftUIWeb\n@_spi(Renderer) @_spi(Generated) import SwiftUIWeb\nstruct P: Codable { let x: Int }\n", rules: ["embedded-codable"])
    #expect(codable.hasPrefix("import SwiftUIWeb\n@preconcurrency import SwiftUIWeb\n@_spi(Renderer) @_spi(Generated) import SwiftUIWeb\nstruct P: EmbeddedCodable"))
  }

  @Test func aPreviewIsRemovedWhereverItIsDeclared() {
    let output = lowered(
      """
      enum Namespace {
        #Preview { Text("a") }
      }
      #Preview { Text("b") }
      #Preview("x") {
        Text("c")
      }
      struct A { }

      """)
    #expect(output == "enum Namespace {\n}\nstruct A { }\n")
  }

  @Test func anObservableAttributeInAConditionalBlockIsRefusedWhereItIsWritten() throws {
    // The previous lowerer refuses it too, but words the error for the declaration that follows the `#endif`.
    let source = "#if DEBUG\n@Observable\n#endif\nfinal class M { var a = 1 }\n"
    let error = try #require(throws: LoweringError.self) {
      _ = try LoweringPipeline.standard.lower(source, options: LoweringOptions(lowerCodable: true))
    }
    #expect(error.code == "SWUI-L001")
    #expect(LoweringError.position(of: error.offset, in: source) == (line: 2, column: 1))
  }

  /// A rule whose two edits overlap: the run must fail with the rule named, not trap.
  private struct OverlappingRule: SourceTransform {
    let name = "overlapping-rule"
    func applies(to options: LoweringOptions) -> Bool { true }
    func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
      try apply([.remove(0, 4), .remove(2, 6)], to: text)
    }
  }

  @Test func overlappingEditsFailTheRunNamingTheRule() throws {
    #expect(throws: LoweringError.self) { _ = try apply([.remove(0, 4), .remove(2, 6)], to: "abcdefgh") }
    #expect(throws: LoweringError.self) { _ = try apply([.remove(0, 99)], to: "abc") }
    // Edits that touch but do not overlap, and edits at one offset, still apply in order.
    #expect(try apply([.remove(0, 2), .remove(2, 4), .insert("X", at: 4)], to: "abcdefgh") == "Xefgh")
    #expect(try apply([.insert("1", at: 1), .insert("2", at: 1)], to: "ab") == "a12b")

    let error = try #require(throws: LoweringError.self) {
      _ = try LoweringPipeline(transforms: [OverlappingRule()]).lower("abcdefgh", options: LoweringOptions())
    }
    #expect(error.code == "SWUI-L003")
    #expect(error.message.hasPrefix("rule overlapping-rule: "))
  }
}
