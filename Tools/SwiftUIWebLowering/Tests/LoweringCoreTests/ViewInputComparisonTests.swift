import Testing

@testable import LoweringCore

@Suite struct ViewInputComparisonTests {
  private func views(_ source: String) -> LoweringResult { lower(source, rules: ["view-inputs"]) }

  @Test func storedInputsAreCompared() {
    let source = """
      struct Card: View {
        let title: String
        var count: Int = 0
        let model: StudioStore
        @State private var hovered = false
        @Environment(\\.studioLayout) private var layout
        @Binding var selection: String
        @ViewBuilder let content: () -> Text
        static let spacing = 4.0
        var label: String { title.uppercased() }
        var body: some View { Text(title) }
      }

      struct Stored: View {
        @AppStorage("k") var value = 1
        var body: some View { Text("x") }
      }

      struct Holder {
        private struct Inner: View {
          let value: Int
          var body: some View { Text("\\(value)") }
        }
      }

      struct Box<Content: View>: View {
        let content: Content
        var body: some View { content }
      }

      struct Plain: Equatable {
        let value: Int
      }

      struct Empty: View {
        var body: some View { Text("e") }
      }

      """
    let result = views(source)
    #expect(result.counts["view-input-comparison"] == 3)
    #expect(result.text.contains("extension Card {\n  static var _comparesInputs: Bool { true }\n  static func _sameInputs(_ lhs: Self, _ rhs: Self) -> Bool { _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.count, rhs.count) && _swiftUIWebSame(lhs.model, rhs.model) && _swiftUIWebSame(lhs.content, rhs.content) }\n}"))
    #expect(result.text.contains("extension Box {"))
    #expect(result.text.contains("extension Empty {\n  static var _comparesInputs: Bool { true }\n  static func _sameInputs(_ lhs: Self, _ rhs: Self) -> Bool { true }\n}"))
    #expect(!result.text.contains("extension Stored"))
    #expect(!result.text.contains("Inner {\n  static var"))
    #expect(!result.text.contains("extension Plain"))
    let again = views(result.text)
    #expect(again.counts["view-input-comparison"] == nil)
    #expect(again.text == result.text)
  }

  @Test func attributesWithArgumentsAreRead() {
    // What the comparison pass sees in the full pipeline: state has its identity and environment reads are closures.
    let result = views(
      """
      struct Card: View {
        let title: String
        var size: Double = 22
        @Environment(StudioStore.self) private var store
        @Environment(_embedded: { $0.studioActions }) private var actions
        @State(memberID: 2901697652) private var hovered = false
        @ViewBuilder let content: () -> Text
        var body: some View { Text(title) }
      }

      """)
    #expect(result.counts["view-input-comparison"] == 1)
    #expect(result.text.contains("extension Card {\n  static var _comparesInputs: Bool { true }\n  static func _sameInputs(_ lhs: Self, _ rhs: Self) -> Bool { _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.size, rhs.size) && _swiftUIWebSame(lhs.content, rhs.content) }\n}"))
  }

  @Test func aPublicViewGetsAComparisonAsVisibleAsItself() {
    let source = """
      public struct SharedRootView: View {
        public init() {}
        public var body: some View { Text("root") }
      }

      package struct Badge: View {
        let count: Int
        package var body: some View { Text("\\(count)") }
      }

      struct Row: View {
        let title: String
        var body: some View { Text(title) }
      }

      """
    let result = views(source)
    #expect(result.counts["view-input-comparison"] == 3)
    #expect(result.text.contains("extension SharedRootView {\n  public static var _comparesInputs: Bool { true }\n  public static func _sameInputs(_ lhs: Self, _ rhs: Self) -> Bool { true }\n}"))
    #expect(result.text.contains("extension Badge {\n  package static var _comparesInputs: Bool { true }\n  package static func _sameInputs(_ lhs: Self, _ rhs: Self) -> Bool { _swiftUIWebSame(lhs.count, rhs.count) }\n}"))
    #expect(result.text.contains("extension Row {\n  static var _comparesInputs: Bool { true }\n"))
    #expect(views(result.text).text == result.text)
  }

