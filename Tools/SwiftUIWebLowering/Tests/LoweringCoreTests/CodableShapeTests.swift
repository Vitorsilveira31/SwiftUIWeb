import Testing

@testable import LoweringCore

/// The shapes of declaration the embedded Codable pass has to read, one test per way the previous lowerer's unit tests
/// wrote them.
@Suite struct CodableShapeTests {
  /// The first extension of `name` that holds a generated member.
  private func generatedExtension(_ output: String, _ name: String) -> String {
    let header = "\nextension \(name) {\n"
    var search = output.startIndex..<output.endIndex
    while let found = output.range(of: header, range: search) {
      let rest = output[output.index(after: found.lowerBound)...]
      let block = rest[..<(rest.range(of: "\n}\n").map { rest.index($0.lowerBound, offsetBy: 2) } ?? rest.endIndex)]
      if block.contains("_embeddedJSONValue") || block.contains("_embeddedDecodeJSONValue") { return String(block) }
      search = found.upperBound..<output.endIndex
    }
    Issue.record("no generated extension for \(name):\n\(output)")
    return ""
  }

  @Test func associatedValuesHoldingDictionariesAreNotSplitAtTheirColon() {
    let output = lowered(
      """
      enum JSONValue: Codable {
        case string(String)
        case object([String: JSONValue])
      }
      """)
    #expect(output.contains("case .string(let v0)"))
    #expect(output.contains("case .object(let v0)"))
    #expect(output.contains("String: JSONValue"))
  }

  @Test func rawValueEnumsAndEmptyStructsAreCoded() {
    let raw = lower("enum Kind: Codable, Int { case one }")
    #expect(raw.counts["codable-to-embedded"] == 1)
    let empty = lower("struct Empty: Codable {}")
    #expect(empty.counts["codable-to-embedded"] == 1)
    #expect(empty.text.contains("guard case .object = value"))
    let plain = lowered("enum Status: Codable { case ready; case finished }\n")
    #expect(plain.contains("case .ready: return .object([\"ready\": .object([:])])"))
    #expect(plain.contains("case \"finished\": return .finished"))
  }

  @Test func codableTypesOfOneFileAreCountedOnceEach() {
    let result = lower(
      """
      public struct Record: Codable {
        public let title: String
        var count: Int = 0
        enum CodingKeys: String, CodingKey { case title = "display_title"; case count }
        func ignored(value: Int) -> Int { value }
      }
      enum Kind: Codable, String { case text, image }
      enum Event: Codable { case empty; case text(String); case named(value: String, count: Int) }
      """)
    #expect(result.counts["codable-to-embedded"] == 3)
    #expect(result.text.contains("EmbeddedCodable"))
    #expect(result.text.contains("display_title"))
    #expect(result.text.contains("Self(rawValue"))
    #expect(result.text.contains("\"count\""))
  }

  @Test func integerCodingKeysNameNoField() {
    let output = lowered(
      """
      struct Row: Codable {
        let id: Int
        enum CodingKeys: Int, CodingKey { case id = 1 }
      }
      """)
    // The key is not understood, so the type is coded as an object without fields.
    #expect(!output.contains("\"id\": try self.id"))
    #expect(output.contains("{ .object([:]) }"))
    #expect(output.contains("return Self()"))
  }

  @Test func typesConformingThroughACodableProtocolGetTheHalvesItRefines() {
    let output = lowered(
      """
      protocol Payload: Codable {}
      protocol Outgoing: Encodable {}
      protocol Named { var name: String { get } }
      struct Event: Payload { let id: Int }
      struct Ping: Outgoing, Sendable { let at: Int }
      struct Label: Named { let name: String }
      """)
    let event = generatedExtension(output, "Event")
    #expect(event.contains("func _embeddedJSONValue()"))
    #expect(event.contains("func _embeddedDecodeJSONValue("))
    let ping = generatedExtension(output, "Ping")
    #expect(ping.contains("func _embeddedJSONValue()"))
    #expect(!ping.contains("_embeddedDecodeJSONValue"))
    #expect(!output.contains("extension Label"))
    #expect(output.contains("protocol Payload: EmbeddedCodable {}"))
  }

  @Test func aHandWrittenEncoderIsDroppedAndAnExtensionDecoderIsUsed() {
    let output = lowered(
      """
      struct Profile: Codable {
        let name: String
        func encode(to encoder: Encoder) throws {
          var container = encoder.container(keyedBy: CodingKeys.self)
          try container.encode(name, forKey: .name)
        }
      }
      extension Profile {
        init(from decoder: Decoder) throws {
          let container = try decoder.container(keyedBy: CodingKeys.self)
          name = try container.decode(String.self, forKey: .name)
        }
      }
      """)
    #expect(!output.contains("func encode(to"))
    let profile = generatedExtension(output, "Profile")
    #expect(profile.contains("[\"name\": try self.name._embeddedJSONValue()]"))
    #expect(profile.contains("throws -> Self { try Self(from: EmbeddedDecoder(value)) }"))
    #expect(output.contains("fileprivate enum CodingKeys: String, EmbeddedCodingKey { case name }"))
    #expect(output.contains("init(from decoder: EmbeddedDecoder) throws {\n    let container"))
  }

