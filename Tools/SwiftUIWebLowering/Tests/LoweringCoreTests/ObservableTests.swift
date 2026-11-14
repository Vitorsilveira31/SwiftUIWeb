import Testing

@testable import LoweringCore

@Suite struct ObservableTests {
  private func observable(_ source: String) -> LoweringResult { lower(source, rules: ["observable"]) }

  /// The error a source is refused with, or nil when it is lowered.
  private func refusal(_ source: String, rules: [String] = ["observable"]) -> LoweringError? {
    var pipeline = LoweringPipeline.standard
    pipeline = pipeline.selecting(rules)!
    do {
      _ = try pipeline.lower(source, options: LoweringOptions(lowerCodable: true))
      return nil
    } catch let error as LoweringError {
      return error
    } catch {
      Issue.record("unexpected error \(error)")
      return nil
    }
  }

  @Test func storedMembersOfAnObservableClassAreWrappedInDeclarationOrder() {
    let result = observable(
      """
      @Observable final class Model {
        @ObservationIgnored var cache = 0
        var value = 1
        var label: String
        var optionalNote: String?
        var computed: Int { cache }
      }

      """)
    #expect(!result.text.contains("@Observable"))
    #expect(!result.text.contains("@ObservationIgnored"))
    #expect(result.text.contains("@Published(memberID: 1) var value = 1"))
    #expect(result.text.contains("@Published(memberID: 2) var label: String\n"))
    #expect(result.text.contains("@Published(memberID: 3) var optionalNote: String? = nil"))
    #expect(result.text.contains("var computed: Int { cache }"))
    #expect(result.text.hasPrefix(" final class Model {\n  var cache = 0\n"))
    #expect(result.counts == ["observable-attribute": 1, "observable-published": 3, "observation-ignored": 1])
  }

  @Test func anObservableThatIsNotAClassFailsTheRunAndNamesTheDeclaration() throws {
    let error = try #require(refusal("@Observable struct NotAReferenceModel { var value = 0 }"))
    #expect(error.code == "SWUI-L001")
    #expect(error.message.contains("struct `NotAReferenceModel`"))
    #expect(error.message.contains("make it a class"))
    #expect(error.description.hasPrefix("[SWUI-L001]"))
    #expect(error.offset == 0)
    #expect(refusal("let a = 1\n@Observable enum Mode { case one }\n")?.message.contains("line 2 declares enum `Mode`") == true)
    #expect(refusal("@Observable actor Counter { var n = 0 }")?.message.contains("actor `Counter`") == true)
    #expect(refusal("@Observable protocol Store {}")?.message.contains("protocol `Store`") == true)
    #expect(refusal("@Observable extension Model {}")?.message.contains("extension `Model`") == true)
  }

  @Test func anObservableOnAnythingElseOrOnAClassWithoutItsBracesFailsWithTheGeneralReason() throws {
    for source in ["@Observable func run() {}\n", "@Observable final class Open {\n  var a = 1\n"] {
      let error = try #require(refusal(source))
      #expect(error.code == "SWUI-L001", "\(source)")
      #expect(error.message.contains("cannot rewrite safely"), "\(source)")
    }
  }

  @Test func aNestedRefusalIsReportedAtTheNestedDeclaration() throws {
    let source = "@Observable final class Parent {\n  @Observable struct Child { var value = 1 }\n}"
    let error = try #require(refusal(source))
    let expected = source.utf8.distance(from: source.startIndex, to: source.range(of: "@Observable struct Child")!.lowerBound)
    #expect(error.offset == expected)
    #expect(LoweringError.position(of: error.offset, in: source) == (line: 2, column: 3))
    #expect(error.formatted(path: "Sources/P.swift", source: source).hasPrefix("Sources/P.swift:2:3: [SWUI-L001]"))
  }

  @Test func aClassNestedInAnotherTypeIsLowered() {
    let result = observable("struct Namespace {\n  @Observable final class Model { var value = 1 }\n}")
    #expect(result.counts["observable-attribute"] == 1)
    #expect(result.counts["observable-published"] == 1)
    #expect(!result.text.contains("@Observable"))
    #expect(result.text.contains("@Published(memberID: 1) var value = 1"))
  }