  @Test func theComparisonStaysInTheConditionalBranchOfItsView() throws {
    let source = """
      #if os(Android)
      import Foundation

          struct AndroidCarousel: View {
              let cards: [String]
              var body: some View { Text("a") }
          }
      #endif

      struct Shelf {
      #if os(Android)
        struct Row: View {
          let title: String
          var body: some View { Text(title) }
        }
      #endif
      }

      struct Plain: View {
        let value: Int
        var body: some View { Text("\\(value)") }
      }

      """
    let result = views(source)
    #expect(result.counts["view-input-comparison"] == 2)
    let extensionStart = try #require(result.text.range(of: "extension AndroidCarousel {"))
    let endif = try #require(result.text.range(of: "#endif"))
    #expect(extensionStart.lowerBound < endif.lowerBound)
    #expect(!result.text.contains("extension Shelf.Row"))
    #expect(result.text.hasSuffix("static func _sameInputs(_ lhs: Self, _ rhs: Self) -> Bool { _swiftUIWebSame(lhs.value, rhs.value) }\n}\n"))
    #expect(views(result.text).text == result.text)
  }

  @Test func viewsNestedInTypesAreQualified() {
    let result = views(
      """
      enum Screens {
        struct Detail: View {
          let id: Int
          var body: some View { Text("\\(id)") }
        }
      }

      """)
    #expect(result.text.contains("extension Screens.Detail {"))
    // The extension follows the file-scope declaration that holds the view.
    #expect(result.text.hasSuffix("}\n\nextension Screens.Detail {\n  static var _comparesInputs: Bool { true }\n  static func _sameInputs(_ lhs: Self, _ rhs: Self) -> Bool { _swiftUIWebSame(lhs.id, rhs.id) }\n}\n"))
  }

  @Test func aFileWithoutATrailingNewlineGetsOne() {
    let result = views("struct V: View { let n: Int; var body: some View { Text(\"\") } }")
    #expect(result.text.hasSuffix("}\nextension V {\n  static var _comparesInputs: Bool { true }\n  static func _sameInputs(_ lhs: Self, _ rhs: Self) -> Bool { _swiftUIWebSame(lhs.n, rhs.n) }\n}\n\n"))
  }

  @Test func propertiesTheRuntimeCannotCompareLeaveTheViewAlone() {
    for property in ["lazy var cache = 0", "@Query var rows: [Int]", "let a = 1, b = 2", "@available(*, deprecated) var old = 1"] {
      let result = views("struct V: View {\n  \(property)\n  var body: some View { Text(\"\") }\n}\n")
      #expect(result.counts["view-input-comparison"] == nil, "\(property)")
    }
    let conditional = views("struct V: View {\n  #if DEBUG\n  let debug = 1\n  #endif\n  var body: some View { Text(\"\") }\n}\n")
    #expect(conditional.counts["view-input-comparison"] == nil)
  }

  @Test func observersDoNotMakeAPropertyComputed() {
    let result = views("struct V: View {\n  var count = 0 { didSet { print(count) } }\n  var body: some View { Text(\"\") }\n}\n")
    #expect(result.text.contains("_swiftUIWebSame(lhs.count, rhs.count)"))
  }

  /// The previous lowerer reads `headerSize` as a computed property because the next member is a nested type, and
  /// leaves it out of the inputs: the header would not render again when only its size changes.
  @Test func aStoredPropertyBeforeANestedTypeIsAnInput() {
    let result = views(
      """
      public struct BrandHeader: View {
        public var animated: Bool
        public var headerSize: HeaderSize

        public enum HeaderSize: Double { case standard = 1.0 }

        public var body: some View { Text("") }
      }

      """)
    #expect(result.text.contains("_swiftUIWebSame(lhs.animated, rhs.animated) && _swiftUIWebSame(lhs.headerSize, rhs.headerSize)"))
  }

  /// The previous lowerer masks the comment, so the header line no longer starts with `struct` and it sees no view.
  @Test func aViewDeclaredAfterABlockCommentOnItsLineIsCompared() {
    let result = views("/* SKIP @bridge */ public struct Root: View {\n  public var body: some View { Text(\"\") }\n}\n")
    #expect(result.counts["view-input-comparison"] == 1)
  }

  @Test func anUnclosedViewIsLeftAlone() {
    let source = "struct V: View {\n  let n: Int\n"
    #expect(views(source).text == source)
  }

  @Test func onlyViewsAreCompared() {
    #expect(views("struct S: Equatable { let a: Int }\n").text == "struct S: Equatable { let a: Int }\n")
    #expect(views("struct S: SwiftUI.View { var body: some View { Text(\"\") } }\n").counts["view-input-comparison"] == 1)
    #expect(views("struct S: Other.View { var body: some View { Text(\"\") } }\n").counts.isEmpty)
  }
}