  @Test func conformancesDeclaredInExtensionsMoveToTheDeclarationWhereverItIs() {
    let output = lowered(
      """
      struct Plain {
        let a: Int
      }
      extension Plain: Codable {}
      extension Later: Decodable, Encodable {}
      struct Later: Equatable { let b: Int }
      extension External: Codable {}
      """)
    #expect(output.contains("struct Plain: EmbeddedCodable {"))
    #expect(output.contains("extension Plain {}"))
    #expect(output.contains("struct Later: Equatable, EmbeddedDecodable, EmbeddedEncodable {"))
    #expect(output.contains("extension Later {}"))
    #expect(output.contains("extension External {}"))
    #expect(generatedExtension(output, "Plain").contains("Self(a: try _embeddedField(Int.self, object, \"a\"))"))
    #expect(generatedExtension(output, "Later").contains("Self(b: try _embeddedField(Int.self, object, \"b\"))"))
  }

  @Test func aClassDecodesThroughTheDesignatedInitializerThatTakesItsFields() {
    let output = lowered(
      """
      final class Item: Codable {
        let id: Int
        let title: String
        let tags: [String]
        struct Draft {
          init(raw: String) {}
        }
        init(from: Draft) {
          self.id = 0
          self.title = ""
          self.tags = []
        }
        init(title: String, id: Int, tags: [String]) {
          self.title = title
          self.id = id
          self.tags = tags
        }
      }
      struct Settings: Codable {
        var theme: String
        init(from decoder: Decoder) throws { theme = "" }
      }
      """)
    let item = generatedExtension(output, "Item")
    #expect(item.contains("return Self(title: try _embeddedField(String.self, object, \"title\"), id: try _embeddedField(Int.self, object, \"id\"), tags: try _embeddedField([String].self, object, \"tags\"))"))
    // A class has no memberwise initializer to forward a decoder to.
    #expect(!item.contains("init(from decoder: EmbeddedDecoder)"))
    #expect(generatedExtension(output, "Settings").contains("try Self(from: EmbeddedDecoder(value))"))
  }

  @Test func aStructWithAWrittenInitializerAssignsItsFieldsOneByOne() {
    let output = lowered(
      """
      struct Span: Codable {
        let lower: Int
        let upper: Int?
        init(lower: Int) {
          self.lower = lower
          self.upper = nil
        }
      }
      """)
    let span = generatedExtension(output, "Span")
    #expect(span.contains("  fileprivate init(_embeddedObject object: [String: EmbeddedJSONValue]) throws {\n    self.lower = try _embeddedField(Int.self, object, \"lower\")\n    self.upper = try _embeddedField(Optional<Int>.self, object, \"upper\")\n  }"))
    #expect(span.contains("return try Self(_embeddedObject: object)"))
    #expect(span.contains("public init(from decoder: EmbeddedDecoder)"))
  }

  @Test func aConformanceOnTheLineAfterTheTypeNameIsStillSynthesized() {
    let output = lowered("struct Wrapper\n  : Codable {\n  let value: Int\n}\n")
    #expect(generatedExtension(output, "Wrapper").contains("Self(value: try _embeddedField(Int.self, object, \"value\"))"))
  }

  @Test func aClassFunctionIsNotANestedClass() {
    let output = lowered(
      """
      final class Factory: Codable {
        let id: Int
        class func make() -> Factory { Factory(id: 1) }
        init(id: Int) { self.id = id }
      }
      struct Open: Codable {
        let flag: Bool
      }
      """)
    #expect(output.contains("extension Factory {"))
    #expect(!output.contains("Factory.make"))
    #expect(output.contains("extension Open {"))
  }

  @Test func aSynthesizedInitializerIsAvailableToTheParentThatDecodesWithIt() {
    let output = lowered(
      """
      struct Plain: Decodable { let id: String }
      struct Composite: Decodable {
        let plain: Plain
        init(from decoder: any Decoder) throws { plain = try Plain(from: decoder) }
      }
      """)
    #expect(output.contains("public init(from decoder: EmbeddedDecoder) throws { self = try Self._embeddedDecodeJSONValue(decoder._value) }"))
  }

  @Test func aMultilineStringLiteralComesBackUnchanged() {
    let source = "enum Strings {\n  static let table: StaticString = \"\"\"\n    a\\u{3}b\\u{4}\\\n    c\\u{3}d\n    \"\"\"\n}\n"
    let once = lowered(source)
    #expect(once == source)
    #expect(lowered(once) == once)
  }