  @Test func nestedObservableClassesAreNumberedAndCountedSeparately() {
    let result = observable(
      """
      @Observable final class Outer {
        var value: Int?
        var initialized = 1
        var computed: Int { value ?? 0 }
        var callback: (Int) -> [String] = { _ in [] }
        var observed: Int { willSet { _ = newValue } }
        static var ignored = 0
        @ObservationIgnored var cache = 0
        @Observable final class Inner { var nested = 1 }
      }

      """)
    #expect(result.counts == ["observable-attribute": 2, "observable-published": 4, "observation-ignored": 1])
    #expect(result.text.contains("@Published(memberID: 1) var value: Int? = nil"))
    #expect(result.text.contains("@Published(memberID: 2) var initialized = 1"))
    #expect(result.text.contains("@Published(memberID: 3) var callback: (Int) -> [String] = { _ in [] }"))
    #expect(result.text.contains("var observed: Int { willSet { _ = newValue } }"))
    #expect(result.text.contains("static var ignored = 0"))
    #expect(result.text.contains("final class Inner { @Published(memberID: 1) var nested = 1 }"))
  }

  @Test func membersThatAreNotPlainStoredVarsStayAsTheyAre() {
    let result = observable(
      """
      @Observable class RouterPath {
        public var path: [Int] = []
        public var presentedSheet: Sheet?

        public static var starting: Start?
        class var kind: String { "router" }
        let identifier = 1
        @available(iOS 17, *) var available = 1
        @MainActor
        var onItsOwnLine = 2

        public init() {}
      }

      """)
    #expect(result.text.contains("@Published(memberID: 1) public var path: [Int] = []"))
    #expect(result.text.contains("@Published(memberID: 2) public var presentedSheet: Sheet? = nil"))
    #expect(result.text.contains("public static var starting: Start?"))
    #expect(result.text.contains("class var kind: String { \"router\" }"))
    #expect(result.text.contains("let identifier = 1"))
    #expect(result.text.contains("@available(iOS 17, *) var available = 1"))
    // An attribute on the line above does not keep the property from being published; one on its line does.
    #expect(result.text.contains("@MainActor\n  @Published(memberID: 3) var onItsOwnLine = 2"))
  }

  @Test func theModifiersOfAMemberFollowTheWrapper() {
    let result = observable(
      """
      @Observable final class Model {
        public private(set) var a = 1
        private lazy var b = 2
        weak var delegate: Thing?
        fileprivate var c: Int?, d: String?
      }

      """)
    #expect(result.text.contains("@Published(memberID: 1) public private(set) var a = 1"))
    #expect(result.text.contains("@Published(memberID: 2) private lazy var b = 2"))
    #expect(result.text.contains("@Published(memberID: 3) weak var delegate: Thing? = nil"))
    #expect(result.text.contains("@Published(memberID: 4) fileprivate var c: Int? = nil, d: String? = nil"))
  }

  @Test func anOptionalWithoutAValueGetsNilEvenWithACommentAfterIt() {
    let result = observable("@Observable final class Model {\n  var note: String? // a note\n  var plain: Int // not optional\n}\n")
    #expect(result.text.contains("@Published(memberID: 1) var note: String? = nil // a note"))
    #expect(result.text.contains("@Published(memberID: 2) var plain: Int // not optional"))
  }

  @Test func aStoredPropertyBeforeANestedTypeIsStillPublished() {
    let result = observable(
      """
      @Observable final class Model {
        var size: Size
        enum Size { case small }
        var title: String
        typealias Row = Int
        var rows: [Row]
      }

      """)
    #expect(result.counts["observable-published"] == 3)
    #expect(result.text.contains("@Published(memberID: 1) var size: Size"))
    #expect(result.text.contains("@Published(memberID: 3) var rows: [Row]"))
  }

  @Test func membersInAConditionalBlockAreMembers() {
    let result = observable(
      """
      @Observable final class Model {
        var always = 1
        #if DEBUG
        var debugOnly = 2
        #endif
      }

      """)
    #expect(result.text.contains("@Published(memberID: 2) var debugOnly = 2"))
  }

