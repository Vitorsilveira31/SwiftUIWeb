import Testing

@testable import LoweringCore

@Suite struct ProtocolExtensionTests {
  private func promoted(_ source: String) -> LoweringResult { lower(source, rules: ["protocol-extension-requirement"]) }

  @Test func publicProtocolExtensionMembersArePromotedToRequirements() {
    let result = promoted(
      """
      public protocol Shape {
        var sides: Int { get }
      }
      public extension Shape {
        func describe() -> String { "shape" }
        var isPolygon: Bool {
          sides > 2
        }
        var sides: Int { 0 }
        internal func hidden() {}
        static func make() {}
        func generic<T>(_ value: T) {}
        func helper() {
          func nested() {}
        }
      }
      extension Shape {
        public func area()
          -> Double {
          0
        }
        public func describe() -> String { "again" }
        func internalOnly() {}
      }
      protocol Plain {}
      extension Plain {
        func untouched() {}
      }

      """
    )
    let requirements =
      "public protocol Shape {\n  var sides: Int { get }\n  func describe() -> String\n  var isPolygon: Bool { get }\n  func helper()\n  func area()\n    -> Double\n}"
    #expect(result.text.contains(requirements))
    #expect(result.counts["protocol-extension-requirement"] == 4)
    #expect(result.text.contains("protocol Plain {}"))
    #expect(!result.text.contains("  func nested()\n}"))
  }

  @Test func promotionSkipsUnbalancedProtocolsAndExtensions() {
    // The protocol body never closes, so there is nowhere to add the requirement.
    let unclosedProtocol = "public protocol P {\npublic extension P {\n  func f() {}\n}\n"
    #expect(promoted(unclosedProtocol).text == unclosedProtocol)
    // The extension body never closes, so none of its members are read.
    let unclosedExtension = "public protocol P {}\npublic extension P {\n  func f() {}\n"
    #expect(promoted(unclosedExtension).text == unclosedExtension)
    // A method without a body has no signature end to copy.
    let bodiless = "public protocol P {}\npublic extension P {\n  func f() -> Int\n}\n"
    #expect(promoted(bodiless).text == bodiless)
    #expect(promoted(bodiless).counts.isEmpty)
  }

  @Test func theRequirementIsTheSignatureAsWrittenWithoutAccessAndIsolation() {
    let result = promoted(
      """
      public protocol Store {}
      public extension Store {
        @discardableResult
        func save() -> Bool { true }
        @MainActor nonisolated public func load(id: String) async throws -> [String: Int] {
          [:]
        }
        public mutating func reset() {}
        func fetch(
          _ id: String,
          limit: Int
        ) async throws -> [Item] {
          []
        }
      }

      """
    )
    #expect(
      result.text.contains(
        "public protocol Store {  func save() -> Bool\n  @MainActor func load(id: String) async throws -> [String: Int]\n  mutating func reset()\n  func fetch(\n    _ id: String,\n    limit: Int\n  ) async throws -> [Item]\n}"
      ))
    #expect(result.counts["protocol-extension-requirement"] == 4)
  }

  @Test func onlyUnconstrainedExtensionsOfTheProtocolAreRead() {
    let result = promoted(
      """
      public protocol Shape {}
      public extension Shape where Self: Equatable { func same() -> Bool { true } }
      public extension Shape { func plain() -> Bool { true } }
      extension Shape: Sendable {}
      public extension Namespace.Shape { func qualified() {} }
      private extension Shape { func hidden() {} }
      public extension Array where Element: Shape { func total() -> Int { 0 } }
      public extension Shape {
        var oneLiner: Int { 3 }
        func listing() -> Array<Int> { [] }
        func hash(into hasher: inout Hasher) {}
        static func == (lhs: Self, rhs: Self) -> Bool { true }
        subscript(i: Int) -> Int { i }
        func compare(_ a: Int, _ b: Int) -> Bool { a < b }
        func quoted() { print("}") }
        var opaque: some View { Text("") }
        var spread: some View {
          Text("")
        }
        func wrap(_ content: some View) -> some View { content }
      }

      """
    )
    #expect(
      result.text.contains(
        "public protocol Shape {  func plain() -> Bool\n  var oneLiner: Int { get }\n  func listing() -> Array<Int>\n  func compare(_ a: Int, _ b: Int) -> Bool\n  func quoted()\n}"))
    #expect(result.counts["protocol-extension-requirement"] == 5)
  }

  @Test func aDeclaredNameIsMatchedAsAWholeName() {
    let result = promoted(
      """
      protocol Source {
        func imageURL() -> String
        func title(prefix: String) -> String
      }
      public extension Source {
        func image() -> String { imageURL() }
        func title(suffix: String) -> String { suffix }
        var imageURLs: [String] { [] }
      }

      """
    )
    #expect(result.text.contains("  func title(prefix: String) -> String\n  func image() -> String\n  var imageURLs: [String] { get }\n}"))
    // A name the protocol declares is not declared twice, whatever its parameters.
    #expect(!result.text.contains("func title(suffix: String) -> String\n"))
    #expect(result.counts["protocol-extension-requirement"] == 2)
  }

  @Test func protocolsAndExtensionsAreReadWhereverTheyAreDeclared() {
    let result = promoted(
      """
      enum Namespace {
        public protocol Named {
          var raw: String { get }
        }
        public extension Named {
          func label() -> String { raw }
        }
      }
      @MainActor
      public protocol Moded
      {
      }
      @available(macOS 12, *)
      public extension Moded
      {
        func mode() -> Int { 0 }
      }
      #if DEBUG
      public protocol Debug {}
      public extension Debug {
        func dump() {}
      }
      #endif

      """
    )
    #expect(result.text.contains("    var raw: String { get }\n    func label() -> String\n}"))
    #expect(result.text.contains("public protocol Moded\n{\n  func mode() -> Int\n}"))
    #expect(result.text.contains("public protocol Debug {  func dump()\n}"))
    #expect(result.counts["protocol-extension-requirement"] == 3)
  }

  @Test func promotionIsIdempotentAndTheFrameworkIsLeftAlone() {
    let source = "protocol G { func name() -> String }\nextension G {\n  public func greet() -> String { name() }\n}\n"
    let first = promoted(source)
    #expect(first.text.contains("protocol G { func name() -> String   func greet() -> String\n}"))
    #expect(first.counts["protocol-extension-requirement"] == 1)
    let second = promoted(first.text)
    #expect(second.text == first.text)
    #expect(second.counts.isEmpty)
    let pipeline = LoweringPipeline.standard.selecting(["protocol-extension-requirement"])!
    #expect(lower(pipeline, source, options: LoweringOptions(lowerCodable: false)).text == source)
  }
}
