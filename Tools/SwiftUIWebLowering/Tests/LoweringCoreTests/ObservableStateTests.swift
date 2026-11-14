import Testing

@testable import LoweringCore

@Suite struct ObservableStateTests {
  private func state(_ source: String, models: Set<String> = []) -> LoweringResult {
    var pipeline = LoweringPipeline.standard
    pipeline = pipeline.selecting(["observable-state"])!
    return lower(pipeline, source, options: LoweringOptions(lowerCodable: false, observableTypes: models))
  }

  @Test func stateInitialValueOfAModelBecomesTheWrappedValueOfAStateObject() {
    let source = """
      @Observable final class Store { var count = 0 }
      struct ShellView: View {
        @State private var store: Store
        @State private var selection: Int
        init(start: Int) {
          _store = State(initialValue: Store())
          _selection = State(initialValue: start)
        }
      }

      """
    var pipeline = LoweringPipeline.standard
    pipeline = pipeline.selecting(["observable-state"])!
    let result = lower(pipeline, source, options: LoweringOptions(lowerCodable: false, observableTypes: []))
    #expect(result.text.contains("_store = StateObject(wrappedValue: Store())"))
    #expect(result.text.contains("_selection = State(initialValue: start)"))
  }

  @Test func theDeclaredTypeDecidesNotThePropertyName() {
    let source = """
      @Observable final class Store { var count = 0 }
      struct ShellView: View {
        @State private var store = Store()
        @State var shared: Router
        @State private var selection = 0
        @State private var player: AVPlayer? = nil
        @State private var viewModel = Draft()
        init(router: Router) {
          _shared = State(wrappedValue: router)
          self._selection = State(initialValue: 1)
        }
      }

      """
    var pipeline = LoweringPipeline.standard
    pipeline = pipeline.selecting(["observable-state", "observable", "state-member-ids"])!
    let result = lower(pipeline, source, options: LoweringOptions(lowerCodable: false, observableTypes: ["Router"]))
    #expect(result.text.contains("@StateObject private var store = Store()"))
    #expect(result.text.contains("@StateObject var shared: Router"))
    #expect(result.text.contains("_shared = StateObject(wrappedValue: router)"))
    #expect(result.text.contains("self._selection = State(initialValue: 1)"))
    #expect(result.text.contains("private var player: AVPlayer? = nil"))
    #expect(!result.text.contains("@StateObject private var viewModel"))
    #expect(!result.text.contains("@StateObject(memberID:"))
    #expect(result.counts["state-observable-model"] == 2)
    #expect(result.counts["state-observable-init"] == 1)
  }

  @Test func theClassesOfTheFileAreKnownEvenAfterTheAttributeIsGone() {
    let result = lower(
      """
      @Observable final class DashboardViewModel {}
      struct DashboardView: View {
        @State private var viewModel: DashboardViewModel
      }

      """)
    #expect(result.text.contains("@StateObject private var viewModel: DashboardViewModel"))
    #expect(!result.text.contains("@StateObject(memberID:"))
    #expect(result.counts["state-member-identities"] == nil)
    #expect(result.counts["state-observable-model"] == 1)
  }

  @Test func withoutObservableClassesNothingChanges() {
    let source = "struct V: View {\n  @State private var store = Store()\n  init() { self.store = Store() }\n}\n"
    #expect(state(source).text == source)
    #expect(state(source).counts.isEmpty)
  }

  @Test func anAssignmentInAnInitializerInitializesTheStateObject() {
    let result = state(
      """
      struct Screen: View {
        @State private var store: Store
        init(seed: Int) {
          self.store = Store()
        }
        var body: some View { Text("x") }
      }

      """,
      models: ["Store"])
    #expect(result.text.contains("@StateObject private var store: Store"))
    #expect(result.text.contains("    _store = StateObject(wrappedValue: Store())\n"))
    #expect(result.counts["state-observable-assignment"] == 1)
  }

  @Test func theWholeValueIsWrappedAndATrailingCommentStaysOutside() {
    let result = state(
      """
      struct Screen: View {
        @State var a: Store
        @State var b: Store
        @State var c: Store
        init(seed: Int) {
          a = Store(
            seed: seed
          )
          self.b = Store() // note
          c = Store(); _ = seed
        }
      }

      """,
      models: ["Store"])
    #expect(result.text.contains("    _a = StateObject(wrappedValue: Store(\n      seed: seed\n    ))\n"))
    #expect(result.text.contains("    _b = StateObject(wrappedValue: Store()) // note\n"))
    #expect(result.text.contains("    _c = StateObject(wrappedValue: Store()); _ = seed\n"))
    #expect(result.counts["state-observable-assignment"] == 3)
  }