  @Test func observationIgnoredGoesFromEverywhereInsideALoweredClass() {
    let result = observable(
      """
      @Observable final class Model {
        @ObservationIgnored
        var multiline = 1
        @ObservationIgnored   var cache = 2
        struct Inner { @ObservationIgnored var inside = 3 }
      }
      @ObservationIgnored var outside = 4

      """)
    #expect(result.counts["observation-ignored"] == 3)
    #expect(result.text.contains("var cache = 2"))
    #expect(!result.text.contains("@ObservationIgnored   "))
    #expect(result.text.contains("struct Inner { var inside = 3 }"))
    // The attribute on the line above excludes the property as well as one on its line; the attribute goes.
    #expect(result.text.contains("{\n  \n  var multiline = 1\n"))
    #expect(!result.text.contains("@Published"))
    #expect(result.text.contains("@ObservationIgnored var outside = 4"))
  }

  @Test func textInsideStringsAndCommentsIsNotADeclaration() {
    let source = """
      let s = "\\(table["@Observable final class Hidden { var v = 0 }"] ?? "")"
      let note = "@Observable struct NotLowered {}"
      // @Observable struct InAComment {}
      /* @Observable final class Block { var v = 0 } */

      """
    let result = observable(source)
    #expect(result.text == source)
    #expect(result.counts.isEmpty)
  }

  @Test func anAssignmentInAnInitializerInitializesTheWrapper() {
    let result = observable(
      """
      @Observable
      class Model {
        var tint: Int
        var url: String
        var label: String
        init() {
          tint = 1  // real work later
          url = "https://example.com"
          self.label = "x"
        }
      }

      """)
    // A value that ends in a comment or a string literal is followed by a line break before `, memberID:`.
    #expect(result.text.contains("    _tint = Published(wrappedValue: 1  // real work later\n, memberID: 1)\n"))
    #expect(result.text.contains("    _url = Published(wrappedValue: \"https://example.com\"\n, memberID: 2)\n"))
    #expect(result.text.contains("    _label = Published(wrappedValue: \"x\"\n, memberID: 3)\n"))
  }

  @Test func theWholeRightHandSideIsTheWrappedValue() {
    let multiline = observable(
      """
      @Observable
      @MainActor
      final class Model {
        private(set) var state: State
        init(initialState: State?, index: Int) {
          state = initialState ?? State(
            index: max(0, index),
            isFavorite: true,
          )
        }
      }

      """)
    #expect(!multiline.text.contains("State(, memberID"))
    #expect(multiline.text.contains("_state = Published(wrappedValue: initialState ?? State(\n      index: max(0, index),\n      isFavorite: true,\n    ), memberID: 1)"))

    let operatorAtTheEnd = observable("@Observable\nfinal class Model {\n  var total: Int\n  init(a: Int, b: Int) {\n    total = a +\n      b\n  }\n}\n")
    #expect(operatorAtTheEnd.text.contains("_total = Published(wrappedValue: a +\n      b, memberID: 1)"))
  }

  @Test func onlyDeclaredWithoutAValueMembersAreInitializedThroughTheWrapper() {
    let result = observable(
      """
      @Observable final class Counter {
        var total: Int
        private(set) var step: Int
        var started = false
        var note: String?
        init() {
          total = combine(
          total = 1)
          step = 1
          started = true
          note = "n"
          self.total += 2
        }
        static let shared = Counter.init()
      }

      """)
    #expect(result.text.contains("@Published(memberID: 1) var total: Int\n"))
    #expect(result.text.contains("@Published(memberID: 2) private(set) var step: Int\n"))
    // A statement inside the value of another one is part of that value.
    #expect(result.text.contains("    _total = Published(wrappedValue: combine(\n    total = 1), memberID: 1)\n"))
    #expect(result.text.contains("    _step = Published(wrappedValue: 1, memberID: 2)\n"))
    #expect(result.text.contains("    started = true\n"))
    #expect(result.text.contains("    note = \"n\"\n"))
    #expect(result.text.contains("    self.total += 2\n"))
    #expect(result.text.contains("static let shared = Counter.init()"))
  }

  @Test func onlyTheAssignmentsOfAnInitializerOfTheClassAreRewrittenAndAllOfThem() {
    let result = observable(
      """
      @Observable final class Model {
        var a: Int
        var b: Int
        init() {
          a = 1; b = 2
          if true { a = 3 }
        }
        convenience init(a: Int, closure: () -> Void = { }) {
          self.init()
          self.a = a
        }
        func reset() { a = 0 }
      }

      """)
    #expect(result.text.contains("    _a = Published(wrappedValue: 1, memberID: 1); _b = Published(wrappedValue: 2, memberID: 2)\n"))
    #expect(result.text.contains("if true { _a = Published(wrappedValue: 3, memberID: 1) }"))
    #expect(result.text.contains("    _a = Published(wrappedValue: a, memberID: 1)\n"))
    #expect(result.text.contains("func reset() { a = 0 }"))
  }