  @Test func theCodableImportFollowsTheModuleAliasChoiceOfEachCall() {
    let source = "import SwiftUI\nstruct Point: Codable { let x: Int }\n"
    for _ in 0..<2 {
      let plain = lowered(source)
      #expect(plain.hasPrefix("import SwiftUIWeb\nimport SwiftUI\n"), "\(plain)")
      let aliased = lowered(source, aliased: true)
      #expect(aliased.hasPrefix("import SwiftUI\nstruct Point"), "\(aliased)")
      #expect(aliased.components(separatedBy: "import ").count - 1 == 1, "\(aliased)")
    }
  }

  @Test func aPrivateOrPublicMainBrowserAppStillGetsItsBrowserExports() {
    for access in ["", "private ", "fileprivate ", "public "] {
      let output = lowered("@main\n\(access)struct Demo: BrowserApp {\n  var body: some Scene { WindowGroup { Text(\"x\") } }\n}\n")
      #expect(output.contains("embedded_browser_start"), "\(access)")
    }
  }

  @Test func everyStoredPropertyIsEncodedAndOnlyThePlainTypedOnesAreDecodedByName() {
    let output = lowered(
      """
      struct Obs: Codable {
        var level: Int = 0 { didSet { print(level) } }
        lazy var cache: String = "x"
        static var shared: Int = 1
        private(set) var secret: Int = 2
        @available(*, deprecated) var old: Int = 3
        public var visible: Int = 4
        private var hidden: Int = 5
        var computed: Int { 6 }
        init(level: Int) { self.level = level }
      }
      """)
    let section = generatedExtension(output, "Obs")
    #expect(section.contains(".object([\"level\": try self.level._embeddedJSONValue(), \"visible\": try self.visible._embeddedJSONValue(), \"hidden\": try self.hidden._embeddedJSONValue(), \"cache\": try self.cache._embeddedJSONValue(), \"secret\": try self.secret._embeddedJSONValue(), \"old\": try self.old._embeddedJSONValue()])"))
    #expect(section.contains("    self.level = try _embeddedField(Int.self, object, \"level\")\n    self.visible = try _embeddedField(Int.self, object, \"visible\")\n    self.hidden = try _embeddedField(Int.self, object, \"hidden\")\n  }"))
    #expect(!section.contains("shared"))
    #expect(!section.contains("computed"))
  }

  @Test func theInitializersOfAStructDecideHowItIsBuilt() {
    let output = lowered(
      """
      struct Private: Codable {
        let a: Int
        private init(a: Int) { self.a = a }
      }
      struct Public: Codable {
        let a: Int
        public init(a: Int) { self.a = a }
      }
      struct Convenience: Codable {
        let a: Int
        convenience init(a: Int) { self.a = a }
      }
      struct Failable: Codable {
        let a: Int
        init?(a: Int) { self.a = a }
      }
      """)
    for name in ["Private", "Public"] {
      let section = generatedExtension(output, name)
      #expect(section.contains("fileprivate init(_embeddedObject object: [String: EmbeddedJSONValue]) throws {\n    self.a = try _embeddedField(Int.self, object, \"a\")\n  }"), "\(name)")
      #expect(section.contains("return try Self(_embeddedObject: object)"), "\(name)")
    }
    for name in ["Convenience", "Failable"] {
      let section = generatedExtension(output, name)
      #expect(!section.contains("_embeddedObject"), "\(name)")
      #expect(section.contains("return Self(a: try _embeddedField(Int.self, object, \"a\"))"), "\(name)")
    }
  }

  @Test func classesAndExtensionsWithAnAccessModifierCarryTheConformanceToo() {
    let output = lowered(
      """
      final class Box { let v: Int
        init(v: Int) { self.v = v } }
      extension Box: Codable {}
      public extension Item: Codable {}
      final class Item { let id: Int
        init(id: Int) { self.id = id } }
      public final class Pub: Codable { public let w: Int
        public init(w: Int) { self.w = w } }
      enum Ev {}
      extension Ev: Codable {}
      class Base { let q: Int
        init(q: Int) { self.q = q } }
      class Sub: Base, Codable { let r: Int
        init(r: Int) { self.r = r; super.init(q: 0) } }
      """)
    #expect(output.contains("final class Box: EmbeddedCodable { let v: Int"))
    #expect(output.contains("\nextension Box {}\n"))
    #expect(output.contains("\npublic extension Item {}\n"))
    #expect(output.contains("final class Item: EmbeddedCodable { let id: Int"))
    #expect(output.contains("public final class Pub: EmbeddedCodable {"))
    #expect(output.contains("enum Ev: EmbeddedCodable {}"))
    #expect(output.contains("class Sub: Base, EmbeddedCodable {"))
    #expect(generatedExtension(output, "Item").contains("return Self(id: try _embeddedField(Int.self, object, \"id\"))"))
    #expect(generatedExtension(output, "Pub").contains("return Self(w: try _embeddedField(Int.self, object, \"w\"))"))
  }
}