  @Test func onlyTheAssignmentsOfModelPropertiesAreRewritten() {
    let result = state(
      """
      struct Screen: View {
        @State var store: Store
        @State var count: Int
        init() {
          store = Store()
          count = 1
          store == other
          store += 1
        }
        func reset() { store = Store() }
      }

      """,
      models: ["Store"])
    #expect(result.text.contains("    _store = StateObject(wrappedValue: Store())\n"))
    #expect(result.text.contains("    count = 1\n"))
    #expect(result.text.contains("    store == other\n"))
    #expect(result.text.contains("    store += 1\n"))
    #expect(result.text.contains("func reset() { store = Store() }"))
    #expect(result.counts["state-observable-assignment"] == 1)
  }

  @Test func theDeclarationShapesThePatternReads() {
    let result = state(
      """
      struct V: View {
        @State var a = Store()
        @State  var  b  =  Store ()
        @State var c: Store = Store()
        @State private var d: Store? = Store()
        @State var e: Store!
        @State var f: Store<Int>
        @State var g = Store<Int>()
        @State var h: Module.Store
        @State var i = Store.make()
        @State var j = Store(a: 1).configured()
        @State static var k = Store()
        @State public var l = Store()
        @State private(set) var m = Store()
        @State open var n = Store()
        @State @MainActor var o = Store()
        @State(wrappedValue: Store()) var p: Store
        @State var q: [Store] = []
        @State
        var r = Store()
        @State var (s, t) = (Store(), Store())
      }

      """,
      models: ["Store"])
    #expect(result.text.contains("@StateObject var a = Store()"))
    #expect(result.text.contains("@StateObject  var  b  =  Store ()"))
    #expect(result.text.contains("@StateObject var c: Store = Store()"))
    #expect(result.text.contains("@State private var d: Store? = Store()"))
    #expect(result.text.contains("@StateObject var e: Store!"))
    #expect(result.text.contains("@StateObject var f: Store<Int>"))
    #expect(result.text.contains("@State var g = Store<Int>()"))
    #expect(result.text.contains("@State var h: Module.Store"))
    #expect(result.text.contains("@State var i = Store.make()"))
    #expect(result.text.contains("@StateObject var j = Store(a: 1).configured()"))
    #expect(result.text.contains("@State static var k = Store()"))
    #expect(result.text.contains("@StateObject public var l = Store()"))
    #expect(result.text.contains("@State private(set) var m = Store()"))
    #expect(result.text.contains("@State open var n = Store()"))
    #expect(result.text.contains("@State @MainActor var o = Store()"))
    #expect(result.text.contains("@State(wrappedValue: Store()) var p: Store"))
    #expect(result.text.contains("@State var q: [Store] = []"))
    #expect(result.text.contains("@State\n  var r = Store()"))
    #expect(result.text.contains("@State var (s, t) = (Store(), Store())"))
    #expect(result.counts["state-observable-model"] == 7)
  }

  @Test func theInitializerSideFollowsTheModelPropertyOrTheConstructedType() {
    let result = state(
      """
      struct V: View {
        @State var model: Store
        @State var count = 0
        init(router: Store) {
          _model = State(wrappedValue: router)
          _count = State(wrappedValue: 1)
          self._count = State(wrappedValue: Store())
          _other = State(wrappedValue: router)
          _model = State(initialValue: 5)
          _count = State (wrappedValue: router)
          _count = State(
            wrappedValue: Store())
        }
      }

      """,
      models: ["Store"])
    #expect(result.text.contains("    _model = StateObject(wrappedValue: router)\n"))
    #expect(result.text.contains("    _count = State(wrappedValue: 1)\n"))
    #expect(result.text.contains("    self._count = StateObject(wrappedValue: Store())\n"))
    #expect(result.text.contains("    _other = State(wrappedValue: router)\n"))
    #expect(result.text.contains("    _model = StateObject(wrappedValue: 5)\n"))
    #expect(result.text.contains("    _count = State (wrappedValue: router)\n"))
    #expect(result.text.contains("    _count = State(\n      wrappedValue: Store())\n"))
    #expect(result.counts["state-observable-init"] == 3)
  }

  @Test func textInStringsAndCommentsIsLeftAlone() {
    let source = "struct V: View {\n  let a = \"@State var s = Store()\"\n  // @State var t = Store()\n}\n"
    #expect(state(source, models: ["Store"]).text == source)
  }

  @Test func theClassesOfThePackageComeFromTheOptions() {
    let source = "struct V: View {\n  @State var shared: Router\n}\n"
    #expect(state(source, models: ["Router"]).text.contains("@StateObject var shared: Router"))
    #expect(state(source, models: ["Other"]).text == source)
  }
}