  @Test func anAssignmentInAClosureOfAnInitializerIsNotTheInitializersOwn() {
    let result = observable(
      """
      @Observable final class Model {
        var a: Int
        var b: Int
        init() {
          let set = { a = 4 }
          let reset = { self.b = 5 }
          a = 1
          b = 2
        }
      }

      """)
    #expect(result.text.contains("    let set = { a = 4 }\n    let reset = { self.b = 5 }\n"))
    #expect(result.text.contains("    _a = Published(wrappedValue: 1, memberID: 1)\n    _b = Published(wrappedValue: 2, memberID: 2)\n"))
  }

  @Test func aBareNameThatALocalOfTheInitializerDeclaresIsNotTheProperty() {
    let result = observable(
      """
      @Observable final class Model {
        var a: Int
        var b: Int
        init(b: Int) {
          var a = 0
          a = 3
          self.b = b
        }
      }

      """)
    #expect(result.text.contains("    a = 3\n"))
    #expect(result.text.contains("    _b = Published(wrappedValue: b, memberID: 2)\n"))
  }

  @Test func aValueThatDoesNotEndBeforeTheInitializerDoesFailsClosedWithThePropertyName() throws {
    let source = "@Observable\nfinal class Model {\n  var total: Int\n  init() {\n    total = max(1,\n  }\n}\n"
    let error = try #require(refusal(source))
    #expect(error.code == "SWUI-L002")
    #expect(error.message.contains("`total`"))
    // Anchored at the class header, the declaration that contains the initializer.
    #expect(LoweringError.position(of: error.offset, in: source).line == 2)
  }

  @Test func aModelClassIsLoweredLikeAnyObservableClass() {
    let result = lower("@Model final class Note { var title = \"\" }\n")
    #expect(result.text.contains("final class Note: PersistentModel {"))
    #expect(result.text.contains("@Published(memberID: 1) var title = \"\""))
    #expect(!result.text.contains("@Model"))
    #expect(result.counts["model-macro"] == 1)
    #expect(result.counts["observable-attribute"] == 1)
  }

  @Test func loweringItsOwnOutputChangesNothing() {
    let first = lower(
      """
      @Observable final class Store {
        var count = 0
        var label: String?
        init() { label = nil }
      }
      struct Screen: View {
        @State private var store = Store()
        @State private var hovered = false
        init() { self.store = Store() }
        var body: some View { Text("x") }
      }

      """)
    let second = lower(first.text)
    #expect(second.text == first.text)
    #expect(second.counts.isEmpty)
  }

  @Test func theFrameworkSourcesAreLoweredToo() {
    let source = "@Observable final class Store { var count = 0 }\n"
    var pipeline = LoweringPipeline.standard
    pipeline = pipeline.selecting(["observable"])!
    let result = lower(pipeline, source, options: LoweringOptions(lowerCodable: false))
    #expect(result.text == " final class Store { @Published(memberID: 1) var count = 0 }\n")
  }

  @Test func theObservableClassesOfASourceAreFoundWithTheirNestedOnes() throws {
    let names = try ObservableTypeScan.names(
      in: """
        @Observable final class A { @Observable final class B {} }
        enum E { @Observable class C<T> {} }
        @Observable struct NotAClass {}
        class Plain {}
        let s = "@Observable final class InAString {}"

        """)
    #expect(names == ["A", "B", "C"])
    #expect(ObservableTypeScan.names(in: "class Plain {}").isEmpty)
  }

  @Test func theObservablePassesRunBeforeCodableAndViewInputs() {
    let names = LoweringPipeline.passNames
    func index(_ name: String) -> Int { names.firstIndex(of: name)! }
    #expect(index("error-interpolation") < index("observable") && index("observable") < index("embedded-codable"))
    #expect(index("error-description") < index("observable-state"))
    #expect(index("observable-state") < index("state-member-ids") && index("state-member-ids") < index("view-inputs"))
  }
}
